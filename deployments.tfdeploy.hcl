identity_token "aws" {
  audience = ["aws.workload.identity"]
}

deployment "sandbox" {
  inputs = {
    region         = "eu-west-2"
    role_arn       = "arn:aws:iam::735910966814:role/ayazi-terrastack"
    arm_ami_id     = "ami-0c101f26f147fa7fd"
    identity_token = identity_token.aws.jwt
  }
}
