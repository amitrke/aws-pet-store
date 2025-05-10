# main.tf

provider "aws" {
  region = "us-east-1"
}

# DynamoDB Table
resource "aws_dynamodb_table" "pet_store" {
  name           = "PetStore"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  global_secondary_index {
    name            = "UserIdIndex"
    hash_key        = "userId"
    projection_type = "ALL"
    read_capacity   = 5
    write_capacity  = 5
  }
}

# Cognito Identity Pool
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "pet_store_identity_pool"
  allow_unauthenticated_identities = false

  supported_login_providers = {
    "accounts.google.com" = var.google_client_id
  }
}

# IAM Roles
resource "aws_iam_role" "authenticated_role" {
  name = "pet_store_authenticated_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          "StringEquals" = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "authenticated_policy" {
  name = "pet_store_authenticated_policy"
  role = aws_iam_role.authenticated_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["dynamodb:Scan"],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.pet_store.arn
      },
      {
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.pet_store.arn,
        Condition = {
          "ForAllValues:StringEquals" = {
            "dynamodb:LeadingKeys" = ["${aws_cognito_identity_pool.main.id}:*"]
          }
        }
      },
      {
        Action   = ["execute-api:Invoke"],
        Effect   = "Allow",
        Resource = "${aws_api_gateway_rest_api.pet_store_api.execution_arn}/*"
      }
    ]
  })
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id
  roles = {
    "authenticated" = aws_iam_role.authenticated_role.arn
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "pet_store_api" {
  name        = "PetStoreAPI"
  description = "API for Pet Store with Google Auth"
}

# Resources
resource "aws_api_gateway_resource" "pets" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  parent_id   = aws_api_gateway_rest_api.pet_store_api.root_resource_id
  path_part   = "pets"
}

resource "aws_api_gateway_resource" "pet" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  parent_id   = aws_api_gateway_resource.pets.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "my_pets" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  parent_id   = aws_api_gateway_rest_api.pet_store_api.root_resource_id
  path_part   = "my-pets"
}

# Methods
resource "aws_api_gateway_method" "pets_post" {
  rest_api_id   = aws_api_gateway_rest_api.pet_store_api.id
  resource_id   = aws_api_gateway_resource.pets.id
  http_method   = "POST"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_method" "pets_get" {
  rest_api_id   = aws_api_gateway_rest_api.pet_store_api.id
  resource_id   = aws_api_gateway_resource.pets.id
  http_method   = "GET"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_method" "pet_get" {
  rest_api_id   = aws_api_gateway_rest_api.pet_store_api.id
  resource_id   = aws_api_gateway_resource.pet.id
  http_method   = "GET"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_method" "pet_put" {
  rest_api_id   = aws_api_gateway_rest_api.pet_store_api.id
  resource_id   = aws_api_gateway_resource.pet.id
  http_method   = "PUT"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_method" "pet_delete" {
  rest_api_id   = aws_api_gateway_rest_api.pet_store_api.id
  resource_id   = aws_api_gateway_resource.pet.id
  http_method   = "DELETE"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_method" "my_pets_get" {
  rest_api_id   = aws_api_gateway_rest_api.pet_store_api.id
  resource_id   = aws_api_gateway_resource.my_pets.id
  http_method   = "GET"
  authorization = "AWS_IAM"
}

# Integrations
locals {
  template_vars = {
    table_name = aws_dynamodb_table.pet_store.name
  }
}

resource "aws_api_gateway_integration" "pets_post" {
  rest_api_id             = aws_api_gateway_rest_api.pet_store_api.id
  resource_id             = aws_api_gateway_resource.pets.id
  http_method             = aws_api_gateway_method.pets_post.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  credentials             = aws_iam_role.authenticated_role.arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:dynamodb:action/PutItem"

  request_templates = {
    "application/json" = templatefile("${path.module}/vtl_templates/pets/POST.vm", local.template_vars)
  }
}

resource "aws_api_gateway_integration" "pets_get" {
  rest_api_id             = aws_api_gateway_rest_api.pet_store_api.id
  resource_id             = aws_api_gateway_resource.pets.id
  http_method             = aws_api_gateway_method.pets_get.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  credentials             = aws_iam_role.authenticated_role.arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:dynamodb:action/Scan"

  request_templates = {
    "application/json" = templatefile("${path.module}/vtl_templates/pets/GET.vm", local.template_vars)
  }
}

