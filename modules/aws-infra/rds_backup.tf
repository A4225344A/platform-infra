# W3 task 10: durable backups for the RDS-backed state store.
#
# This file provides two independent backup paths:
# 1. S3 bucket + node IAM permissions for pg_dump archives produced by close.sh
#    or by manual task 10 commands.
# 2. EventBridge + Lambda safety net that creates daily manual RDS snapshots.
#
# Keep these resources outside the nightly destroy target list. The current
# terraform-destroy workflow targets only the control/worker instances and EIP.

locals {
  region_short = lookup({
    ap-northeast-1 = "apne1"
  }, var.aws_region, replace(var.aws_region, "-", ""))

  backup_bucket_name = var.backup_bucket_name != "" ? var.backup_bucket_name : "${var.project_name}-w3-backup-${data.aws_caller_identity.current.account_id}-${local.region_short}"
}

resource "aws_s3_bucket" "db_backups" {
  bucket = local.backup_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  rule {
    id     = "expire-old-pgdumps"
    status = "Enabled"

    filter {
      prefix = "w3/"
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 14
    }
  }
}

resource "aws_iam_role_policy" "node_backup_s3" {
  name = "${var.project_name}-node-backup-s3"
  role = aws_iam_role.node.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBackupBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.db_backups.arn
      },
      {
        Sid    = "ReadWriteBackupObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = "${aws_s3_bucket.db_backups.arn}/w3/*"
      }
    ]
  })
}

resource "aws_iam_role" "rds_snapshot_backup_lambda" {
  name = "${var.project_name}-rds-snapshot-backup-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_snapshot_backup_lambda_logs" {
  role       = aws_iam_role.rds_snapshot_backup_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "rds_snapshot_backup_lambda" {
  name = "${var.project_name}-rds-snapshot-backup"
  role = aws_iam_role.rds_snapshot_backup_lambda.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageManualSnapshots"
        Effect = "Allow"
        Action = [
          "rds:CreateDBSnapshot",
          "rds:DescribeDBInstances",
          "rds:DescribeDBSnapshots",
          "rds:DeleteDBSnapshot",
          "rds:AddTagsToResource",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "rds_snapshot_backup_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/rds_snapshot_backup/index.py"
  output_path = "${path.root}/.terraform/rds_snapshot_backup.zip"
}

resource "aws_lambda_function" "rds_snapshot_backup" {
  function_name    = "${var.project_name}-rds-snapshot-backup"
  role             = aws_iam_role.rds_snapshot_backup_lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.rds_snapshot_backup_lambda.output_path
  source_code_hash = data.archive_file.rds_snapshot_backup_lambda.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      DB_INSTANCE_ID = aws_db_instance.postgres.identifier
      RETENTION_DAYS = tostring(var.rds_snapshot_retention_days)
    }
  }
}

resource "aws_cloudwatch_event_rule" "rds_snapshot_backup" {
  name                = "${var.project_name}-rds-snapshot-backup"
  description         = "Create daily W3 RDS manual snapshots before the usual lab shutdown window."
  schedule_expression = var.rds_snapshot_schedule_expression
}

resource "aws_cloudwatch_event_target" "rds_snapshot_backup" {
  rule      = aws_cloudwatch_event_rule.rds_snapshot_backup.name
  target_id = "rds-snapshot-backup"
  arn       = aws_lambda_function.rds_snapshot_backup.arn
}

resource "aws_lambda_permission" "allow_eventbridge_rds_snapshot_backup" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rds_snapshot_backup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_snapshot_backup.arn
}
