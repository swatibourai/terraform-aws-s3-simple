test_bucket_name = "simple-s3-test"
# bucket_name will be computed automatically from test_bucket_name + random suffix
# bucket_name = "custom-bucket-name-if-needed"  # Uncomment to override

environment      = "test"
versioning_enabled = true
test_run_id      = "simple-test-run-001"
aws_region       = "us-east-1"

additional_tags = {
  TestFramework = "Terraform"
  TestType     = "Simple"
  AutoCleanup  = "true"
  Owner        = "DevOps Team"
  Project      = "S3-Simple-Module"
  CostCenter   = "Engineering"
}