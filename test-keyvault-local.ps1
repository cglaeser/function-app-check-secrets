# Local testing script for the Key Vault Secrets Azure Function
# This script simulates calling the Key Vault secrets function locally for testing purposes

Write-Host "==============================================="
Write-Host "Testing Key Vault Secrets Function Locally"
Write-Host "==============================================="

# Import required modules (ensure they're installed)
$requiredModules = @(
    'Az.Accounts',
    'Az.KeyVault',
    'Az.Profile'
)

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing module: $module"
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module $module -Force
}

# Create a mock request object for testing
$mockRequest = @{
    Query = @{
        DaysThreshold = "60"
        # KeyVaultName = "my-key-vault"  # Uncomment to test specific Key Vault
        # SecretName = "my-secret"       # Uncomment to test specific secret
        # SubscriptionId = "12345678-1234-1234-1234-123456789012"  # Uncomment to test specific subscription
    }
    Body = @{}
}

# Mock TriggerMetadata
$mockTriggerMetadata = @{
    Name = "KeyVaultTestRun"
}

Write-Host "Testing with parameters:"
Write-Host "- DaysThreshold: $($mockRequest.Query.DaysThreshold)"
if ($mockRequest.Query.KeyVaultName) {
    Write-Host "- KeyVaultName: $($mockRequest.Query.KeyVaultName)"
}
if ($mockRequest.Query.SecretName) {
    Write-Host "- SecretName: $($mockRequest.Query.SecretName)"
}
if ($mockRequest.Query.SubscriptionId) {
    Write-Host "- SubscriptionId: $($mockRequest.Query.SubscriptionId)"
}
Write-Host ""

# Set parameters as they would be in the function
$Request = $mockRequest
$TriggerMetadata = $mockTriggerMetadata

# Source the function script
$functionPath = Join-Path $PSScriptRoot "check-key-vault-secrets\run.ps1"

if (Test-Path $functionPath) {
    Write-Host "Executing Key Vault secrets function script..."
    Write-Host "==============================================="
    
    # Execute the function script
    . $functionPath
    
    Write-Host "==============================================="
    Write-Host "Function execution completed."
} else {
    Write-Host "Error: Function script not found at: $functionPath"
    Write-Host "Please ensure you're running this script from the function app root directory."
}

Write-Host ""
Write-Host "Note: This test script simulates the Azure Function runtime environment."
Write-Host "The actual Push-OutputBinding calls are executed but won't have the same effect as in Azure."
Write-Host ""
Write-Host "Required Permissions:"
Write-Host "- 'Key Vault Reader' or 'Key Vault Secrets User' role on Key Vaults"
Write-Host "- 'Reader' role on the subscription (to list Key Vaults)"
