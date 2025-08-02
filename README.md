# Azure Function App: Secrets & Certificates Expiration Checker

This Azure Function App contains multiple functions to check for expired and expiring secrets and certificates across different Azure services.

## Functions Included

### 1. **Enterprise Application Secrets & Certificates Checker**

- **Endpoint**: `/api/check-enterprise-application-secrets`
- **Purpose**: Checks expired/expiring secrets and certificates in Azure Enterprise Applications (Service Principals)

### 2. **Key Vault Secrets Expiration Checker**

- **Endpoint**: `/api/check-key-vault-secrets`
- **Purpose**: Checks expired/expiring secrets across all Key Vaults in a subscription

## Features

- ✅ **Enterprise Applications**: Check secrets (password credentials) and certificates expiration
- ✅ **Key Vault Secrets**: Check secret expiration across all Key Vaults in subscription
- ✅ Configurable expiration threshold
- ✅ Filter by specific application ID or Key Vault name
- ✅ Comprehensive reporting with summary statistics
- ✅ Proper error handling and logging
- ✅ **Smart Authentication**: Uses managed identity in Azure, interactive login locally
- ✅ **Local Development Support**: Automatic fallback to interactive authentication for testing## Authentication Methods

This function supports two authentication methods:

### 1. **Managed Identity (Production)**

- Used when running in Azure Function App
- Automatic detection based on environment variables
- No user interaction required
- Requires `Application.Read.All` permissions

### 2. **Interactive Authentication (Local Development)**

- Used when running locally for testing
- Opens browser for Azure AD authentication
- Requires user with appropriate permissions
- Automatically detected when not in Azure environment## Prerequisites

### 1. Azure Function App Configuration

- **Runtime**: PowerShell 7.4
- **Managed Identity**: System-assigned managed identity must be enabled

### 2. Required Permissions

The Function App's managed identity needs the following Microsoft Graph API permissions:

- `Application.Read.All` - To read all applications and their credentials

### 3. Grant Permissions

```bash
# Get the Function App's managed identity object ID
az functionapp identity show --name <function-app-name> --resource-group <resource-group>

# Grant Application.Read.All permission
az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/<managed-identity-object-id>/appRoleAssignments" \
  --body '{
    "principalId": "<managed-identity-object-id>",
    "resourceId": "<graph-service-principal-object-id>",
    "appRoleId": "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30"
  }'
```

## API Usage

### Endpoint

```
GET/POST https://<function-app-name>.azurewebsites.net/api/check-enterprise-application-secrets
```

### Query Parameters

| Parameter             | Type    | Default | Description                                            |
| --------------------- | ------- | ------- | ------------------------------------------------------ |
| `DaysThreshold`       | int     | 30      | Number of days ahead to check for expiring credentials |
| `AppId`               | string  | null    | Specific application ID to check (optional)            |
| `IncludeSecrets`      | boolean | true    | Whether to check password credentials                  |
| `IncludeCertificates` | boolean | true    | Whether to check certificate credentials               |

### Example Requests

#### Check all applications with default 30-day threshold

```bash
curl "https://your-function-app.azurewebsites.net/api/check-enterprise-application-secrets?code=<function-key>"
```

#### Check with 60-day threshold

```bash
curl "https://your-function-app.azurewebsites.net/api/check-enterprise-application-secrets?DaysThreshold=60&code=<function-key>"
```

#### Check specific application

```bash
curl "https://your-function-app.azurewebsites.net/api/check-enterprise-application-secrets?AppId=12345678-1234-1234-1234-123456789012&code=<function-key>"
```

#### Check only certificates

```bash
curl "https://your-function-app.azurewebsites.net/api/check-enterprise-application-secrets?IncludeSecrets=false&code=<function-key>"
```

### Response Format

#### Success Response

