locals {
  logging_bucket_name = format("%s-logging-%s", var.resource_name_prefix, local.short_region_name)
}

data "aws_iam_policy_document" "logging_bucket_policy" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = [format("arn:aws:s3:::%s/s3/*", local.logging_bucket_name)]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid    = "LoadBalancerAccessLogsPolicy"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [format("arn:aws:iam::%s:root", local.elb_logging_account)]
    }
    actions   = ["s3:PutObject"]
    resources = [format("arn:aws:s3:::%s/lb/*", local.logging_bucket_name)]
  }
}

resource "aws_s3_bucket" "logging" {
  bucket = local.logging_bucket_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logging" {
  bucket = aws_s3_bucket.logging.id
  rule {
    apply_server_side_encryption_by_default {
      # use aws/s3 key managed by AWS
      sse_algorithm = "aws:kms"
    }
  }
}
resource "aws_s3_bucket_policy" "logging" {
  bucket = aws_s3_bucket.logging.id
  policy = data.aws_iam_policy_document.logging_bucket_policy.json
}

resource "aws_s3_bucket_public_access_block" "logging" {
  bucket = aws_s3_bucket.logging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logging" {
  bucket = aws_s3_bucket.logging.id
  rule {
    status = "Enabled"
    id     = "purge-all-after-90-days"
    expiration { days = 90 }
  }
}
