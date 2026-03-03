#!/usr/bin/env bash
# Shared port-forward utilities for IBM License Service scripts
#
# Usage: source this file from other scripts
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/portforward.sh"
#
# Provides:
#   start_port_forward <namespace> <service> <local_port> <remote_port>
#     - Starts kubectl port-forward with retry logic
#     - Verifies connectivity before returning
#     - Sets PF_PID with the background process PID
#     - Registers a cleanup trap automatically
#
# Configuration (via environment variables):
#   PF_MAX_RETRIES    - Max retry attempts (default: 3)
#   PF_RETRY_DELAY    - Seconds between retries (default: 5)
#   PF_HEALTH_TIMEOUT - Seconds to wait for port readiness per attempt (default: 15)

PF_MAX_RETRIES="${PF_MAX_RETRIES:-3}"
PF_RETRY_DELAY="${PF_RETRY_DELAY:-5}"
PF_HEALTH_TIMEOUT="${PF_HEALTH_TIMEOUT:-15}"
PF_PID=""

# Internal: log helpers (use caller's if defined, otherwise provide defaults)
_pf_info()  { if declare -F log_info  >/dev/null 2>&1; then log_info  "$1"; else echo "[INFO] $1"; fi; }
_pf_warn()  { if declare -F log_warn  >/dev/null 2>&1; then log_warn  "$1"; else echo "[WARN] $1"; fi; }
_pf_error() { if declare -F log_error >/dev/null 2>&1; then log_error "$1"; else echo "[ERROR] $1" >&2; fi; }

# Kill any existing port-forward managed by this library
_pf_cleanup() {
    if [ -n "$PF_PID" ] && kill -0 "$PF_PID" 2>/dev/null; then
        kill "$PF_PID" 2>/dev/null || true
        wait "$PF_PID" 2>/dev/null || true
        PF_PID=""
    fi
}

# Wait until the local port accepts a TCP connection
_pf_wait_for_port() {
    local port=$1
    local timeout=$2
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        # Use /dev/tcp if available (bash), fall back to curl
        if (echo >/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
            return 0
        elif curl -s --connect-timeout 1 "http://localhost:${port}/" -o /dev/null 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Start a port-forward with retry logic and health verification.
#
# Arguments:
#   $1 - Kubernetes namespace
#   $2 - Service name (e.g. "ibm-licensing-service-instance")
#   $3 - Local port
#   $4 - Remote port (default: 8080)
#
# On success: sets PF_PID and returns 0
# On failure: returns 1
start_port_forward() {
    local namespace=$1
    local service=$2
    local local_port=$3
    local remote_port=${4:-8080}
    local attempt=0

    # Register cleanup on EXIT (preserves any existing trap)
    trap '_pf_cleanup' EXIT

    while [ "$attempt" -lt "$PF_MAX_RETRIES" ]; do
        attempt=$((attempt + 1))

        # Kill previous attempt if still running
        _pf_cleanup

        if [ "$attempt" -gt 1 ]; then
            _pf_warn "Port-forward attempt $attempt/$PF_MAX_RETRIES (retrying in ${PF_RETRY_DELAY}s)..."
            sleep "$PF_RETRY_DELAY"
        fi

        # Start port-forward in background, capture stderr for diagnostics
        local pf_log="/tmp/pf-${local_port}-$$.log"
        kubectl port-forward -n "$namespace" \
            "svc/$service" "${local_port}:${remote_port}" \
            >"$pf_log" 2>&1 &
        PF_PID=$!

        # Wait for the port to become reachable
        if _pf_wait_for_port "$local_port" "$PF_HEALTH_TIMEOUT"; then
            _pf_info "Port-forward established (localhost:$local_port -> $service:$remote_port)"
            rm -f "$pf_log"
            return 0
        fi

        # Port never came up — check if the process died
        if ! kill -0 "$PF_PID" 2>/dev/null; then
            _pf_warn "Port-forward process exited prematurely"
            if [ -f "$pf_log" ]; then
                _pf_warn "$(cat "$pf_log")"
            fi
        else
            _pf_warn "Port-forward process running but port $local_port not reachable"
            _pf_cleanup
        fi

        rm -f "$pf_log"
    done

    _pf_error "Failed to establish port-forward after $PF_MAX_RETRIES attempts"
    _pf_error "Possible causes:"
    _pf_error "  - License Service pod is not ready or was rescheduled"
    _pf_error "  - Node hosting the pod is unreachable (common with spot/preemptible nodes)"
    _pf_error "  - Port $local_port is already in use (check: lsof -i :$local_port)"
    _pf_error "  - Cluster API server connectivity issue"
    return 1
}
