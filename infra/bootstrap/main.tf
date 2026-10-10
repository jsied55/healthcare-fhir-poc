terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.23"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    bucket       = "jsied55-fhir-poc-tfstate"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "healthcare-fhir-poc"
      ManagedBy = "terraform"
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket = "jsied55-fhir-poc-tfstate"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

provider "github" {
  owner = "jsied55"
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid       = "ProdDeployListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::jsied55-fhir-poc-tfstate"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::058015011573:role/github-actions-prod-deploy"]
    }
  }

  statement {
    sid       = "ProdDeployProdStateOnly"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::jsied55-fhir-poc-tfstate/prod/*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::058015011573:role/github-actions-prod-deploy"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = "jsied55-fhir-poc-tfstate"
  policy = data.aws_iam_policy_document.state_bucket.json
}