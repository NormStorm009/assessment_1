# S3 Bucket for ALB logs

resource "aws_s3_bucket" "lb_logs" {
  bucket        = "${local.name}-alb-logs-${local.account_id}"
  force_destroy = true   # dev only set false in prod

  tags = {
    Name        = "${local.name}-alb-logs"
  }
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
