output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.elastic_agent.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_eip.elastic_agent_eip.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.elastic_agent.private_ip
}

output "iam_role_name" {
  description = "IAM role name"
  value       = aws_iam_role.elastic_agent_role.name
}

output "iam_role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.elastic_agent_role.arn
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh ec2-user@${aws_eip.elastic_agent_eip.public_ip}"
}

output "s3_access_logs_bucket" {
  description = "S3 bucket storing access logs"
  value       = aws_s3_bucket.access_logs_bucket.id
}

output "s3_access_logs_bucket_arn" {
  description = "ARN of the S3 bucket storing access logs"
  value       = aws_s3_bucket.access_logs_bucket.arn
}

output "source_bucket_name" {
  description = "Name of the source bucket configured for access logging (if created)"
  value       = var.source_bucket_name != "" ? aws_s3_bucket.source_bucket[0].id : "No source bucket created"
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for S3 event notifications"
  value       = aws_sqs_queue.s3_events_queue.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for S3 event notifications"
  value       = aws_sqs_queue.s3_events_queue.arn
}

output "elastic_agent_config_example" {
  description = "Example configuration for Elastic Agent aws-s3 input"
  value       = <<-EOT
    - type: aws-s3
      queue_url: ${aws_sqs_queue.s3_events_queue.url}
      expand_event_list_from_field: Records
      api_timeout: 120s
      visibility_timeout: 300s
      include_s3_metadata:
        - last-modified
  EOT
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}