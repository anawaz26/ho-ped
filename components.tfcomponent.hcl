removed {
  source = "./modules/ped"
  from   = component.ped

  providers = {
    aws = provider.aws.this
  }
}
