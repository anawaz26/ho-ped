variable "region" { type = string }
variable "role_arn" { type = string }
variable "arm_ami_id" { type = string }
variable "identity_token" {
  type      = string
  ephemeral = true
}
