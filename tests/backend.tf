terraform {
  cloud {
    organization = "Chase-UK-Org"
    
    workspaces {
      name = "s3-simple-module-tests"
    }
  }
}

# Alternative: For local testing
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }