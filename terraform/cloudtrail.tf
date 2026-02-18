# =============================================================================
# CloudTrail — AWS API Activity Logging
# =============================================================================
# Purpose: Record every AWS API call made in this account to an S3 bucket.
#
# Why CloudTrail?
#   - Provides a complete audit trail of WHO did WHAT and WHEN in AWS.
#   - Required for security investigations ("who deleted that resource?")
#   - Enables compliance with SOC2, ISO 27001, PCI-DSS requirements.
#   - Works alongside GuardDuty — GuardDuty uses CloudTrail events as a
#     data source to detect threats.
#
# Security hardening applied:
#   - Log file validation: SHA-256 digest files detect tampering
#   - S3 bucket: encrypted (SSE-S3), public access blocked, lifecycle policy
#   - Multi-region trail: captures events from ALL regions, not just eu-west-1
#   - Global service events: captures IAM, STS, Route53 (global services)
# =============================================================================

# =============================================================================
# S3 Bucket for CloudTrail Logs
# =============================================================================

resource "aws_s3_bucket" "cloudtrail" {
  # Bucket name must be globally unique — using account ID as suffix
  bucket        = "notes-app-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # Allow terraform destroy to empty the bucket

  tags = merge(
    local.common_tags,
    {
      Name    = "notes-app-cloudtrail-logs"
      Purpose = "CloudTrail audit logs"
    }
  )
}

# Encrypt all objects at rest using SSE-S3 (AES-256)
# SSE-S3 is free; SSE-KMS adds cost but stronger key management.
# For a lab, SSE-S3 meets the "encryption" requirement.
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block ALL public access — CloudTrail logs must never be publicly readable
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy — manage log retention cost:
#   Day 0–90:  Standard storage (frequent access for investigations)
#   Day 90+:   Glacier Instant Retrieval (cheap cold storage, ~$0.004/GB/month)
#   Day 365+:  Expire (delete) — adjust to your compliance requirements
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "cloudtrail-log-lifecycle"
    status = "Enabled"

    # Apply to all objects in the bucket
    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER_IR" # Glacier Instant Retrieval
    }

    expiration {
      days = 365
    }

    # Also expire incomplete multipart uploads (housekeeping)
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket policy — CloudTrail service needs permission to write to this bucket.
# This is a mandatory AWS requirement; without it, the trail creation fails.
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  # Must wait for public access block to be applied first
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudTrail must be able to check the bucket ACL
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/notes-app-trail"
          }
        }
      },
      {
        # CloudTrail must be able to write log files
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/notes-app-trail"
          }
        }
      }
    ]
  })
}

# =============================================================================
# CloudTrail Trail
# =============================================================================

resource "aws_cloudtrail" "main" {
  name           = "notes-app-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  # Capture events from ALL AWS regions (not just eu-west-1)
  # This catches attacks that try to operate in unused regions
  is_multi_region_trail = true

  # Capture IAM, STS, Route53 — these are "global" services not tied to a region
  include_global_service_events = true

  # SHA-256 digest files are written hourly — detect if log files are tampered with
  enable_log_file_validation = true

  # Enable CloudWatch Logs integration for real-time alerting on API events
  # (optional — adds CloudWatch Logs costs; comment out if not needed)
  # cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  # cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  tags = merge(
    local.common_tags,
    {
      Name    = "notes-app-trail"
      Purpose = "AWS API audit logging"
    }
  )

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_s3_bucket_public_access_block.cloudtrail,
  ]
}
