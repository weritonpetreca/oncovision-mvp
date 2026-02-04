output "api_endpoint" {
  description = "URL base da API Gateway (Para usar no Postman)"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "ecr_repository_url" {
  description = "URL do Repositório Docker (Para fazer o push da imagem)"
  value       = aws_ecr_repository.ai_repo.repository_url
}

output "s3_bucket_name" {
  description = "Nome do Bucket S3 criado"
  value       = aws_s3_bucket.images_bucket.id
}