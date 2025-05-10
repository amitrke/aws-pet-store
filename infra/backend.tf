terraform {
  backend "s3" {
    bucket = "975848467324-terraform-state-bucket-e1"
    key    = "aws-pet-store/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "TerraformLockTable"
    shared_credentials_file = "~/.aws/credentials"
  }
}