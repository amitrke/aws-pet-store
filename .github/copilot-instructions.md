# AWS Pet Store API - Copilot Instructions

## Project Context
**Objective**: Build a serverless Pet Store API with:
- AWS API Gateway direct DynamoDB integration
- Google authentication via Cognito Identity Pools
- Terraform infrastructure-as-code
- User-specific data isolation

## Coding Patterns

### Terraform Patterns
```hcl
# Preferred resource naming
resource "aws_dynamodb_table" "pet_store" {
  name = "${var.env}-pet-store"  # Environment-prefixed names
}

# Module structure
module "authentication" {
  source = "./modules/auth"
  google_client_id = var.google_client_id
}

# Variable conventions
variable "env" {
  description = "Deployment environment (dev/stage/prod)"
  type        = string
  default     = "dev"
}
```

### API Gateway Patterns
```vtl
// VTL Template Convention
#set($inputRoot = $input.path('$'))
{
  "TableName": "PetStore",
  "Item": {
    "id": {"S": "$context.requestId"},
    // Always include userId from Cognito context
    "userId": {"S": "$context.identity.cognitoIdentityId"}
  }
}
```

## Special Instructions

1.  **AWS Direct Integration**:
    
    -   Prefer API Gateway direct DynamoDB integration over Lambda
        
    -   Use VTL for request/response transformation
        
    -   Implement conditional writes for user isolation
        
2.  **Security Requirements**:
    
    -   All IAM policies must follow least privilege
        
    -   Google OAuth scope limited to email/profile
        
    -   Encrypt DynamoDB at rest (default)
        
    -   Never hardcode credentials - use Terraform variables
        
3.  **Error Handling**:

    ```vtl
    // Example error response template
    #if($context.error.message)
    {
    "error": "$context.error.message",
    "requestId": "$context.requestId"
    }
    #end
    ```

4.  **Testing Guidance**:
    ```bash
    # Preferred test command
    aws apigateway test-invoke-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --body '{"name":"Test","type":"Dog","age":3}'
    ```

## Anti-Patterns to Avoid

❌ Using Lambda functions for CRUD operations  
❌ Storing user credentials in code/configuration  
❌ Wide-open IAM permissions (e.g., dynamodb:*)  
❌ Hardcoded environment-specific values

## Collaboration Tips

1.  **Documentation**:
    
    -   Update OpenAPI spec in  `/docs`  after API changes
        
    -   Keep Terraform module READMEs current
        
2.  **PR Checks**:
    
    -   Terraform validate/format on commit
        
    -   VTL template validation using AWS CLI
        
    -   IAM policy security audit using  `iam-lint`
        
3.  **Review Focus**:
    
    -   Verify Cognito Identity ID usage in VTL templates
        
    -   Check conditional expressions in DynamoDB operations
        
    -   Validate environment variable handling
        
    -   Confirm Google OAuth configuration
        

## Knowledge Base

Key Files:

-   `infra/main.tf`  - Core infrastructure
    
-   `api_gateway/vtl_templates/`  - Mapping templates
    
-   `modules/auth/cognito.tf`  - Authentication setup
    

Reference Architectures:

-   [AWS API Gateway Direct Integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-dynamodb.html)
    
-   [Cognito Google Federation](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-identity-federation-google.html)