resource "aws_api_gateway_integration" "pet_get" {
  rest_api_id             = aws_api_gateway_rest_api.pet_store_api.id
  resource_id             = aws_api_gateway_resource.pet.id
  http_method             = aws_api_gateway_method.pet_get.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  credentials             = aws_iam_role.authenticated_role.arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:dynamodb:action/GetItem"

  request_templates = {
    "application/json" = templatefile("${path.module}/vtl_templates/pets_{id}/GET.vm", local.template_vars)
  }
}

resource "aws_api_gateway_integration" "pet_put" {
  rest_api_id             = aws_api_gateway_rest_api.pet_store_api.id
  resource_id             = aws_api_gateway_resource.pet.id
  http_method             = aws_api_gateway_method.pet_put.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  credentials             = aws_iam_role.authenticated_role.arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:dynamodb:action/UpdateItem"

  request_templates = {
    "application/json" = templatefile("${path.module}/vtl_templates/pets_{id}/PUT.vm", local.template_vars)
  }
}

resource "aws_api_gateway_integration" "pet_delete" {
  rest_api_id             = aws_api_gateway_rest_api.pet_store_api.id
  resource_id             = aws_api_gateway_resource.pet.id
  http_method             = aws_api_gateway_method.pet_delete.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  credentials             = aws_iam_role.authenticated_role.arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:dynamodb:action/DeleteItem"

  request_templates = {
    "application/json" = templatefile("${path.module}/vtl_templates/pets_{id}/DELETE.vm", local.template_vars)
  }
}

resource "aws_api_gateway_integration" "my_pets_get" {
  rest_api_id             = aws_api_gateway_rest_api.pet_store_api.id
  resource_id             = aws_api_gateway_resource.my_pets.id
  http_method             = aws_api_gateway_method.my_pets_get.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  credentials             = aws_iam_role.authenticated_role.arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:dynamodb:action/Query"

  request_templates = {
    "application/json" = templatefile("${path.module}/vtl_templates/my_pets/GET.vm", local.template_vars)
  }
}

# Response Templates
locals {
  error_template = templatefile("${path.module}/vtl_templates/shared/error.vm", {})
}

# Generic Method Response
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pets.id
  http_method = aws_api_gateway_method.pets_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_method_response" "response_400" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pets.id
  http_method = aws_api_gateway_method.pets_post.http_method
  status_code = "400"

  response_models = {
    "application/json" = "Error"
  }
}

# Integration Responses
resource "aws_api_gateway_integration_response" "pets_post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pets.id
  http_method = aws_api_gateway_method.pets_post.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "id": "$context.requestId"
}
EOF
  }

  depends_on = [aws_api_gateway_integration.pets_post]
}

resource "aws_api_gateway_integration_response" "pets_post_error" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pets.id
  http_method = aws_api_gateway_method.pets_post.http_method
  status_code = aws_api_gateway_method_response.response_400.status_code

  selection_pattern = "4\\d{2}"

  response_templates = {
    "application/json" = local.error_template
  }

  depends_on = [aws_api_gateway_integration.pets_post]
}

# Repeat similar response configurations for other methods:
# - pets_get
# - pet_get
# - pet_put
# - pet_delete
# - my_pets_get
resource "aws_api_gateway_method_response" "pets_get_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pets.id
  http_method = aws_api_gateway_method.pets_get.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "pets_get_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pets.id
  http_method = aws_api_gateway_method.pets_get.http_method
  status_code = aws_api_gateway_method_response.pets_get_response.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "items": $input.json('$')
}
EOF
  }

  depends_on = [aws_api_gateway_integration.pets_get]
}

resource "aws_api_gateway_integration_response" "pets_get_error" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pets.id
  http_method = aws_api_gateway_method.pets_get.http_method
  status_code = aws_api_gateway_method_response.response_400.status_code

  selection_pattern = "4\\d{2}"

  response_templates = {
    "application/json" = local.error_template
  }

  depends_on = [aws_api_gateway_integration.pets_get]
}

resource "aws_api_gateway_method_response" "pet_get_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pet.id
  http_method = aws_api_gateway_method.pet_get.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "pet_get_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pet.id
  http_method = aws_api_gateway_method.pet_get.http_method
  status_code = aws_api_gateway_method_response.pet_get_response.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "item": $input.json('$')
}
EOF
  }

  depends_on = [aws_api_gateway_integration.pet_get]
}

