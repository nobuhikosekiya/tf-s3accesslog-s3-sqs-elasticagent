# S3 Logs Collection with SQS Notification

This Terraform project sets up infrastructure for collecting S3 access logs using the SQS notification method. It creates all the necessary components for an EC2 instance to run Elastic Agent and collect S3 logs efficiently.

## Architecture

```
┌────────────────┐     Log      ┌────────────────┐   Notification  ┌────────────────┐
│   Source S3    │ ────────────>│  Access Logs   │ ───────────────>│    SQS Queue   │
│    Bucket      │     Data     │     Bucket     │    (S3 Event)   │                │
└────────────────┘              └────────────────┘                 └────────┬───────┘
                                                                            │
                                                                            │ Pull
                                                                            │ Notifications
                                                                            ▼
┌────────────────────────────────────────────────────────────────┐  ┌──────┴───────┐
│                                                                │  │               │
│              IAM Role with Required Permissions                │◄─┤  EC2 Instance │
│                                                                │  │ (Elastic Agent)│
└────────────────────────────────────────────────────────────────┘  └───────────────┘
```

## Resources Created

This Terraform configuration creates:

- **EC2 Instance**: Amazon Linux 2 instance to run Elastic Agent
- **IAM Role & Instance Profile**: With policies for SQS and S3 access
- **Security Group**: Allowing SSH access and outbound traffic
- **Access Logs S3 Bucket**: Configured for storing S3 access logs with appropriate encryption and lifecycle policies
- **SQS Queue**: For receiving S3 object creation notifications
- **Source S3 Bucket** (optional): A bucket that will be configured to send access logs to the logs bucket
- **S3 Event Notification**: Configuration to send notifications to SQS when new logs are created
- **Elastic IP**: For stable access to the EC2 instance

## Prerequisites

- AWS CLI installed and configured
- Terraform ~> 1.0
- SSH key at `~/.ssh/id_rsa.pub`

## Quick Start

1. Clone this repository
2. Copy `terraform.tfvars.example` to `terraform.tfvars`
3. Modify `terraform.tfvars` with your settings
4. Run Terraform:

```bash
terraform init
terraform plan
terraform apply
```

## Configuration

Edit `terraform.tfvars` to configure:

| Variable | Description | Default |
|----------|-------------|---------|
| aws_region | AWS region to deploy resources | ap-northeast-1 |
| aws_profile | AWS profile to use for credentials | default |
| resource_prefix | Prefix for all resource names | elastic-s3logs |
| ec2_instance_type | EC2 instance type | t3.medium |
| ec2_ami | EC2 AMI ID | ami-0599b6e53ca798bb2 |
| access_logs_retention_days | Days to retain logs before deletion | 90 |
| source_bucket_name | Optional source bucket name | "" |
| default_tags | AWS resource tagging | {} |

## Testing

The included `test_s3_logging.py` script helps verify your setup:

```bash
pip install -r requirements.txt
python test_s3_logging.py
```

The script:
1. Creates and uploads test files to the source bucket
2. Monitors the SQS queue for notifications
3. Checks the logs bucket for access logs
4. Provides detailed reporting on the setup

## Elastic Agent Configuration

After deployment, connect to the EC2 instance to configure Elastic Agent:

```bash
ssh ec2-user@$(terraform output -raw instance_public_ip)
```

Use the aws-s3 input configuration from the Terraform output:

```bash
terraform output elastic_agent_config_example
```

Example configuration:
```yaml
- type: aws-s3
  queue_url: https://sqs.ap-northeast-1.amazonaws.com/123456789012/elastic-s3logs-s3-events-abc123
  expand_event_list_from_field: Records
  api_timeout: 120s
  visibility_timeout: 300s
  include_s3_metadata:
    - last-modified
```

## Important Notes

- S3 access logs are typically delivered with a delay of several hours
- SQS message visibility timeout is set to 300 seconds by default
- All S3 buckets are configured with `force_destroy = true` to allow clean-up during `terraform destroy`
- The EC2 instance is created in the default VPC and subnet

## Troubleshooting

- **No source bucket listed:** Make sure to set `source_bucket_name` in your `terraform.tfvars` file
- **Missing logs:** S3 access logs typically appear after several hours
- **SQS permission errors:** Verify the correct SQS policy is attached to allow S3 notifications
- **EC2 connectivity issues:** Check security group rules and network ACLs

## Cleanup

To remove all created resources:

```bash
terraform destroy
```

This will delete all resources, including the S3 buckets and their contents.