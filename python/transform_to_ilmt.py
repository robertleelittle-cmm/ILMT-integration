#!/usr/bin/env python3
"""
IBM License Service to ILMT Data Transformer

Transforms IBM License Service export data into ILMT-compatible format
for manual import into IBM License Metric Tool.
"""

import argparse
import csv
import json
import os
import sys
from datetime import datetime
from pathlib import Path


def load_license_data(input_file: str) -> dict:
    """Load license data from JSON file."""
    with open(input_file, 'r') as f:
        return json.load(f)


def transform_to_ilmt_csv(license_data: dict, output_file: str, report_date: str = None):
    """
    Transform License Service data to ILMT-compatible CSV format.
    
    Args:
        license_data: Dictionary containing license service export data
        output_file: Path to output CSV file
        report_date: Date for the report (YYYY-MM-DD), defaults to today
    """
    if report_date is None:
        report_date = datetime.now().strftime('%Y-%m-%d')
    
    products = license_data.get('products', [])
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        
        # ILMT-compatible header
        writer.writerow([
            'Product Name',
            'Product ID', 
            'Metric Type',
            'Metric Quantity',
            'Cluster Name',
            'Namespace',
            'Report Date',
            'Container Name',
            'CPU Limit',
            'Memory Limit'
        ])
        
        for product in products:
            # Get containers/deployments using this product
            containers = product.get('containers', [])
            
            if containers:
                for container in containers:
                    writer.writerow([
                        product.get('productName', ''),
                        product.get('productID', ''),
                        product.get('productMetric', 'VIRTUAL_PROCESSOR_CORE'),
                        product.get('metricQuantity', 0),
                        product.get('clusterName', ''),
                        container.get('namespace', ''),
                        report_date,
                        container.get('containerName', ''),
                        container.get('cpuLimit', ''),
                        container.get('memoryLimit', '')
                    ])
            else:
                # Product without container details
                writer.writerow([
                    product.get('productName', ''),
                    product.get('productID', ''),
                    product.get('productMetric', 'VIRTUAL_PROCESSOR_CORE'),
                    product.get('metricQuantity', 0),
                    product.get('clusterName', ''),
                    '',  # namespace
                    report_date,
                    '',  # containerName
                    '',  # cpuLimit
                    ''   # memoryLimit
                ])
    
    print(f"ILMT CSV exported to: {output_file}")
    print(f"Total products: {len(products)}")


def transform_to_ilmt_json(license_data: dict, output_file: str, report_date: str = None):
    """
    Transform License Service data to ILMT-compatible JSON format.
    """
    if report_date is None:
        report_date = datetime.now().strftime('%Y-%m-%d')
    
    products = license_data.get('products', [])
    
    ilmt_data = {
        'reportDate': report_date,
        'source': 'IBM License Service',
        'generatedAt': datetime.now().isoformat(),
        'products': []
    }
    
    for product in products:
        ilmt_product = {
            'productName': product.get('productName', ''),
            'productId': product.get('productID', ''),
            'metricType': product.get('productMetric', 'VIRTUAL_PROCESSOR_CORE'),
            'metricQuantity': product.get('metricQuantity', 0),
            'deployments': []
        }
        
        for container in product.get('containers', []):
            ilmt_product['deployments'].append({
                'namespace': container.get('namespace', ''),
                'containerName': container.get('containerName', ''),
                'cpuLimit': container.get('cpuLimit', ''),
                'memoryLimit': container.get('memoryLimit', '')
            })
        
        ilmt_data['products'].append(ilmt_product)
    
    with open(output_file, 'w') as f:
        json.dump(ilmt_data, f, indent=2)
    
    print(f"ILMT JSON exported to: {output_file}")


def generate_summary_report(license_data: dict, output_file: str):
    """Generate a human-readable summary report."""
    products = license_data.get('products', [])
    
    with open(output_file, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write("IBM License Service - ILMT Integration Report\n")
        f.write("=" * 60 + "\n\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Total Products: {len(products)}\n\n")
        
        f.write("-" * 60 + "\n")
        f.write("PRODUCT SUMMARY\n")
        f.write("-" * 60 + "\n\n")
        
        total_vpcs = 0
        for product in products:
            name = product.get('productName', 'Unknown')
            pid = product.get('productID', 'Unknown')
            metric = product.get('productMetric', 'Unknown')
            qty = product.get('metricQuantity', 0)
            total_vpcs += qty
            
            f.write(f"Product: {name}\n")
            f.write(f"  ID: {pid}\n")
            f.write(f"  Metric: {metric}\n")
            f.write(f"  Quantity: {qty}\n")
            
            containers = product.get('containers', [])
            if containers:
                f.write(f"  Containers ({len(containers)}):\n")
                for c in containers[:5]:  # Show first 5
                    f.write(f"    - {c.get('containerName', 'N/A')} ({c.get('namespace', 'N/A')})\n")
                if len(containers) > 5:
                    f.write(f"    ... and {len(containers) - 5} more\n")
            f.write("\n")
        
        f.write("-" * 60 + "\n")
        f.write(f"TOTAL VPCs: {total_vpcs}\n")
        f.write("-" * 60 + "\n")
    
    print(f"Summary report generated: {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description='Transform IBM License Service data to ILMT format'
    )
    parser.add_argument(
        'input_file',
        help='Input JSON file from License Service export'
    )
    parser.add_argument(
        '-o', '--output-dir',
        default='.',
        help='Output directory for generated files (default: current directory)'
    )
    parser.add_argument(
        '-f', '--format',
        choices=['csv', 'json', 'both'],
        default='both',
        help='Output format (default: both)'
    )
    parser.add_argument(
        '-d', '--date',
        help='Report date in YYYY-MM-DD format (default: today)'
    )
    parser.add_argument(
        '-s', '--summary',
        action='store_true',
        help='Generate summary report'
    )
    
    args = parser.parse_args()
    
    # Load input data
    print(f"Loading license data from: {args.input_file}")
    license_data = load_license_data(args.input_file)
    
    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Generate base filename
    base_name = Path(args.input_file).stem
    date_suffix = args.date or datetime.now().strftime('%Y-%m-%d')
    
    # Generate outputs
    if args.format in ['csv', 'both']:
        csv_file = output_dir / f"ilmt-{base_name}-{date_suffix}.csv"
        transform_to_ilmt_csv(license_data, str(csv_file), args.date)
    
    if args.format in ['json', 'both']:
        json_file = output_dir / f"ilmt-{base_name}-{date_suffix}.json"
        transform_to_ilmt_json(license_data, str(json_file), args.date)
    
    if args.summary:
        summary_file = output_dir / f"ilmt-summary-{date_suffix}.txt"
        generate_summary_report(license_data, str(summary_file))
    
    print("\nTransformation complete!")


if __name__ == '__main__':
    main()
