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
    key          = "bootstrap-prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::058015011573:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project   = "healthcare-fhir-poc"
      ManagedBy = "terraform"
    }
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_prod_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:jsied55@338652645/healthcare-fhir-poc@1407971041:environment:prod"]
    }
  }
}

resource "aws_iam_role" "github_prod_deploy" {
  name               = "github-actions-prod-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_prod_trust.json
}

resource "aws_iam_role_policy_attachment" "deploy_poweruser" {
  role       = aws_iam_role.github_prod_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "deploy_iam" {
  statement {
    sid     = "ManageRolesAndPolicies"
    actions = ["iam:*Role*", "iam:*Policy*"]
    resources = [
      "arn:aws:iam::058015011573:role/*",
      "arn:aws:iam::058015011573:policy/*",
    ]
  }

  statement {
    sid     = "ProtectCiIdentity"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::058015011573:role/github-actions-*",
      "arn:aws:iam::058015011573:policy/github-actions-*",
      "arn:aws:iam::058015011573:oidc-provider/token.actions.githubusercontent.com",
    ]
  }
}

resource "aws_iam_policy" "deploy_iam" {
  name   = "github-actions-prod-deploy-iam"
  policy = data.aws_iam_policy_document.deploy_iam.json
}

resource "aws_iam_role_policy_attachment" "deploy_iam" {
  role       = aws_iam_role.github_prod_deploy.name
  policy_arn = aws_iam_policy.deploy_iam.arn
}

output "github_prod_deploy_role_arn" {
  value = aws_iam_role.github_prod_deploy.arn
}