resource "aws_api_gateway_integration_response" "pet_get_error" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pet.id
  http_method = aws_api_gateway_method.pet_get.http_method
  status_code = aws_api_gateway_method_response.response_400.status_code

  selection_pattern = "4\\d{2}"

  response_templates = {
    "application/json" = local.error_template
  }

  depends_on = [aws_api_gateway_integration.pet_get]
}

resource "aws_api_gateway_method_response" "pet_put_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pet.id
  http_method = aws_api_gateway_method.pet_put.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "pet_put_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pet.id
  http_method = aws_api_gateway_method.pet_put.http_method
  status_code = aws_api_gateway_method_response.pet_put_response.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "id": "$context.requestId"
}
EOF
  }

  depends_on = [aws_api_gateway_integration.pet_put]
}

resource "aws_api_gateway_integration_response" "pet_put_error" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pet.id
  http_method = aws_api_gateway_method.pet_put.http_method
  status_code = aws_api_gateway_method_response.response_400.status_code

  selection_pattern = "4\\d{2}"

  response_templates = {
    "application/json" = local.error_template
  }

  depends_on = [aws_api_gateway_integration.pet_put]
}

resource "aws_api_gateway_method_response" "pet_delete_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pet.id
  http_method = aws_api_gateway_method.pet_delete.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "pet_delete_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pet.id
  http_method = aws_api_gateway_method.pet_delete.http_method
  status_code = aws_api_gateway_method_response.pet_delete_response.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "id": "$context.requestId"
}
EOF
  }

  depends_on = [aws_api_gateway_integration.pet_delete]
}

resource "aws_api_gateway_integration_response" "pet_delete_error" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.pet.id
  http_method = aws_api_gateway_method.pet_delete.http_method
  status_code = aws_api_gateway_method_response.response_400.status_code

  selection_pattern = "4\\d{2}"

  response_templates = {
    "application/json" = local.error_template
  }

  depends_on = [aws_api_gateway_integration.pet_delete]
}

resource "aws_api_gateway_method_response" "my_pets_get_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.my_pets.id
  http_method = aws_api_gateway_method.my_pets_get.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "my_pets_get_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.my_pets.id
  http_method = aws_api_gateway_method.my_pets_get.http_method
  status_code = aws_api_gateway_method_response.my_pets_get_response.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "items": $input.json('$')
}
EOF
  }

  depends_on = [aws_api_gateway_integration.my_pets_get]
}

resource "aws_api_gateway_integration_response" "my_pets_get_error" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id
  resource_id = aws_api_gateway_resource.my_pets.id
  http_method = aws_api_gateway_method.my_pets_get.http_method
  status_code = aws_api_gateway_method_response.response_400.status_code

  selection_pattern = "4\\d{2}"

  response_templates = {
    "application/json" = local.error_template
  }

  depends_on = [aws_api_gateway_integration.my_pets_get]
}

# Deployment
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.pet_store_api.id

  depends_on = [
    aws_api_gateway_integration.pets_post,
    aws_api_gateway_integration.pets_get,
    aws_api_gateway_integration.pet_get,
    aws_api_gateway_integration.pet_put,
    aws_api_gateway_integration.pet_delete,
    aws_api_gateway_integration.my_pets_get,
    aws_api_gateway_integration_response.pets_post_integration_response,
    aws_api_gateway_integration_response.pets_post_error,
    aws_api_gateway_integration_response.pets_get_integration_response,
    aws_api_gateway_integration_response.pets_get_error,
    aws_api_gateway_integration_response.pet_get_integration_response,
    aws_api_gateway_integration_response.pet_get_error,
    aws_api_gateway_integration_response.pet_put_integration_response,
    aws_api_gateway_integration_response.pet_put_error,
    aws_api_gateway_integration_response.pet_delete_integration_response,
    aws_api_gateway_integration_response.pet_delete_error,
    aws_api_gateway_integration_response.my_pets_get_integration_response,
    aws_api_gateway_integration_response.my_pets_get_error,
    aws_api_gateway_method_response.response_200,
    aws_api_gateway_method_response.response_400,
    aws_api_gateway_method_response.pets_get_response,
    aws_api_gateway_method_response.pet_get_response,
    aws_api_gateway_method_response.pet_put_response,
    aws_api_gateway_method_response.pet_delete_response,
    aws_api_gateway_method_response.my_pets_get_response
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.pet_store_api.id
  stage_name    = "prod"
}

# Outputs
output "api_url" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}/pets"
}

output "cognito_identity_pool_id" {
  value = aws_cognito_identity_pool.main.id
}

data "aws_region" "current" {}