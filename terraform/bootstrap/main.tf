# Remote state infrastructure: the S3 bucket holding the state files of every
# environment (dev/, qa/, prod/ ...). State locking is S3-native
# (use_lockfile = true in each backend: a <key>.tflock object in this bucket),
# so no DynamoDB table is needed.

resource "aws_s3_bucket" "state" {
  bucket = "michaeltg17-template-terraform-state"

  tags = {
    Project   = "template"
    ManagedBy = "terraform"
  }
}

# State history: every replace/destroy keeps the previous versions, so a
# bad apply can always be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