```json
{
  "Success": true,
  "Summary": {
    "TotalAppsChecked": 25,
    "AppsWithExpiringCredentials": 3,
    "ExpiredSecrets": 1,
    "ExpiringSecrets": 2,
    "ExpiredCertificates": 0,
    "ExpiringCertificates": 1,
    "CheckDate": "2025-08-02 10:30:00 UTC",
    "DaysThreshold": 30
  },
  "ExpiringCredentials": [
    {
      "AppId": "12345678-1234-1234-1234-123456789012",
      "AppDisplayName": "My Enterprise App",
      "CredentialType": "Secret",
      "CredentialId": "abcd1234-5678-9012-3456-789012345678",
      "ExpiryDate": "2025-08-15 00:00:00 UTC",
      "DaysUntilExpiry": 13,
      "Status": "Expiring",
      "Hint": "abc"
    }
  ],
  "Message": "Found 4 expiring or expired credentials across 3 applications."
}
```

#### Error Response

```json
{
  "Success": false,
  "Error": "Error checking enterprise application credentials: Access denied",
  "Details": "Insufficient privileges to complete the operation."
}
```

---

## Key Vault Secrets API

### Endpoint

```
GET/POST https://<function-app-name>.azurewebsites.net/api/check-key-vault-secrets
```

### Query Parameters

| Parameter        | Type   | Default | Description                                        |
| ---------------- | ------ | ------- | -------------------------------------------------- |
| `DaysThreshold`  | int    | 30      | Number of days ahead to check for expiring secrets |
| `KeyVaultName`   | string | null    | Specific Key Vault name to check (optional)        |
| `SecretName`     | string | null    | Specific secret name to check (optional)           |
| `SubscriptionId` | string | null    | Specific subscription ID to use (optional)         |

### Example Requests

#### Check all Key Vaults with default 30-day threshold

```bash
curl "https://your-function-app.azurewebsites.net/api/check-key-vault-secrets?code=<function-key>"
```

#### Check with 90-day threshold

```bash
curl "https://your-function-app.azurewebsites.net/api/check-key-vault-secrets?DaysThreshold=90&code=<function-key>"
```

#### Check specific Key Vault

```bash
curl "https://your-function-app.azurewebsites.net/api/check-key-vault-secrets?KeyVaultName=my-key-vault&code=<function-key>"
```

#### Check specific secret in specific Key Vault

```bash
curl "https://your-function-app.azurewebsites.net/api/check-key-vault-secrets?KeyVaultName=my-key-vault&SecretName=my-secret&code=<function-key>"
```

### Response Format

#### Success Response

```json
{
  "Success": true,
  "Summary": {
    "TotalKeyVaultsChecked": 5,
    "TotalSecretsChecked": 25,
    "KeyVaultsWithExpiringCredentials": 2,
    "ExpiredSecrets": 1,
    "ExpiringSecrets": 3,
    "InaccessibleKeyVaults": 0,
    "CheckDate": "2025-08-02 10:30:00 UTC",
    "DaysThreshold": 30,
    "SubscriptionId": "12345678-1234-1234-1234-123456789012",
    "SubscriptionName": "Production Subscription"
  },
  "KeyVaultsChecked": [
    {
      "VaultName": "prod-key-vault",
      "ResourceGroupName": "production-rg",
      "Location": "East US",
      "SecretsChecked": 15,
      "ExpiringSecrets": 2,
      "ExpiredSecrets": 1,
      "Status": "Accessible",
      "ErrorMessage": null
    },
    {
      "VaultName": "dev-key-vault",
      "ResourceGroupName": "development-rg",
      "Location": "West US",
      "SecretsChecked": 10,
      "ExpiringSecrets": 1,
      "ExpiredSecrets": 0,
      "Status": "Accessible",
      "ErrorMessage": null
    }
  ],
  "ExpiringSecrets": [
    {
      "KeyVaultName": "prod-key-vault",
      "SecretName": "database-password",
      "ExpiryDate": "2025-08-15 00:00:00 UTC",
      "DaysUntilExpiry": 13,
      "Status": "Expiring",
      "Created": "2024-01-15 10:30:00 UTC",
      "Updated": "2024-06-01 14:20:00 UTC",
      "Enabled": true,
      "Version": "abc123",
      "Tags": {
        "Environment": "Production",
        "Owner": "DatabaseTeam"
      }
    }
  ],
  "Message": "Found 4 expiring or expired secrets across 2 Key Vaults.",
  "Notes": [
    "Only secrets with expiration dates are checked for expiration.",
    "Ensure the Function App's managed identity has 'Key Vault Secrets User' or 'Key Vault Reader' role on all Key Vaults."
  ]
}
```

