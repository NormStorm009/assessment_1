# S3 Bucket for ALB logs

resource "aws_s3_bucket" "lb_logs" {
  bucket        = "${local.name}-alb-logs-${local.account_id}"
  force_destroy = true   # dev only set false in prod

  tags = {
    Name        = "${local.name}-alb-logs"
  }
}

# Block public access (bucket policy for ELB service account is not public)
resource "aws_s3_bucket_public_access_block" "lb_logs" {
  bucket = aws_s3_bucket.lb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Grant the AWS ELB service account for eu-west-1 permission to write access logs.
# Each region has a dedicated ELB account — eu-west-1 uses 156460612806.
# See: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
resource "aws_s3_bucket_policy" "lb_logs" {
  bucket = aws_s3_bucket.lb_logs.id

  # Ensure public access block is applied before the policy is attached
  depends_on = [aws_s3_bucket_public_access_block.lb_logs]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowELBAccessLogs"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::156460612806:root"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${aws_s3_bucket.lb_logs.id}/${local.name}-alb/AWSLogs/${local.account_id}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_versioning" "lb_logs" {
  bucket = aws_s3_bucket.lb_logs.id

  versioning_configuration {
    status = "Disabled" 
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lb_logs" {
  bucket = aws_s3_bucket.lb_logs.id

  # Dev: expire logs after 30 days
  dynamic "rule" {
    for_each = var.env == "dev" ? [1] : []

    content {
      id     = "dev-expire-logs"
      status = "Enabled"

      expiration {
        days = 30
      }
    }
  }

  # Prod: transition to Glacer after 1 year never expire
  dynamic "rule" {
    for_each = var.env == "prod" ? [1] : []

    content {
      id     = "prod-archive-logs"
      status = "Enabled"

      transition {
        days          = 365
        storage_class = "GLACIER"
      }
    }
  }
}
