provider "aws" {
  region = var.aws_region
}

# ==============================================================================
# 1. ECR (Container Registry) - Onde guardaremos a imagem da IA
# ==============================================================================
resource "aws_ecr_repository" "ai_repo" {
  name                 = "${var.project_name}-ai-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true  # Permite destruir o repo mesmo com imagens dentro (útil para testes)
}

# ==============================================================================
# 2. S3 Bucket (Armazenamento de Imagens)
# ==============================================================================
resource "random_id" "bucket_id" { byte_length = 4 }

resource "aws_s3_bucket" "images_bucket" {
  bucket        = "${var.project_name}-images-${random_id.bucket_id.hex}"
  force_destroy = true # Permite destruir o bucket mesmo com arquivos dentro
}

# Configuração de CORS: Permite que o navegador/Postman envie PUT direto para o bucket
resource "aws_s3_bucket_cors_configuration" "cors" {
  bucket = aws_s3_bucket.images_bucket.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

# ==============================================================================
# 3. DynamoDB (Banco de Dados de Pacientes)
# ==============================================================================
resource "aws_dynamodb_table" "patients_table" {
  name           = "${var.project_name}-patients"
  billing_mode   = "PAY_PER_REQUEST" # Serverless: paga apenas por leitura/escrita
  hash_key       = "pacienteId"

  attribute {
    name = "pacienteId"
    type = "S"
  }
}

# ==============================================================================
# 4. IAM (Permissões e Segurança)
# ==============================================================================
# Role que permite as Lambdas executarem
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Política de acesso: Logs, S3 e DynamoDB
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-policy"
  role = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { # Logs do CloudWatch
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      { # Acesso total ao Bucket do Projeto
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        Effect = "Allow",
        Resource = [
          aws_s3_bucket.images_bucket.arn,
          "${aws_s3_bucket.images_bucket.arn}/*"
        ]
      },
      { # Acesso à Tabela de Pacientes
        Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"],
        Effect = "Allow",
        Resource = aws_dynamodb_table.patients_table.arn
      }
    ]
  })
}

# ==============================================================================
# 5. Lambda Java (Backend API)
# ==============================================================================
resource "aws_lambda_function" "java_backend" {
  function_name = "${var.project_name}-java-backend"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "com.oncovision.LambdaHandler::handleRequest"
  runtime       = "java21"
  timeout       = 15
  memory_size   = 512

  # Aponta para o ZIP que o Gradle gerou
  filename         = "../backend-java/build/distributions/backend-java.zip"
  source_code_hash = filebase64sha256("../backend-java/build/distributions/backend-java.zip")

  # Variáveis de ambiente injetadas no código Java
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.images_bucket.id
      TABLE_NAME  = aws_dynamodb_table.patients_table.name
    }
  }
}

# ==============================================================================
# 6. Lambda Python (AI Container)
# ==============================================================================
# NOTA: O Terraform falhará se a imagem não existir no ECR.
# Você deve fazer o push da imagem Docker antes de aplicar esta parte completamente.
resource "aws_lambda_function" "ai_container" {
  function_name = "${var.project_name}-ai-container"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.ai_repo.repository_url}:latest"
  timeout       = 60
  memory_size   = 1024

  architectures = ["x86_64"]

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.patients_table.name
    }
  }
}

# Permissão para o S3 chamar a Lambda de IA
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ai_container.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.images_bucket.arn
}

# Gatilho: Quando um arquivo é criado no S3 -> Chama a Lambda IA
resource "aws_s3_bucket_notification" "bucket_trigger" {
  bucket = aws_s3_bucket.images_bucket.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.ai_container.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpg"
  }
  depends_on = [aws_lambda_permission.allow_s3]
}

# ==============================================================================
# 7. API Gateway (HTTP API) - A Porta de Entrada
# ==============================================================================
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET", "OPTIONS", "PUT"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# Integração da API com a Lambda Java
resource "aws_apigatewayv2_integration" "java_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.java_backend.invoke_arn
  payload_format_version = "1.0"
}

# Rota: POST /pacientes
resource "aws_apigatewayv2_route" "create_patient" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /pacientes"
  target    = "integrations/${aws_apigatewayv2_integration.java_integration.id}"
}

# --- NOVO BLOCO: Rota GET ---
resource "aws_apigatewayv2_route" "get_patient" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /pacientes/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.java_integration.id}"
}

# Permissão para a API Gateway invocar a Lambda Java
resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.java_backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}