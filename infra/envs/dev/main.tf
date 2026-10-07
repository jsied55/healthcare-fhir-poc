terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.23"
    }
  }

  backend "s3" {
    bucket       = "jsied55-fhir-poc-tfstate"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "healthcare-fhir-poc"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

variable "environment" {
  description = "Name of this environment"
  type        = string
  default     = "dev"
}

locals {
  name_prefix = "fhir-poc-${var.environment}"
}

resource "aws_ssm_parameter" "env" {
  name  = "/${local.name_prefix}/environment"
  type  = "String"
  value = var.environment
}

output "name_prefix" {
  value = local.name_prefix
}

moved {
  from = aws_ssm_parameter.environment
  to   = aws_ssm_parameter.env
}

module "vpc" {
  source = "../../modules/vpc"

  name = local.name_prefix
  azs  = ["us-east-1a", "us-east-1b"]
}

module "iam" {
  source = "../../modules/iam"

  name = local.name_prefix
}