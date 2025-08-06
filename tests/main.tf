terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Compute bucket_name before calling the module
locals {
  computed_bucket_name = var.bucket_name != null ? var.bucket_name : "${var.test_bucket_name}-${random_string.bucket_suffix.result}"
}

# Test the Simple S3 Module
module "simple_s3_test" {
  source = "../"

  bucket_name         = "testswat23567"
#   environment         = var.environment
#   versioning_enabled  = var.versioning_enabled
  #tags = merge(
  #  var.additional_tags,
  #  {
  #    TestRun = var.test_run_id
  #    Purpose = "Integration Testing"
  #    Owner   = "DevOps Team"
  #  }
  #)
}

# Test file upload to verify bucket functionality
resource "aws_s3_object" "test_file" {
  bucket  = module.simple_s3_test.bucket_id
  key     = "test-files/integration-test.txt"
  content = "Test file for Simple S3 Module validation - ${var.test_run_id}"

  tags = {
    Purpose = "Integration Test"
    TestRun = var.test_run_id
  }
}