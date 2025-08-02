using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function started - Checking Enterprise Application secrets and certificates."

try {
    # Get query parameters
    $daysThreshold = [int]($Request.Query.DaysThreshold ?? 30)
    $appId = $Request.Query.AppId
    $includeSecrets = ($Request.Query.IncludeSecrets ?? "true") -eq "true"
    $includeCertificates = ($Request.Query.IncludeCertificates ?? "true") -eq "true"
    
    Write-Host "Parameters: DaysThreshold=$daysThreshold, AppId=$appId, IncludeSecrets=$includeSecrets, IncludeCertificates=$includeCertificates"

    # Determine authentication method and connect to Microsoft Graph
    Write-Host "Determining authentication method..."
    
    # Check if running in Azure (managed identity available)
    $isRunningInAzure = $env:WEBSITE_SITE_NAME -or $env:AZURE_CLIENT_ID
    
    if ($isRunningInAzure) {
        Write-Host "Running in Azure - attempting managed identity authentication..."
        try {
            Connect-MgGraph -Identity -NoWelcome
            Write-Host "Successfully connected using managed identity."
        }
        catch {
            $errorMessage = "Managed identity authentication failed in Azure environment: $($_.Exception.Message)"
            Write-Host $errorMessage
            
            $errorResponse = @{
                Success = $false
                Error = "Authentication Failed"
                Details = $errorMessage
                Solution = "Ensure the Function App's managed identity is enabled and has 'Application.Read.All' permissions in Microsoft Graph."
            } | ConvertTo-Json -Depth 5
            
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = $errorResponse
                Headers = @{
                    'Content-Type' = 'application/json'
                }
            })
            return
        }
    }
    else {
        Write-Host "Running locally - using interactive authentication..."
        Write-Host "This will open a browser window for Azure authentication."
        Connect-MgGraph -Scopes "Application.Read.All" -NoWelcome
        Write-Host "Successfully connected using interactive authentication."
    }
    
    # Verify connection and get context
    $context = Get-MgContext
    Write-Host "Connected to tenant: $($context.TenantId) as $($context.Account)"
    
    # Get the current date and threshold date
    $currentDate = Get-Date
    $thresholdDate = $currentDate.AddDays($daysThreshold)
    
    Write-Host "Checking for credentials expiring before: $($thresholdDate.ToString('yyyy-MM-dd'))"
    
    # Initialize results array
    $results = @()
    $summary = @{
        TotalAppsChecked = 0
        AppsWithExpiringCredentials = 0
        ExpiredSecrets = 0
        ExpiringSecrets = 0
        ExpiredCertificates = 0
        ExpiringCertificates = 0
        CheckDate = $currentDate.ToString('yyyy-MM-dd HH:mm:ss UTC')
        DaysThreshold = $daysThreshold
    }
    
    # Get enterprise applications (service principals)
    Write-Host "Retrieving enterprise applications..."
    
    if ($appId) {
        # Get specific application
        $servicePrincipals = @(Get-MgServicePrincipal -Filter "appId eq '$appId'" -All)
        Write-Host "Found specific application with AppId: $appId"
    } else {
        # Get all service principals (enterprise applications)
        $servicePrincipals = Get-MgServicePrincipal -All -Property "Id,AppId,DisplayName,PasswordCredentials,KeyCredentials"
        Write-Host "Found $($servicePrincipals.Count) enterprise applications"
    }
    
    $summary.TotalAppsChecked = $servicePrincipals.Count
    
    foreach ($sp in $servicePrincipals) {
        Write-Host "Checking application: $($sp.DisplayName) (AppId: $($sp.AppId))"
        
        $appHasExpiringCredentials = $false
        
        # Check password credentials (secrets) if enabled
        if ($includeSecrets -and $sp.PasswordCredentials) {
            foreach ($secret in $sp.PasswordCredentials) {
                $expiryDate = [DateTime]$secret.EndDateTime
                $daysUntilExpiry = ($expiryDate - $currentDate).Days
                
                $isExpired = $expiryDate -lt $currentDate
                $isExpiring = $expiryDate -lt $thresholdDate -and -not $isExpired
                
                if ($isExpired -or $isExpiring) {
                    $appHasExpiringCredentials = $true
                    
                    $credentialInfo = @{
                        AppId = $sp.AppId
                        AppDisplayName = $sp.DisplayName
                        CredentialType = "Secret"
                        CredentialId = $secret.KeyId
                        ExpiryDate = $expiryDate.ToString('yyyy-MM-dd HH:mm:ss UTC')
                        DaysUntilExpiry = $daysUntilExpiry
                        Status = if ($isExpired) { "Expired" } else { "Expiring" }
                        Hint = $secret.Hint
                    }
                    
                    $results += $credentialInfo
                    
                    if ($isExpired) {
                        $summary.ExpiredSecrets++
                        Write-Host "  - EXPIRED Secret: KeyId=$($secret.KeyId), Expired on $($expiryDate.ToString('yyyy-MM-dd'))"
                    } else {
                        $summary.ExpiringSecrets++
                        Write-Host "  - EXPIRING Secret: KeyId=$($secret.KeyId), Expires in $daysUntilExpiry days ($($expiryDate.ToString('yyyy-MM-dd')))"
                    }
                }
            }
        }
        
        # Check key credentials (certificates) if enabled
        if ($includeCertificates -and $sp.KeyCredentials) {
            foreach ($cert in $sp.KeyCredentials) {
                $expiryDate = [DateTime]$cert.EndDateTime
                $daysUntilExpiry = ($expiryDate - $currentDate).Days
                
                $isExpired = $expiryDate -lt $currentDate
                $isExpiring = $expiryDate -lt $thresholdDate -and -not $isExpired
                
                if ($isExpired -or $isExpiring) {
                    $appHasExpiringCredentials = $true
                    
                    $credentialInfo = @{
                        AppId = $sp.AppId
                        AppDisplayName = $sp.DisplayName
                        CredentialType = "Certificate"
                        CredentialId = $cert.KeyId
                        ExpiryDate = $expiryDate.ToString('yyyy-MM-dd HH:mm:ss UTC')
                        DaysUntilExpiry = $daysUntilExpiry
                        Status = if ($isExpired) { "Expired" } else { "Expiring" }
                        Usage = $cert.Usage
                        Type = $cert.Type
                    }
                    
                    $results += $credentialInfo
                    
                    if ($isExpired) {
                        $summary.ExpiredCertificates++
                        Write-Host "  - EXPIRED Certificate: KeyId=$($cert.KeyId), Expired on $($expiryDate.ToString('yyyy-MM-dd'))"
                    } else {
                        $summary.ExpiringCertificates++
                        Write-Host "  - EXPIRING Certificate: KeyId=$($cert.KeyId), Expires in $daysUntilExpiry days ($($expiryDate.ToString('yyyy-MM-dd')))"
                    }
                }
            }
        }
        
        if ($appHasExpiringCredentials) {
            $summary.AppsWithExpiringCredentials++
        }
    }
    
    # Disconnect from Microsoft Graph
    Disconnect-MgGraph
    
    # Prepare response
    $responseBody = @{
        Success = $true
        Summary = $summary
        ExpiringCredentials = $results
        Message = if ($results.Count -eq 0) { 
            "No expiring or expired credentials found within $daysThreshold days." 
        } else { 
            "Found $($results.Count) expiring or expired credentials across $($summary.AppsWithExpiringCredentials) applications." 
        }
    } | ConvertTo-Json -Depth 10
    
    Write-Host "Check completed successfully. Found $($results.Count) expiring/expired credentials."
    
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = $responseBody
        Headers = @{
            'Content-Type' = 'application/json'
        }
    })

} catch {
    $errorMessage = "Error checking enterprise application credentials: $($_.Exception.Message)"
    Write-Host $errorMessage
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    
    # Try to disconnect if connected
    try { 
        $context = Get-MgContext -ErrorAction SilentlyContinue
        if ($context) {
            Write-Host "Disconnecting from Microsoft Graph..."
            Disconnect-MgGraph -ErrorAction SilentlyContinue 
        }
    } catch { 
        Write-Host "Note: Could not disconnect from Microsoft Graph cleanly."
    }
    
    $errorResponse = @{
        Success = $false
        Error = $errorMessage
        Details = $_.Exception.Message
        AuthenticationNote = if (-not ($env:WEBSITE_SITE_NAME -or $env:AZURE_CLIENT_ID)) { 
            "When running locally, ensure you have the required permissions and can authenticate interactively." 
        } else { 
            "Ensure the Function App's managed identity has Application.Read.All permissions." 
        }
    } | ConvertTo-Json -Depth 5
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = $errorResponse
        Headers = @{
            'Content-Type' = 'application/json'
        }
    })
}
