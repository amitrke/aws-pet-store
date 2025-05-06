# Pet Store API - Technical Requirements Document

## 1. Overview
Build a serverless Pet Store API with CRUD operations that:
- Uses API Gateway for REST endpoints  
- Directly integrates with DynamoDB (no Lambda)
- Implements user authentication via Google OAuth  
- Enforces data isolation (users can only modify their own pets)
- Allows public read access to all pets

## 2. Technical Specifications

### 2.1 Core Components
| Component          | Technology       | Description                                                                 |
|--------------------|------------------|-----------------------------------------------------------------------------|
| API Gateway        | AWS API Gateway  | REST API with IAM authorization                                             |
| Database           | DynamoDB         | Single-table design with `id` (PK) and `userId` (GSI)                       |
| Authentication     | Cognito Identity | Google OAuth integration via Identity Pool                                  |
| Infrastructure     | Terraform        | Infrastructure-as-code provisioning                                         |

### 2.2 API Endpoints
| Endpoint          | Method | Auth | Description                                                                 |
|-------------------|--------|------|-----------------------------------------------------------------------------|
| `/pets`           | POST   | IAM  | Create new pet (auto-generates ID, adds user context)                       |
| `/pets`           | GET    | IAM  | List all pets (public read)                                                 |
| `/pets/{id}`      | GET    | IAM  | Get specific pet details                                                    |
| `/pets/{id}`      | PUT    | IAM  | Update pet (only if `userId` matches)                                       |
| `/pets/{id}`      | DELETE | IAM  | Delete pet (only if `userId` matches)                                       |
| `/my-pets`        | GET    | IAM  | List only current user's pets (uses GSI query)                              |

### 2.3 Data Model
**DynamoDB Table: `PetStore`**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",  // PK (string)
  "userId": "us-east-1:1234...",  // GSI (from Cognito Identity ID)
  "name": "Fluffy",               // (string)
  "type": "Cat",                  // (string)
  "age": 3,                       // (number)
  "createdAt": "2023-11-15T12:00:00Z"  // (string)
}
```

### 2.4 Authentication Flow

1.  **Client**  authenticates with Google OAuth
    
2.  **Exchange**  Google token for Cognito Identity credentials
    
3.  **Sign**  API requests with AWS SigV4 using temporary credentials
    
4.  **API Gateway**  validates IAM permissions
    
5.  **DynamoDB**  enforces user isolation via conditional writes
    

### 2.5 Security Requirements

-   Data isolation: Users can only modify records where  `userId == $context.identity.cognitoIdentityId`
    
-   Public read access for all authenticated users
    
-   Google OAuth with minimum scopes:  `openid profile email`
    
-   IAM policy with least-privilege access
    
-   All API traffic over HTTPS
    

## 3. Infrastructure Requirements

### 3.1 Terraform Modules Needed

```hcl
module "authentication" {
  # Cognito Identity Pool + Google OAuth config
}

module "database" {
  # DynamoDB table with GSI on userId
}

module "api_gateway" {
  # REST API with IAM auth and VTL templates
}

module "iam_roles" {
  # IAM roles for Cognito identities
}
```

### 3.2 VTL Template Samples

**Create Pet Template:**

```vtl
{
  "TableName": "PetStore",
  "Item": {
    "id": {"S": "$context.requestId"},
    "userId": {"S": "$context.identity.cognitoIdentityId"},
    "name": {"S": "$input.path('$.name')"},
    "type": {"S": "$input.path('$.type')"},
    "age": {"N": "$input.path('$.age')"},
    "createdAt": {"S": "$context.requestTime"}
  }
}
```

## 4. Deployment Pipeline

1.  **Infrastructure Provisioning**

    ```bash
    terraform apply -var="google_client_id=$GOOGLE_CLIENT_ID"
    ```

2.  **CI/CD Pipeline (Example)**

    ```yaml
    steps:
        - terraform validate
        - terraform plan
        - terraform apply -auto-approve
    ```

## 5. Test Cases

| Scenario          | Request | Expected Result | 
|-------------------|---------|-----------------|
| Create pet        | POST /pets with valid Google token	    | 200 OK, returns generated ID                       |
| Create pet        | POST /pets without token                  | 403 Forbidden                                      |
| Update other user's pet | PUT /pets/{id} with different userId | 403 Forbidden                                      |
| Get pet          | GET /pets/{id} with valid token          | 200 OK, returns pet details                        |
| List pets        | GET /pets with valid token               | 200 OK, returns list of all pets                   |
| Get my pets     | GET /my-pets with valid token               | 200 OK, returns list of user's pets                 |
| Delete pet       | DELETE /pets/{id} with valid token        | 200 OK, pet deleted                                 |
| Delete pet       | DELETE /pets/{id} without token           | 403 Forbidden                                      |

## 6. Dependencies

1.  Google Developer Project with OAuth credentials
    
2.  AWS account with permissions to create:
    -   Cognito Identity Pools
    -   API Gateway
    -   DynamoDB
    -   IAM roles

## 7. Open Questions
-   Should pet images be supported? (S3 integration)
-   Need advanced search capabilities? (Elasticsearch integration)
-   Any rate limiting requirements?