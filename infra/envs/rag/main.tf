terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
  }

  backend "s3" {
    bucket       = "jsied55-fhir-poc-tfstate"
    key          = "rag/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      Project     = "healthcare-fhir-poc"
      Environment = "rag"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix     = "fhir-poc-rag"
  account_id      = data.aws_caller_identity.current.account_id
  region          = data.aws_region.current.region
  embedding_model = "amazon.titan-embed-text-v2:0"
  embedding_dim   = 1024
}

# ---- Source documents (synthetic only) ----

resource "aws_s3_bucket" "docs" {
  bucket        = "${local.name_prefix}-docs-${local.account_id}-${local.region}"
  force_destroy = true # learning only
}

resource "aws_s3_bucket_public_access_block" "docs" {
  bucket                  = aws_s3_bucket.docs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- Vector store: S3 Vectors (never the console's "Quick create") ----

resource "aws_s3vectors_vector_bucket" "main" {
  vector_bucket_name = "${local.name_prefix}-vectors"
  force_destroy      = true # learning only
}

resource "aws_s3vectors_index" "main" {
  index_name         = "${local.name_prefix}-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.main.vector_bucket_name

  data_type       = "float32"
  dimension       = local.embedding_dim
  distance_metric = "euclidean"
}

# ---- Role the Knowledge Base uses to read docs, call the embedding model, write vectors ----

resource "aws_iam_role" "kb" {
  name = "${local.name_prefix}-kb"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock:${local.region}:${local.account_id}:knowledge-base/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "kb" {
  name = "kb-access"
  role = aws_iam_role.kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EmbeddingModel"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = ["arn:aws:bedrock:${local.region}::foundation-model/${local.embedding_model}"]
      },
      {
        Sid       = "ListDocs"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = [aws_s3_bucket.docs.arn]
        Condition = { StringEquals = { "aws:ResourceAccount" = local.account_id } }
      },
      {
        Sid       = "ReadDocs"
        Effect    = "Allow"
        Action    = ["s3:GetObject"]
        Resource  = ["${aws_s3_bucket.docs.arn}/rag-source/*"]
        Condition = { StringEquals = { "aws:ResourceAccount" = local.account_id } }
      },
      {
        Sid    = "VectorIndex"
        Effect = "Allow"
        Action = [
          "s3vectors:PutVectors",
          "s3vectors:GetVectors",
          "s3vectors:DeleteVectors",
          "s3vectors:QueryVectors",
          "s3vectors:GetIndex",
        ]
        Resource = aws_s3vectors_index.main.index_arn
      },
    ]
  })
}

# ---- The Knowledge Base and its data source ----

resource "aws_bedrockagent_knowledge_base" "main" {
  name     = "${local.name_prefix}-kb"
  role_arn = aws_iam_role.kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${local.region}::foundation-model/${local.embedding_model}"
      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = local.embedding_dim
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.main.index_arn
    }
  }

  depends_on = [aws_iam_role_policy.kb]
}

resource "aws_bedrockagent_data_source" "docs" {
  name              = "${local.name_prefix}-docs"
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = aws_s3_bucket.docs.arn
      inclusion_prefixes = ["rag-source/"]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
  }
}

output "knowledge_base_id" {
  value = aws_bedrockagent_knowledge_base.main.id
}

output "data_source_id" {
  value = aws_bedrockagent_data_source.docs.data_source_id
}

output "docs_bucket" {
  value = aws_s3_bucket.docs.bucket
}