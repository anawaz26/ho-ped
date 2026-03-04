provider "aws" "this" {
  config {
    region = var.region
    assume_role_with_web_identity {
      role_arn           = var.role_arn
      web_identity_token = identity_token.aws.jwt
    }
  }
}

identity_token "aws" {
  audience = ["aws.workload.identity"]
}

required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
}