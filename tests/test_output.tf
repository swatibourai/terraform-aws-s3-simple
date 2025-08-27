output "s3_bucket_id" {
  value = aws_s3_bucket.s3_bucket[0].id
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.s3_bucket[0].arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.s3_bucket[0].bucket
}
