# =============================================================================
# IAM Role and Policy for Elastic Agent
# =============================================================================

# IAM role for EC2 instance
resource "aws_iam_role" "elastic_agent_role" {
  name = "${var.resource_prefix}-ec2-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.resource_prefix}-ec2-role"
  }
}

# IAM policy for S3 access logs collection
resource "aws_iam_policy" "s3_logs_policy" {
  name        = "${var.resource_prefix}-s3-logs-policy"
  description = "Policy for collecting S3 access logs"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.access_logs_bucket.arn,
          "${aws_s3_bucket.access_logs_bucket.arn}/*"
        ]
      },
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.s3_events_queue.arn
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "s3_logs_attachment" {
  role       = aws_iam_role.elastic_agent_role.name
  policy_arn = aws_iam_policy.s3_logs_policy.arn
}

# Create instance profile
resource "aws_iam_instance_profile" "elastic_agent_profile" {
  name = "${var.resource_prefix}-instance-profile"
  role = aws_iam_role.elastic_agent_role.name
}

# =============================================================================
# Security Group for EC2 Instance
# =============================================================================

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get default subnet in the first availability zone
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Security group for Elastic Agent EC2 instance
resource "aws_security_group" "elastic_agent_sg" {
  name        = "${var.resource_prefix}-sg"
  description = "Security group for Elastic Agent EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.resource_prefix}-sg"
  }
}

# =============================================================================
# S3 Bucket for Access Logs
# =============================================================================

# Random string to ensure bucket name uniqueness
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 bucket to store access logs
resource "aws_s3_bucket" "access_logs_bucket" {
  force_destroy = true
  bucket = "${var.resource_prefix}-access-logs-${random_string.suffix.result}"

  tags = {
    Name = "${var.resource_prefix}-access-logs"
  }
}

# Configure bucket to block public access
resource "aws_s3_bucket_public_access_block" "access_logs_block" {
  bucket = aws_s3_bucket.access_logs_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning on the bucket
resource "aws_s3_bucket_versioning" "access_logs_versioning" {
  bucket = aws_s3_bucket.access_logs_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Set ACL to allow S3 Log Delivery group access
resource "aws_s3_bucket_ownership_controls" "access_logs_ownership" {
  bucket = aws_s3_bucket.access_logs_bucket.id
  
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "access_logs_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.access_logs_ownership]
  
  bucket = aws_s3_bucket.access_logs_bucket.id
  acl    = "log-delivery-write"
}

# Set server-side encryption by default
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs_encryption" {
  bucket = aws_s3_bucket.access_logs_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Add bucket policy to allow log delivery
resource "aws_s3_bucket_policy" "access_logs_policy" {
  bucket = aws_s3_bucket.access_logs_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = [
          "s3:PutObject"
        ]
        Resource  = "${aws_s3_bucket.access_logs_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount": data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Set lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "access_logs_lifecycle" {
  bucket = aws_s3_bucket.access_logs_bucket.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    
    # Adding filter with prefix as required by newer AWS provider versions
    filter {
      prefix = ""  # Empty prefix applies to all objects
    }

    expiration {
      days = var.access_logs_retention_days
    }
    
    # Add abort incomplete multipart upload rule
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# =============================================================================
# Source Bucket (Optional)
# =============================================================================

# Create source bucket if specified
resource "aws_s3_bucket" "source_bucket" {
  force_destroy = true
  count  = var.source_bucket_name != "" ? 1 : 0
  bucket = "${var.source_bucket_name}-${random_string.suffix.result}"

  tags = {
    Name = "${var.source_bucket_name}-${random_string.suffix.result}"
  }
}

# Configure source bucket security if created
resource "aws_s3_bucket_public_access_block" "source_bucket_block" {
  count  = var.source_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.source_bucket[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning on source bucket if created
resource "aws_s3_bucket_versioning" "source_bucket_versioning" {
  count  = var.source_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.source_bucket[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Set server-side encryption on source bucket if created
resource "aws_s3_bucket_server_side_encryption_configuration" "source_bucket_encryption" {
  count  = var.source_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.source_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Configure access logging on source bucket if created
resource "aws_s3_bucket_logging" "source_bucket_logging" {
  count  = var.source_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.source_bucket[0].id
  
  target_bucket = aws_s3_bucket.access_logs_bucket.id
  target_prefix = "s3-access-logs/${aws_s3_bucket.source_bucket[0].id}/"
}

# =============================================================================
# SQS Queue for S3 Event Notifications
# =============================================================================

# SQS Queue for S3 event notifications
resource "aws_sqs_queue" "s3_events_queue" {
  name                      = "${var.resource_prefix}-s3-events-${random_string.suffix.result}"
  message_retention_seconds = 604800  # 7 days
  visibility_timeout_seconds = 300

  tags = {
    Name = "${var.resource_prefix}-s3-events"
  }
}

# SQS Queue Policy to allow S3 to send messages
resource "aws_sqs_queue_policy" "s3_events_policy" {
  queue_url = aws_sqs_queue.s3_events_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.s3_events_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.access_logs_bucket.arn
          }
        }
      }
    ]
  })
}

# =============================================================================
# S3 Event Notification to SQS
# =============================================================================

# S3 notification configuration
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.access_logs_bucket.id

  queue {
    queue_arn     = aws_sqs_queue.s3_events_queue.arn
    events        = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.s3_events_policy]
}

# =============================================================================
# EC2 Instance for Elastic Agent
# =============================================================================

# Import SSH key for EC2 instance 
resource "aws_key_pair" "deployer" {
  key_name   = "${var.resource_prefix}-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# EC2 instance for Elastic Agent
resource "aws_instance" "elastic_agent" {
  ami                    = var.ec2_ami
  instance_type          = var.ec2_instance_type
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [aws_security_group.elastic_agent_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.elastic_agent_profile.name
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.resource_prefix}-instance"
  }
}

# Elastic IP for EC2 instance
resource "aws_eip" "elastic_agent_eip" {
  instance = aws_instance.elastic_agent.id
  domain   = "vpc"
  
  tags = {
    Name = "${var.resource_prefix}-eip"
  }
}