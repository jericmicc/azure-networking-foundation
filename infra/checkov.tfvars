# Used only by the Checkov scan in CI (checkov --var-file). It turns the optional billed code on so that it is scanned.
# Terraform never loads this file by itself (the name is not terraform.tfvars or *.auto.tfvars), so a plan or apply ignores it.
deploy_test_vms         = true
deploy_nat_gateway      = true
deploy_private_endpoint = true
deploy_monitoring       = true
