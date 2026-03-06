deployment "sandbox" {
  inputs = {
    region     = "us-east-1"
    role_arn   = "arn:aws:iam::123456789012:role/hcp-terraform-stack-role"
    arm_ami_id = "ami-0c101f26f147fa7fd"
  }
}