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