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
  source = "git::https://github.com/jsied55/terraform-modules.git//vpc?ref=v1.1.0"

  name               = local.name_prefix
  azs                = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = true
}

module "iam" {
  source = "git::https://github.com/jsied55/terraform-modules.git//iam?ref=v1.2.0"

  name = local.name_prefix

  additional_secret_arns = [module.db.master_secret_arn]
}

module "db" {
  source = "git::https://github.com/jsied55/terraform-modules.git//db?ref=v1.2.0"

  name                  = local.name_prefix
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  app_security_group_id = module.vpc.app_security_group_id
}

resource "aws_ecr_repository" "api" {
  name                 = "${local.name_prefix}-api"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

resource "aws_lb" "api" {
  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnet_ids
  security_groups    = [module.vpc.alb_security_group_id]
}

resource "aws_lb_target_group" "api" {
  name        = "${local.name_prefix}-tg"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id

  health_check {
    path    = "/health"
    matcher = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

output "alb_dns_name" {
  value = aws_lb.api.dns_name
}

variable "image_tag" {
  description = "Tag of the API image in ECR"
  type        = string
  default     = "0.1.0"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${local.name_prefix}-api"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name_prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = module.iam.task_execution_role_arn
  task_role_arn            = module.iam.task_role_arn

  container_definitions = jsonencode([{
    name      = "api"
    image     = "${aws_ecr_repository.api.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{ containerPort = 8000, protocol = "tcp" }]

    environment = [
      { name = "APP_VERSION", value = var.image_tag },
      { name = "DB_HOST", value = module.db.address },
      { name = "DB_PORT", value = tostring(module.db.port) },
      { name = "DB_NAME", value = module.db.db_name },
      { name = "FHIR_BUCKET", value = aws_s3_bucket.fhir.bucket },
    ]

    secrets = [
      { name = "API_KEY", valueFrom = module.iam.api_key_secret_arn },
      { name = "DB_USER", valueFrom = "${module.db.master_secret_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${module.db.master_secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.api.name
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "api"
      }
    }
  }])
}

resource "aws_ecs_service" "api" {
  name            = "${local.name_prefix}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnet_ids
    security_groups  = [module.vpc.app_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]
}

output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}

resource "aws_ecr_repository_policy" "allow_prod_pull" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowProdAccountPull"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::058015011573:root"
      }
      Action = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
    }]
  })
}

# ---- Module 10: FHIR landing bucket ----

data "aws_caller_identity" "fhir" {}

resource "aws_s3_bucket" "fhir" {
  bucket        = "${local.name_prefix}-fhir-${data.aws_caller_identity.fhir.account_id}"
  force_destroy = true # learning only: a real client bucket would not allow this
}

resource "aws_s3_bucket_public_access_block" "fhir" {
  bucket                  = aws_s3_bucket.fhir.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "fhir" {
  bucket = aws_s3_bucket.fhir.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "fhir" {
  bucket = aws_s3_bucket.fhir.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Free S3 gateway endpoint: keeps S3 traffic inside AWS, off the NAT gateway.
data "aws_route_tables" "vpc" {
  vpc_id     = module.vpc.vpc_id
  depends_on = [module.vpc]
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.vpc.ids
}

# The task role may write new objects under incoming/ and nothing else.
resource "aws_iam_role_policy" "task_fhir_put" {
  name = "fhir-put-incoming"
  role = regex("[^/]+$", module.iam.task_role_arn)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.fhir.arn}/incoming/*"
    }]
  })
}