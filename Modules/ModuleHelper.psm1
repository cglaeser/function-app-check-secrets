# Module installation helper for Flex Consumption Plan
# This script provides optimized module installation with caching

function Install-RequiredModules {
    param(
        [string[]]$ModuleNames,
        [string]$CachePath = "$env:TEMP\PSModules"
    )
    
    Write-Host "Starting module installation process..."
    
    # Create cache directory if it doesn't exist
    if (-not (Test-Path $CachePath)) {
        New-Item -Path $CachePath -ItemType Directory -Force | Out-Null
    }
    
    # Set module path to include cache
    $env:PSModulePath = "$CachePath;$env:PSModulePath"
    
    foreach ($moduleName in $ModuleNames) {
        try {
            # Check if module is already available
            if (Get-Module -ListAvailable -Name $moduleName) {
                Write-Host "Module '$moduleName' already available, importing..."
                Import-Module $moduleName -Force -Scope Global
                continue
            }
            
            Write-Host "Installing module: $moduleName"
            $startTime = Get-Date
            
            # Install module with optimized parameters for Azure Functions
            Install-Module -Name $moduleName `
                          -Force `
                          -AllowClobber `
                          -Scope CurrentUser `
                          -Repository PSGallery `
                          -SkipPublisherCheck `
                          -AcceptLicense `
                          -Verbose:$false
            
            $installTime = (Get-Date) - $startTime
            Write-Host "Module '$moduleName' installed in $($installTime.TotalSeconds) seconds"
            
            # Import the module
            Import-Module $moduleName -Force -Scope Global
            Write-Host "Module '$moduleName' imported successfully"
            
        } catch {
            Write-Error "Failed to install/import module '$moduleName': $($_.Exception.Message)"
            throw
        }
    }
    
    Write-Host "All modules installed and imported successfully"
}

# Export the function for use in other scripts
Export-ModuleMember -Function Install-RequiredModules
