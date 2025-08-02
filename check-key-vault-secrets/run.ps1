using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function started - Checking Key Vault secrets for expiration."

try {
    # Get query parameters
    $daysThreshold = [int]($Request.Query.DaysThreshold ?? 30)
    $keyVaultName = $Request.Query.KeyVaultName
    $secretName = $Request.Query.SecretName
    $subscriptionId = $Request.Query.SubscriptionId
    
    Write-Host "Parameters: DaysThreshold=$daysThreshold, KeyVaultName=$keyVaultName, SecretName=$secretName, SubscriptionId=$subscriptionId"

    # Determine authentication method and connect to Azure
    Write-Host "Determining authentication method..."
    
    # Check if running in Azure (managed identity available)
    $isRunningInAzure = $env:WEBSITE_SITE_NAME -or $env:AZURE_CLIENT_ID
    
    if ($isRunningInAzure) {
        Write-Host "Running in Azure - attempting managed identity authentication..."
        try {
            Connect-AzAccount -Identity
            Write-Host "Successfully connected using managed identity."
        }
        catch {
            $errorMessage = "Managed identity authentication failed in Azure environment: $($_.Exception.Message)"
            Write-Host $errorMessage
            
            $errorResponse = @{
                Success = $false
                Error = "Authentication Failed"
                Details = $errorMessage
                Solution = "Ensure the Function App's managed identity is enabled and has 'Key Vault Secrets User' or 'Key Vault Reader' role on the Key Vaults, and 'Reader' role on the subscription."
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
        Connect-AzAccount
        Write-Host "Successfully connected using interactive authentication."
    }
    
    # Get current Azure context
    $context = Get-AzContext
    Write-Host "Connected to subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
    Write-Host "Account: $($context.Account.Id)"
    
    # Set subscription if specified
    if ($subscriptionId) {
        Write-Host "Setting subscription context to: $subscriptionId"
        Set-AzContext -SubscriptionId $subscriptionId
        $context = Get-AzContext
        Write-Host "Updated context - Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
    }
    
    # Get the current date and threshold date
    $currentDate = Get-Date
    $thresholdDate = $currentDate.AddDays($daysThreshold)
    
    Write-Host "Checking for secrets expiring before: $($thresholdDate.ToString('yyyy-MM-dd'))"
    
    # Initialize results array
    $results = @()
    $keyVaultsChecked = @()
    $summary = @{
        TotalKeyVaultsChecked = 0
        TotalSecretsChecked = 0
        KeyVaultsWithExpiringCredentials = 0
        ExpiredSecrets = 0
        ExpiringSecrets = 0
        InaccessibleKeyVaults = 0
        CheckDate = $currentDate.ToString('yyyy-MM-dd HH:mm:ss UTC')
        DaysThreshold = $daysThreshold
        SubscriptionId = $context.Subscription.Id
        SubscriptionName = $context.Subscription.Name
    }
    
    # Get Key Vaults
    Write-Host "Retrieving Key Vaults..."
    
    if ($keyVaultName) {
        # Get specific Key Vault
        try {
            $keyVaults = @(Get-AzKeyVault -VaultName $keyVaultName)
            Write-Host "Found specific Key Vault: $keyVaultName"
        }
        catch {
            Write-Host "Error retrieving specific Key Vault '$keyVaultName': $($_.Exception.Message)"
            throw "Key Vault '$keyVaultName' not found or not accessible."
        }
    } else {
        # Get all Key Vaults in the subscription
        $keyVaults = Get-AzKeyVault
        Write-Host "Found $($keyVaults.Count) Key Vaults in subscription"
    }
    
    $summary.TotalKeyVaultsChecked = $keyVaults.Count
    
    foreach ($kv in $keyVaults) {
        Write-Host "Checking Key Vault: $($kv.VaultName)"
        
        $keyVaultHasExpiringSecrets = $false
        $keyVaultInfo = @{
            VaultName = $kv.VaultName
            ResourceGroupName = $kv.ResourceGroupName
            Location = $kv.Location
            SecretsChecked = 0
            ExpiringSecrets = 0
            ExpiredSecrets = 0
            Status = "Unknown"
            ErrorMessage = $null
        }
        
        try {
            # Get all secrets in the Key Vault
            if ($secretName) {
                # Get specific secret
                $secrets = @(Get-AzKeyVaultSecret -VaultName $kv.VaultName -Name $secretName -ErrorAction Stop)
                Write-Host "  Found specific secret: $secretName"
            } else {
                # Get all secrets
                $secrets = Get-AzKeyVaultSecret -VaultName $kv.VaultName -ErrorAction Stop
                Write-Host "  Found $($secrets.Count) secrets in Key Vault"
            }
            
            $keyVaultInfo.SecretsChecked = $secrets.Count
            $summary.TotalSecretsChecked += $secrets.Count
            
            foreach ($secret in $secrets) {
                # Get secret details including expiration
                try {
                    $secretDetail = Get-AzKeyVaultSecret -VaultName $kv.VaultName -Name $secret.Name -AsPlainText:$false -ErrorAction Stop
                    
                    if ($secretDetail.Expires) {
                        $expiryDate = $secretDetail.Expires
                        $daysUntilExpiry = ($expiryDate - $currentDate).Days
                        
                        $isExpired = $expiryDate -lt $currentDate
                        $isExpiring = $expiryDate -lt $thresholdDate -and -not $isExpired
                        
                        if ($isExpired -or $isExpiring) {
                            $keyVaultHasExpiringSecrets = $true
                            
                            $secretInfo = @{
                                KeyVaultName = $kv.VaultName
                                SecretName = $secret.Name
                                ExpiryDate = $expiryDate.ToString('yyyy-MM-dd HH:mm:ss UTC')
                                DaysUntilExpiry = $daysUntilExpiry
                                Status = if ($isExpired) { "Expired" } else { "Expiring" }
                                Created = $secret.Created.ToString('yyyy-MM-dd HH:mm:ss UTC')
                                Updated = $secret.Updated.ToString('yyyy-MM-dd HH:mm:ss UTC')
                                Enabled = $secret.Enabled
                                Version = $secret.Version
                                Tags = $secret.Tags
                            }
                            
                            $results += $secretInfo
                            
                            if ($isExpired) {
                                $summary.ExpiredSecrets++
                                $keyVaultInfo.ExpiredSecrets++
                                Write-Host "    - EXPIRED Secret: $($secret.Name), Expired on $($expiryDate.ToString('yyyy-MM-dd'))"
                            } else {
                                $summary.ExpiringSecrets++
                                $keyVaultInfo.ExpiringSecrets++
                                Write-Host "    - EXPIRING Secret: $($secret.Name), Expires in $daysUntilExpiry days ($($expiryDate.ToString('yyyy-MM-dd')))"
                            }
                        }
                    } else {
                        Write-Host "    - Secret '$($secret.Name)' has no expiration date set"
                    }
                }
                catch {
                    Write-Host "    - Warning: Could not access secret details for '$($secret.Name)': $($_.Exception.Message)"
                }
            }
            
            if ($keyVaultHasExpiringSecrets) {
                $summary.KeyVaultsWithExpiringCredentials++
            }
            
            # Set success status for accessible Key Vault
            $keyVaultInfo.Status = "Accessible"
            
        }
        catch {
            $summary.InaccessibleKeyVaults++
            $keyVaultInfo.Status = "Inaccessible"
            $keyVaultInfo.ErrorMessage = $_.Exception.Message
            Write-Host "  Error accessing Key Vault '$($kv.VaultName)': $($_.Exception.Message)"
            
            # Add inaccessible Key Vault to results
            $inaccessibleInfo = @{
                KeyVaultName = $kv.VaultName
                SecretName = "N/A"
                ExpiryDate = "N/A"
                DaysUntilExpiry = "N/A"
                Status = "Inaccessible"
                Error = $_.Exception.Message
                Created = "N/A"
                Updated = "N/A"
                Enabled = "N/A"
                Version = "N/A"
                Tags = @{}
            }
            
            $results += $inaccessibleInfo
        }
        
        # Add Key Vault info to tracking array
        $keyVaultsChecked += $keyVaultInfo
    }
    
    # Disconnect from Azure
    Disconnect-AzAccount -Confirm:$false | Out-Null
    
    # Prepare response
    $responseBody = @{
        Success = $true
        Summary = $summary
        KeyVaultsChecked = $keyVaultsChecked
        ExpiringSecrets = $results
        Message = if ($results.Count -eq 0) { 
            "No expiring or expired secrets found within $daysThreshold days." 
        } else { 
            "Found $($summary.ExpiredSecrets + $summary.ExpiringSecrets) expiring or expired secrets across $($summary.KeyVaultsWithExpiringCredentials) Key Vaults." 
        }
        Notes = @(
            if ($summary.InaccessibleKeyVaults -gt 0) { "Warning: $($summary.InaccessibleKeyVaults) Key Vault(s) were inaccessible due to permissions." }
            "Only secrets with expiration dates are checked for expiration."
            "Ensure the Function App's managed identity has 'Key Vault Secrets User' or 'Key Vault Reader' role on all Key Vaults."
        )
    } | ConvertTo-Json -Depth 10
    
    Write-Host "Check completed successfully. Found $($summary.ExpiredSecrets + $summary.ExpiringSecrets) expiring/expired secrets."
    
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = $responseBody
        Headers = @{
            'Content-Type' = 'application/json'
        }
    })

} catch {
    $errorMessage = "Error checking Key Vault secrets: $($_.Exception.Message)"
    Write-Host $errorMessage
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    
    # Try to disconnect if connected
    try { 
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if ($context) {
            Write-Host "Disconnecting from Azure..."
            Disconnect-AzAccount -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { 
        Write-Host "Note: Could not disconnect from Azure cleanly."
    }
    
    $errorResponse = @{
        Success = $false
        Error = $errorMessage
        Details = $_.Exception.Message
        AuthenticationNote = if (-not ($env:WEBSITE_SITE_NAME -or $env:AZURE_CLIENT_ID)) { 
            "When running locally, ensure you have the required permissions to access Key Vaults and can authenticate interactively." 
        } else { 
            "Ensure the Function App's managed identity has 'Key Vault Secrets User' or 'Key Vault Reader' role on the Key Vaults." 
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
