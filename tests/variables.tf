variable "test_bucket_name" {
  description = "Base name for the test S3 bucket"
  type        = string
  default     = "simple-s3-test"
}

variable "bucket_name" {
  description = "Full bucket name with suffix (computed from test_bucket_name + random suffix)"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment for testing"
  type        = string
  default     = "test"
}

variable "versioning_enabled" {
  description = "Enable versioning for the test bucket"
  type        = bool
  default     = true
}

variable "test_run_id" {
  description = "Unique identifier for this test run"
  type        = string
  default     = "manual-test"
}

variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "additional_tags" {
  description = "Additional tags for test resources"
  type        = map(string)
  default = {
    TestFramework = "Terraform"
    AutoCleanup   = "true"
  }
}