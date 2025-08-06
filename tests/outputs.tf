output "test_bucket_id" {
  description = "ID of the test S3 bucket"
  value       = module.simple_s3_test.bucket_id
}

output "test_bucket_arn" {
  description = "ARN of the test S3 bucket"
  value       = module.simple_s3_test.bucket_arn
}

output "test_bucket_domain_name" {
  description = "Domain name of the test S3 bucket"
  value       = module.simple_s3_test.bucket_domain_name
}

output "test_versioning_status" {
  description = "Versioning status of the test bucket"
  value       = module.simple_s3_test.versioning_status
}

output "test_file_details" {
  description = "Test file upload details"
  value = {
    key    = aws_s3_object.test_file.key
    bucket = aws_s3_object.test_file.bucket
    etag   = aws_s3_object.test_file.etag
  }
}

output "test_summary" {
  description = "Summary of test execution"
  value = {
    test_run_id         = var.test_run_id
    bucket_name         = "${var.test_bucket_name}-${random_string.bucket_suffix.result}"
    environment         = var.environment
    versioning_enabled  = var.versioning_enabled
    aws_region          = var.aws_region
    test_timestamp      = timestamp()
  }
}