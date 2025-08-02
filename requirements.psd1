# This file enables modules to be automatically managed by the Functions service.
# See https://aka.ms/functionsmanageddependency for additional information.
#
@{
    # Azure PowerShell modules for Microsoft Graph and Key Vault operations
    'Microsoft.Graph.Authentication' = '2.*'
    'Microsoft.Graph.Applications' = '2.*'
    'Microsoft.Graph.Identity.SignIns' = '2.*'
    'Az.Accounts' = '3.*'
    'Az.KeyVault' = '4.*'
}