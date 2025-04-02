#!/usr/bin/env python3
"""
S3 Logs Collection Test Script

This script tests the S3 logs collection infrastructure by:
1. Uploading test files to the source bucket
2. Performing various operations to generate access logs
3. Monitoring the SQS queue for notifications
4. Checking the logs bucket for access logs

Usage: python test_s3_logging.py [--timeout MINUTES]
"""

import argparse
import boto3
import json
import os
import random
import string
import subprocess
import sys
import time
from datetime import datetime
from botocore.exceptions import ClientError
from colorama import Fore, Style, init

# Initialize colorama
init(autoreset=True)

def run_terraform_output(output_name, default_value=None):
    """Get a value from terraform output."""
    try:
        result = subprocess.run(
            ["terraform", "output", "-raw", output_name],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        if "No value found for output" in e.stderr or "Command '['terraform', 'output'" in str(e):
            if default_value:
                print(f"{Fore.YELLOW}Warning: Couldn't find Terraform output '{output_name}', using default: {default_value}")
                return default_value
            return None
        print(f"{Fore.RED}Error getting Terraform output {output_name}: {e}")
        sys.exit(1)

def create_aws_clients(region):
    """Create boto3 clients for AWS services."""
    try:
        s3_client = boto3.client('s3', region_name=region)
        s3_resource = boto3.resource('s3', region_name=region)
        sqs_client = boto3.client('sqs', region_name=region)
        return s3_client, s3_resource, sqs_client
    except Exception as e:
        print(f"{Fore.RED}Error creating AWS clients: {e}")
        sys.exit(1)

def generate_test_file(size_kb=10):
    """Generate a test file with random content."""
    filename = f"test-file-{datetime.now().strftime('%Y%m%d%H%M%S')}.txt"
    content = ''.join(random.choices(string.ascii_letters + string.digits, k=size_kb * 1024))
    
    with open(filename, 'w') as f:
        f.write(content)
    
    print(f"{Fore.GREEN}Created test file: {filename} ({size_kb} KB)")
    return filename

def upload_file(s3_client, filename, bucket, key=None):
    """Upload a file to S3 bucket."""
    if not key:
        key = filename
    
    try:
        s3_client.upload_file(filename, bucket, key)
        print(f"{Fore.GREEN}Uploaded {filename} to s3://{bucket}/{key}")
        return True
    except ClientError as e:
        print(f"{Fore.RED}Error uploading file: {e}")
        return False

def generate_s3_operations(s3_client, bucket, key):
    """Perform various S3 operations to generate access logs."""
    operations = [
        # Get object metadata
        lambda: s3_client.head_object(Bucket=bucket, Key=key),
        # Get object tagging
        lambda: s3_client.get_object_tagging(Bucket=bucket, Key=key),
        # List objects in bucket
        lambda: s3_client.list_objects_v2(Bucket=bucket, Prefix=key[:1]),
        # Get bucket location
        lambda: s3_client.get_bucket_location(Bucket=bucket),
        # Get object acl
        lambda: s3_client.get_object_acl(Bucket=bucket, Key=key)
    ]
    
    print(f"{Fore.YELLOW}Performing S3 operations to generate access logs...")
    for i, operation in enumerate(operations, 1):
        try:
            operation()
            print(f"{Fore.GREEN}Operation {i}/{len(operations)} completed successfully")
        except ClientError as e:
            print(f"{Fore.YELLOW}Operation {i}/{len(operations)} failed: {e}")
            
    print(f"{Fore.GREEN}Completed all S3 operations")

def check_sqs_messages(sqs_client, queue_url, wait_time=5):
    """Check for messages in the SQS queue."""
    try:
        response = sqs_client.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=wait_time
        )
        
        messages = response.get('Messages', [])
        if messages:
            print(f"{Fore.GREEN}Found {len(messages)} messages in SQS queue")
            # Display the first message
            if len(messages) > 0:
                body = json.loads(messages[0]['Body'])
                print(f"{Fore.CYAN}Sample message content:")
                print(json.dumps(body, indent=2)[:500] + "...")
            
            # Return messages to the queue by not deleting them
            return True
        else:
            print(f"{Fore.YELLOW}No messages found in SQS queue")
            return False
    except ClientError as e:
        print(f"{Fore.RED}Error checking SQS messages: {e}")
        return False

def check_access_logs(s3_client, logs_bucket, source_bucket):
    """Check for access logs in the logs bucket."""
    logs_prefix = f"s3-access-logs/{source_bucket}/"
    
    try:
        response = s3_client.list_objects_v2(
            Bucket=logs_bucket,
            Prefix=logs_prefix,
            MaxKeys=10
        )
        
        objects = response.get('Contents', [])
        if objects:
            print(f"{Fore.GREEN}Found {len(objects)} access log objects in the logs bucket")
            for obj in objects[:5]:
                print(f"  - {obj['Key']} ({obj['Size']} bytes, Last Modified: {obj['LastModified']})")
            return True
        else:
            print(f"{Fore.YELLOW}No access logs found in prefix: {logs_prefix}")
            print(f"{Fore.YELLOW}This is normal - S3 access logs typically take several hours to be delivered")
            return False
    except ClientError as e:
        print(f"{Fore.RED}Error checking access logs: {e}")
        return False

