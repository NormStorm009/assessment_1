locals {
  name        = "${var.env}-${var.service}"
  account_id  = data.aws_caller_identity.current.account_id
  tags = {
    Service     = var.service
    Environment = var.env
    Cost_centre   = var.cost_centre
    Owner       = var.owner
  }
}