#### Error Response

```json
{
  "Success": false,
  "Error": "Error checking Key Vault secrets: Access denied",
  "Details": "The user or application does not have access to the key vault.",
  "AuthenticationNote": "Ensure the Function App's managed identity has 'Key Vault Secrets User' or 'Key Vault Reader' role on the Key Vaults."
}
```

### Required Permissions for Key Vault Function

#### Production (Managed Identity)

- **Key Vault**: `Key Vault Secrets User` or `Key Vault Reader` role on each Key Vault
- **Subscription**: `Reader` role to list Key Vaults

#### Local Development

- Your Azure account needs the same permissions as listed above

---

## Local Development & Testing

### Prerequisites for Local Testing

1. **PowerShell 7.4+** installed
2. **Azure PowerShell modules** (automatically installed by test script)
3. **Azure account** with `Application.Read.All` permissions

### Running Locally

```bash
# Option 1: Use the provided test scripts

# Test Enterprise Applications function
./test-local.ps1

# Test Key Vault secrets function
./test-keyvault-local.ps1

# Option 2: Use Azure Functions Core Tools (runs both functions)
func start
```

### Test Script Features

- **Separate test scripts** for each function type
- Automatically installs required PowerShell modules
- Simulates the Azure Function runtime environment
- Supports all query parameters
- Uses interactive authentication automatically

### Interactive Authentication Flow

When running locally, the function will:

1. Detect it's not running in Azure
2. Prompt for interactive authentication
3. Open your default browser for Azure AD login
4. Use your credentials to access Microsoft Graph

### Local Testing Example

```powershell
# Run the test script with custom parameters
$mockRequest = @{
    Query = @{
        DaysThreshold = "60"
        IncludeSecrets = "true"
        IncludeCertificates = "true"
    }
}
```

## Deployment

### Using Azure CLI

```bash
# Deploy the function app
func azure functionapp publish <function-app-name>

# Enable managed identity
az functionapp identity assign --name <function-app-name> --resource-group <resource-group>
```

### Using Azure DevOps/GitHub Actions

See the deployment pipeline configuration in `.github/workflows/` or `azure-pipelines.yml`.

## Monitoring and Alerts

### Application Insights Queries

```kusto
// Find function executions with errors
traces
| where message contains "Error checking enterprise application credentials"
| order by timestamp desc

// Monitor credential expiration trends
traces
| where message contains "Found" and message contains "expiring"
| extend CredentialCount = extract(@"Found (\d+)", 1, message)
| order by timestamp desc
```

### Recommended Alerts

1. **Function Execution Failures**: Alert when the function fails
2. **High Number of Expiring Credentials**: Alert when more than X credentials are expiring
3. **Expired Credentials Detected**: Immediate alert for any expired credentials

## Security Considerations

- ✅ Uses managed identity (no stored credentials)
- ✅ Follows principle of least privilege
- ✅ Sensitive data is not logged
- ✅ Proper error handling prevents information disclosure
- ✅ Function key required for access

## Troubleshooting

### Common Issues

#### Production (Azure)

1. **"Access denied" errors**: Verify the managed identity has `Application.Read.All` permissions
2. **"Connect-MgGraph" fails**: Ensure managed identity is enabled and has proper permissions
3. **No applications found**: Check if the managed identity can access the tenant's applications

#### Local Development

1. **"Interactive authentication failed"**: Ensure your account has `Application.Read.All` permissions
2. **Browser doesn't open**: Try running `Connect-MgGraph -Scopes "Application.Read.All"` manually first
3. **Module not found errors**: Run `./test-local.ps1` which auto-installs required modules
4. **Permission errors**: Ensure you're logged into the correct tenant with appropriate permissions

### Authentication Detection

The function automatically detects the environment using these indicators:

- **Azure Environment**: `$env:WEBSITE_SITE_NAME` or `$env:AZURE_CLIENT_ID` is present
- **Local Environment**: Neither environment variable is present

### Logs Location

- **Application Insights**: Check the `traces` table for detailed logs
- **Function App Logs**: Available in the Azure portal under Monitoring > Log stream

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test locally
4. Submit a pull request

## License

This project is licensed under the MIT License.
