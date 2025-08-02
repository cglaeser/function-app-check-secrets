# Local testing script for the Azure Function
# This script simulates calling the function locally for testing purposes

Write-Host "==============================================="
Write-Host "Testing Azure Function Locally"
Write-Host "==============================================="

# Import required modules (ensure they're installed)
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications',
    'Microsoft.Graph.Identity.SignIns'
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
        IncludeSecrets = "true"
        IncludeCertificates = "true"
        # AppId = "12345678-1234-1234-1234-123456789012"  # Uncomment to test specific app
    }
    Body = @{}
}

# Mock TriggerMetadata
$mockTriggerMetadata = @{
    Name = "TestRun"
}

Write-Host "Testing with parameters:"
Write-Host "- DaysThreshold: $($mockRequest.Query.DaysThreshold)"
Write-Host "- IncludeSecrets: $($mockRequest.Query.IncludeSecrets)"
Write-Host "- IncludeCertificates: $($mockRequest.Query.IncludeCertificates)"
if ($mockRequest.Query.AppId) {
    Write-Host "- AppId: $($mockRequest.Query.AppId)"
}
Write-Host ""

# Set parameters as they would be in the function
$Request = $mockRequest
$TriggerMetadata = $mockTriggerMetadata

# Source the function script
$functionPath = Join-Path $PSScriptRoot "check-enterprise-application-secrets\run.ps1"

if (Test-Path $functionPath) {
    Write-Host "Executing function script..."
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