def monitor_resources(s3_client, s3_resource, sqs_client, source_bucket, logs_bucket, queue_url, timeout_minutes):
    """Monitor resources for the specified timeout period."""
    start_time = time.time()
    end_time = start_time + (timeout_minutes * 60)
    
    sqs_found = False
    logs_found = False
    
    print(f"{Fore.YELLOW}Starting monitoring for {timeout_minutes} minutes...")
    
    while time.time() < end_time:
        elapsed_minutes = (time.time() - start_time) / 60
        remaining_minutes = timeout_minutes - elapsed_minutes
        
        print(f"\n{Fore.CYAN}===== Monitoring Progress ({elapsed_minutes:.1f} minutes elapsed, {remaining_minutes:.1f} remaining) =====")
        
        # Check SQS messages
        if not sqs_found:
            sqs_found = check_sqs_messages(sqs_client, queue_url)
        else:
            print(f"{Fore.GREEN}✓ SQS notifications confirmed")
        
        # Check for access logs
        if not logs_found:
            logs_found = check_access_logs(s3_client, logs_bucket, source_bucket)
        else:
            print(f"{Fore.GREEN}✓ Access logs confirmed")
        
        # If both found, we can exit
        if sqs_found and logs_found:
            print(f"{Fore.GREEN}Success! Both SQS notifications and access logs confirmed.")
            return True
        
        # Else wait and try again
        if time.time() < end_time:
            wait_time = min(60, (end_time - time.time()) / 2)
            print(f"{Fore.YELLOW}Waiting {int(wait_time)} seconds before next check...")
            time.sleep(wait_time)
    
    # Timeout reached
    print(f"\n{Fore.YELLOW}Monitoring timeout reached ({timeout_minutes} minutes)")
    print(f"{Fore.YELLOW}Summary:")
    print(f"  - SQS Notifications: {'✓ Found' if sqs_found else 'x Not found'}")
    print(f"  - Access Logs: {'✓ Found' if logs_found else 'x Not found (normal for short test periods)'}")
    
    return sqs_found

def cleanup_local_files(files):
    """Clean up local test files."""
    for file in files:
        try:
            os.remove(file)
            print(f"{Fore.GREEN}Removed local file: {file}")
        except Exception as e:
            print(f"{Fore.YELLOW}Error removing file {file}: {e}")

def main():
    parser = argparse.ArgumentParser(description='Test S3 access logs collection')
    parser.add_argument('--timeout', type=int, default=1, help='Monitoring timeout in minutes (default: 1)')
    parser.add_argument('--region', type=str, help='AWS region override (default: from Terraform or ap-northeast-1)')
    args = parser.parse_args()
    
    # Get information from Terraform outputs
    print(f"{Fore.CYAN}Retrieving information from Terraform...")
    aws_region = args.region or run_terraform_output("aws_region", "ap-northeast-1")
    source_bucket = run_terraform_output("source_bucket_name")
    logs_bucket = run_terraform_output("s3_access_logs_bucket")
    queue_url = run_terraform_output("sqs_queue_url")
    
    # Validate source bucket
    if source_bucket is None or source_bucket == "No source bucket created":
        print(f"{Fore.RED}Error: No source bucket was created.")
        print(f"{Fore.YELLOW}Please set source_bucket_name in your terraform.tfvars file and run terraform apply again.")
        sys.exit(1)
    
    # Create AWS clients
    s3_client, s3_resource, sqs_client = create_aws_clients(aws_region)
    
    # Display resource information
    print(f"{Fore.CYAN}Test Configuration:")
    print(f"  - Source Bucket: {source_bucket}")
    print(f"  - Logs Bucket: {logs_bucket}")
    print(f"  - SQS Queue URL: {queue_url}")
    print(f"  - AWS Region: {aws_region}")
    print(f"  - Monitoring Timeout: {args.timeout} minutes")
    
    # Create and upload test files
    local_files = []
    keys = []
    
    # Generate multiple files of different sizes
    file_sizes = [10, 100, 500]  # KB
    for size in file_sizes:
        filename = generate_test_file(size)
        local_files.append(filename)
        key = f"test-files/{filename}"
        keys.append(key)
        upload_file(s3_client, filename, source_bucket, key)
    
    # Perform operations to generate access logs
    for key in keys:
        generate_s3_operations(s3_client, source_bucket, key)
    
    # Monitor resources
    print(f"\n{Fore.CYAN}Starting monitoring for SQS messages and access logs...")
    monitor_resources(s3_client, s3_resource, sqs_client, source_bucket, logs_bucket, queue_url, args.timeout)
    
    # Clean up local files
    cleanup_local_files(local_files)
    
    # Provide guidance
    print(f"\n{Fore.CYAN}==================================================================")
    print(f"{Fore.CYAN}Test completed. Next steps:")
    print(f"{Fore.YELLOW}1. Remember that S3 access logs typically take several hours to appear")
    print(f"{Fore.YELLOW}2. To check for logs later, run these commands:")
    print(f"   aws s3 ls s3://{logs_bucket}/s3-access-logs/{source_bucket}/")
    print(f"\n{Fore.YELLOW}3. To check SQS messages:")
    print(f"   aws sqs receive-message --queue-url {queue_url} --max-number-of-messages 10 --wait-time-seconds 5")
    print(f"\n{Fore.YELLOW}4. When logs appear, configure Elastic Agent using:")
    print(f"   terraform output elastic_agent_config_example")
    print(f"{Fore.CYAN}==================================================================")

if __name__ == '__main__':
    main()