variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "AWS profile to use for deployment"
  type        = string
  default     = "elastic-sa"
}

variable "resource_prefix" {
  description = "Prefix for all resources created by this module"
  type        = string
  default     = "elastic-s3logs"
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "ec2_ami" {
  description = "EC2 AMI ID"
  type        = string
  default     = "ami-0599b6e53ca798bb2"
}

variable "default_tags" {
  description = "AWS default tags for resources"
  type        = map(string)
  default     = {}
}

variable "access_logs_retention_days" {
  description = "Number of days to retain access logs"
  type        = number
  default     = 90
}

variable "source_bucket_name" {
  description = "Optional: Name of a source bucket to create and enable access logging for. Leave empty to skip source bucket creation."
  type        = string
  default     = ""
}