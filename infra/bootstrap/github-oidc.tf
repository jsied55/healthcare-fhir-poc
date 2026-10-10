resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
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
      values   = ["repo:jsied55@338652645/healthcare-fhir-poc@1407971041:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_dev" {
  name               = "github-actions-dev"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy_attachment" "github_dev_readonly" {
  role       = aws_iam_role.github_dev.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

output "github_dev_role_arn" {
  value = aws_iam_role.github_dev.arn
}
data "aws_iam_policy_document" "github_deploy_trust" {
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
      values   = ["repo:jsied55@338652645/healthcare-fhir-poc@1407971041:environment:dev"]
    }
  }
}

resource "aws_iam_role" "github_dev_deploy" {
  name               = "github-actions-dev-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_trust.json
}

resource "aws_iam_role_policy_attachment" "deploy_poweruser" {
  role       = aws_iam_role.github_dev_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "deploy_iam" {
  statement {
    sid     = "ManageRolesAndPolicies"
    actions = ["iam:*Role*", "iam:*Policy*"]
    resources = [
      "arn:aws:iam::886126521431:role/*",
      "arn:aws:iam::886126521431:policy/*",
    ]
  }

  statement {
    sid     = "ProtectCiIdentity"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::886126521431:role/github-actions-*",
      "arn:aws:iam::886126521431:policy/github-actions-*",
      "arn:aws:iam::886126521431:oidc-provider/token.actions.githubusercontent.com",
    ]
  }
}

resource "aws_iam_policy" "deploy_iam" {
  name   = "github-actions-dev-deploy-iam"
  policy = data.aws_iam_policy_document.deploy_iam.json
}

resource "aws_iam_role_policy_attachment" "deploy_iam" {
  role       = aws_iam_role.github_dev_deploy.name
  policy_arn = aws_iam_policy.deploy_iam.arn
}

output "github_dev_deploy_role_arn" {
  value = aws_iam_role.github_dev_deploy.arn
}

data "github_user" "me" {
  username = "jsied55"
}

resource "github_repository_environment" "dev" {
  repository        = "healthcare-fhir-poc"
  environment       = "dev"
  can_admins_bypass = false

  reviewers {
    users = [data.github_user.me.id]
  }
}

resource "github_repository_environment" "prod" {
  repository        = "healthcare-fhir-poc"
  environment       = "prod"
  can_admins_bypass = false

  reviewers {
    users = [data.github_user.me.id]
  }
}