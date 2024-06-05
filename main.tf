provider "aws" {
  region = var.aws_region
}

# Generate a random string for unique resource naming
resource "random_id" "id" {
  byte_length = 4
}

# Create IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-apigateway-role-${random_id.id.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}



# Attach policy to the IAM Role
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create IAM Role for Auth Lambda
resource "aws_iam_role" "auth_lambda_role" {
  name = "auth-lambda-role-${random_id.id.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach policy to the Auth Lambda Role
resource "aws_iam_role_policy_attachment" "auth_lambda_policy" {
  role       = aws_iam_role.auth_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create Lambda function
resource "aws_lambda_function" "LambdaFunctionOverHttps" {
  filename      = "LambdaFunctionOverHttps.zip"
  function_name = "LambdaFunctionOverHttps-${random_id.id.hex}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "LambdaFunctionOverHttps.lambda_handler"
  runtime       = "python3.12"

  source_code_hash = filebase64sha256("LambdaFunctionOverHttps.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.dynamo_db_table.name
    }
  }

}

# Attach required policies to the IAM role
resource "aws_iam_role_policy_attachment" "lambda_permissions" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "additional_permissions" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" # Example policy, adjust as needed
}


# Create Auth Lambda function
resource "aws_lambda_function" "auth_lambda" {
  filename      = "authorizer.zip"
  function_name = "auth_lambda-${random_id.id.hex}"
  role          = aws_iam_role.auth_lambda_role.arn
  handler       = "authorizer.lambda_handler"
  runtime       = "python3.12"

  source_code_hash = filebase64sha256("authorizer.zip")
}

# Create API Gateway REST API
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "DynamoDBOperations-${random_id.id.hex}"
  description = "API Gateway for Lambda to perform CRUD operations on DynamoDB"
}

# Create API Gateway Resource
resource "aws_api_gateway_resource" "api_resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "DynamoDBManager"
}

# Create API Gateway Method
resource "aws_api_gateway_method" "api_method" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.api_resource.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda_authorizer.id
}

# Create Lambda Integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.api_resource.id
  http_method = aws_api_gateway_method.api_method.http_method
 
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.LambdaFunctionOverHttps.invoke_arn
}

#Manages an API Gateway Request Validator.
resource "aws_api_gateway_request_validator" "validator" {
  name                        = "validator"
  rest_api_id                 = aws_api_gateway_rest_api.api_gateway.id
  validate_request_body       = false  
  validate_request_parameters = true
}

# Create API Gateway Authorizer
resource "aws_api_gateway_authorizer" "lambda_authorizer" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  name        = "ddb-lambda-auth-${random_id.id.hex}"
  type        = "REQUEST"
  authorizer_uri = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.aws_region}:${var.account_id}:function:auth_lambda-${random_id.id.hex}/invocations"

  identity_source = "method.request.header.HeaderAuth1"
}

# Create DynamoDB Table
resource "aws_dynamodb_table" "dynamo_db_table" {
  name         = "lambda-timestamp-${random_id.id.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "time"

  attribute {
    name = "time"
    type = "S"
  }
}

# Grant API Gateway permission to invoke the Lambda function
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.LambdaFunctionOverHttps.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

# Grant API Gateway permission to invoke the Auth Lambda function
resource "aws_lambda_permission" "auth_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvokeAuth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

# Create API Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [aws_api_gateway_integration.lambda_integration]

  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "test"
}
