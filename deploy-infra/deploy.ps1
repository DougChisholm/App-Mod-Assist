<#
.SYNOPSIS
    Deploys the Expense Management System infrastructure to Azure.

.DESCRIPTION
    This script automates the complete deployment of the Expense Management System including:
    - Azure resource group creation
    - Infrastructure deployment via Bicep (App Service, SQL, Managed Identity, Monitoring)
    - Optional GenAI resources (Azure OpenAI, AI Search)
    - Database schema import
    - Managed identity database role configuration
    - Stored procedures creation
    - App Service configuration

.PARAMETER ResourceGroup
    The name of the Azure resource group to create/use.

.PARAMETER Location
    The Azure region for deployment (e.g., uksouth, eastus).

.PARAMETER BaseName
    Base name for Azure resources. Resources will be named using this prefix.

.PARAMETER DeployGenAI
    Switch to deploy Azure OpenAI and AI Search resources.

.PARAMETER SkipDatabaseSetup
    Switch to skip database schema and configuration steps (useful for redeployments).

.EXAMPLE
    .\deploy.ps1 -ResourceGroup "rg-expensemgmt-demo" -Location "uksouth"

.EXAMPLE
    .\deploy.ps1 -ResourceGroup "rg-expensemgmt-demo" -Location "uksouth" -DeployGenAI

.EXAMPLE
    .\deploy.ps1 -ResourceGroup "rg-expensemgmt-demo" -Location "uksouth" -DeployGenAI -SkipDatabaseSetup
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [string]$BaseName = "expensemgmt",

    [Parameter(Mandatory = $false)]
    [switch]$DeployGenAI,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDatabaseSetup
)

# Set error preference - but we'll handle az CLI errors manually to allow warnings
$ErrorActionPreference = "Continue"

# Detect CI/CD environment
$IsCI = $env:GITHUB_ACTIONS -eq "true" -or $env:TF_BUILD -eq "true" -or $env:CI -eq "true"

# Check PowerShell version and warn if using older version (skip in CI)
if (-not $IsCI -and $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "[WARNING] You are running PowerShell $($PSVersionTable.PSVersion). PowerShell 7+ is recommended." -ForegroundColor Yellow
    Write-Host "          Install with: winget install Microsoft.PowerShell" -ForegroundColor Yellow
    Write-Host ""
}

# Colors for output
function Write-Step { param($Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Success { param($Message) Write-Host "    [OK] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "    $Message" -ForegroundColor White }
function Write-Warning { param($Message) Write-Host "    [WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "    [ERROR] $Message" -ForegroundColor Red }

# Banner
Write-Host ""
Write-Host "=========================================" -ForegroundColor Magenta
Write-Host "  Expense Management System Deployment" -ForegroundColor Magenta
if ($IsCI) {
    Write-Host "  (CI/CD Mode - OIDC Authentication)" -ForegroundColor Magenta
}
Write-Host "=========================================" -ForegroundColor Magenta
Write-Host ""

# Validate Azure CLI is installed and logged in
Write-Step "Validating prerequisites"
try {
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        throw "Not logged into Azure CLI"
    }
    Write-Success "Logged into Azure CLI as $($account.user.name)"
    Write-Info "Subscription: $($account.name) ($($account.id))"
} catch {
    Write-Error "Please login to Azure CLI first: az login"
    exit 1
}

# Get current user's Azure AD information
Write-Step "Getting Azure AD information for SQL admin"

# Variables for admin identity
$adminObjectId = $null
$adminLogin = $null
$adminPrincipalType = "User"

if ($IsCI) {
    # CI/CD mode: Use the Service Principal from OIDC
    $servicePrincipalClientId = $env:AZURE_CLIENT_ID
    
    if (-not $servicePrincipalClientId) {
        Write-Error "AZURE_CLIENT_ID environment variable not set. Ensure azure/login action has run with OIDC."
        exit 1
    }
    
    Write-Info "CI/CD mode detected - using Service Principal as SQL admin"
    
    # Get the Service Principal's Object ID from its Application (Client) ID
    $spInfo = az ad sp show --id $servicePrincipalClientId 2>$null | ConvertFrom-Json
    
    if (-not $spInfo) {
        Write-Error "Failed to retrieve Service Principal information for Client ID: $servicePrincipalClientId"
        exit 1
    }
    
    $adminObjectId = $spInfo.id
    $adminLogin = $spInfo.displayName
    $adminPrincipalType = "Application"
    
    Write-Success "Service Principal Object ID: $adminObjectId"
    Write-Success "Service Principal Name: $adminLogin"
    Write-Info "Admin Principal Type: $adminPrincipalType"
} else {
    # Local mode: Use the signed-in user
    $adminObjectId = az ad signed-in-user show --query id -o tsv
    $adminLogin = az ad signed-in-user show --query userPrincipalName -o tsv
    
    if (-not $adminObjectId -or -not $adminLogin) {
        Write-Error "Failed to get Azure AD user information"
        exit 1
    }
    
    Write-Success "Admin Object ID: $adminObjectId"
    Write-Success "Admin Login: $adminLogin"
}

# Create resource group
Write-Step "Creating resource group: $ResourceGroup"
az group create --name $ResourceGroup --location $Location --output none
Write-Success "Resource group created/verified"

# Deploy infrastructure
Write-Step "Deploying infrastructure via Bicep"
Write-Info "GenAI deployment: $(if ($DeployGenAI) { 'Enabled' } else { 'Disabled' })"

$deployGenAIValue = if ($DeployGenAI) { "true" } else { "false" }

# Get the script directory to find the Bicep file
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$bicepFile = Join-Path $scriptDir "main.bicep"

if (-not (Test-Path $bicepFile)) {
    Write-Error "Bicep file not found at: $bicepFile"
    exit 1
}

Write-Info "Deploying from: $bicepFile"
Write-Info "This may take several minutes..."

# Run deployment
az deployment group create `
    --resource-group $ResourceGroup `
    --template-file $bicepFile `
    --parameters location=$Location `
    --parameters baseName=$BaseName `
    --parameters adminObjectId=$adminObjectId `
    --parameters adminLogin=$adminLogin `
    --parameters adminPrincipalType=$adminPrincipalType `
    --parameters deployGenAI=$deployGenAIValue `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error "Infrastructure deployment failed"
    exit 1
}

Write-Success "Infrastructure deployment completed"

# Get deployment outputs
Write-Step "Retrieving deployment outputs"
$outputs = az deployment group show --resource-group $ResourceGroup --name main --query "properties.outputs" -o json | ConvertFrom-Json

$sqlServerName = $outputs.sqlServerName.value
$webAppName = $outputs.webAppName.value
$managedIdentityName = $outputs.managedIdentityName.value
$managedIdentityClientId = $outputs.managedIdentityClientId.value
$appInsightsConnectionString = $outputs.appInsightsConnectionString.value

Write-Success "SQL Server: $sqlServerName"
Write-Success "Web App: $webAppName"
Write-Success "Managed Identity: $managedIdentityName"

if ($DeployGenAI) {
    $openAIEndpoint = $outputs.openAIEndpoint.value
    $openAIModelName = $outputs.openAIModelName.value
    $searchEndpoint = $outputs.searchEndpoint.value
    Write-Success "OpenAI Endpoint: $openAIEndpoint"
    Write-Success "OpenAI Model: $openAIModelName"
    Write-Success "Search Endpoint: $searchEndpoint"
}

# Database setup
if (-not $SkipDatabaseSetup) {
    # Wait for SQL Server to be ready
    Write-Step "Waiting for SQL Server to be fully ready"
    Write-Info "Waiting 30 seconds..."
    Start-Sleep -Seconds 30
    Write-Success "Wait completed"

    # Add firewall rule for current IP
    Write-Step "Configuring SQL Server firewall"
    $myIp = (Invoke-RestMethod -Uri "https://api.ipify.org")
    Write-Info "Current IP: $myIp"

    # Check if rule already exists and delete it first to avoid errors
    $existingRule = az sql server firewall-rule show --resource-group $ResourceGroup --server $sqlServerName --name "DeploymentScript" 2>$null
    if ($existingRule) {
        az sql server firewall-rule delete --resource-group $ResourceGroup --server $sqlServerName --name "DeploymentScript" --output none
    }

    az sql server firewall-rule create `
        --resource-group $ResourceGroup `
        --server $sqlServerName `
        --name "DeploymentScript" `
        --start-ip-address $myIp `
        --end-ip-address $myIp `
        --output none

    Write-Success "Firewall rule created for $myIp"

    # Find the database schema file
    $repoRoot = Split-Path -Parent $scriptDir
    $schemaFile = Join-Path (Join-Path $repoRoot "Database-Schema") "database_schema.sql"
    $storedProcsFile = Join-Path $repoRoot "stored-procedures.sql"

    $serverFqdn = "$sqlServerName.database.windows.net"

    # Import database schema
    Write-Step "Importing database schema"
    if (-not (Test-Path $schemaFile)) {
        Write-Warning "Database schema file not found at: $schemaFile"
        Write-Warning "Skipping schema import"
    } else {
        Write-Info "Schema file: $schemaFile"
        Write-Info "Server: $serverFqdn"
        
        # Try go-sqlcmd first, fall back to legacy
        $sqlcmdPath = Get-Command sqlcmd -ErrorAction SilentlyContinue
        if ($sqlcmdPath) {
            Write-Info "Using sqlcmd..."
            # In CI/CD, use AzCli auth to leverage the az login OIDC token
            # In local mode, use ActiveDirectoryDefault which works with user credentials
            $authMethod = if ($IsCI) { "ActiveDirectoryAzCli" } else { "ActiveDirectoryDefault" }
            Write-Info "Authentication method: $authMethod"
            try {
                sqlcmd -S $serverFqdn -d "Northwind" "--authentication-method=$authMethod" -i $schemaFile
                Write-Success "Database schema imported"
            } catch {
                Write-Warning "sqlcmd failed, this might be expected if schema already exists"
                Write-Warning $_.Exception.Message
            }
        } else {
            Write-Warning "sqlcmd not found. Install with: winget install sqlcmd"
            Write-Warning "Skipping database schema import"
        }
    }

    # Configure managed identity database roles
    Write-Step "Configuring managed identity database roles"
    if ($sqlcmdPath) {
        Write-Info "Setting up database user for: $managedIdentityName"
        Write-Info "Managed Identity Client ID: $managedIdentityClientId"
        
        # In CI/CD, use AzCli auth to leverage the az login OIDC token
        $authMethod = if ($IsCI) { "ActiveDirectoryAzCli" } else { "ActiveDirectoryDefault" }
        
        # Convert the Client ID (GUID) to a SID format for SQL Server
        # This avoids needing Directory Reader permissions on the SQL Server
        # The SID is derived from the Client ID GUID bytes
        $guidBytes = [System.Guid]::Parse($managedIdentityClientId).ToByteArray()
        $sidHex = "0x" + [System.BitConverter]::ToString($guidBytes).Replace("-", "")
        
        Write-Info "Using SID-based user creation (no Directory Reader required)"
        
        try {
            # Drop user if exists, then recreate using SID
            # This approach works without requiring the SQL Server to have Directory Reader permissions
            $createUserSql = @"
IF EXISTS (SELECT * FROM sys.database_principals WHERE name = '$managedIdentityName')
    DROP USER [$managedIdentityName];

CREATE USER [$managedIdentityName] WITH SID = $sidHex, TYPE = E;

ALTER ROLE db_datareader ADD MEMBER [$managedIdentityName];
ALTER ROLE db_datawriter ADD MEMBER [$managedIdentityName];
GRANT EXECUTE TO [$managedIdentityName];
"@
            
            sqlcmd -S $serverFqdn -d "Northwind" "--authentication-method=$authMethod" -Q $createUserSql
            
            Write-Success "Managed identity database roles configured"
        } catch {
            Write-Warning "Failed to configure database roles"
            Write-Warning $_.Exception.Message
        }
    } else {
        Write-Warning "sqlcmd not found - skipping managed identity role configuration"
    }

    # Create stored procedures
    Write-Step "Creating stored procedures"
    if (-not (Test-Path $storedProcsFile)) {
        Write-Warning "Stored procedures file not found at: $storedProcsFile"
        Write-Warning "Skipping stored procedures creation"
    } elseif ($sqlcmdPath) {
        Write-Info "Stored procedures file: $storedProcsFile"
        
        # In CI/CD, use AzCli auth to leverage the az login OIDC token
        $authMethod = if ($IsCI) { "ActiveDirectoryAzCli" } else { "ActiveDirectoryDefault" }
        
        try {
            sqlcmd -S $serverFqdn -d "Northwind" "--authentication-method=$authMethod" -i $storedProcsFile
            Write-Success "Stored procedures created"
        } catch {
            Write-Warning "Failed to create stored procedures"
            Write-Warning $_.Exception.Message
        }
    } else {
        Write-Warning "sqlcmd not found - skipping stored procedures creation"
    }
} else {
    Write-Step "Skipping database setup (SkipDatabaseSetup flag set)"
}

# Configure App Service
Write-Step "Configuring App Service settings"

# Build connection string for SQL Database with Managed Identity
$sqlConnectionString = "Server=tcp:$sqlServerName.database.windows.net,1433;Initial Catalog=Northwind;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=Active Directory Managed Identity;User Id=$managedIdentityClientId;"

# Build settings array - always include connection string and client ID
$settings = @(
    "APPLICATIONINSIGHTS_CONNECTION_STRING=$appInsightsConnectionString",
    "AZURE_CLIENT_ID=$managedIdentityClientId",
    "ConnectionStrings__DefaultConnection=$sqlConnectionString"
)

if ($DeployGenAI -and $openAIEndpoint) {
    $settings += "OpenAI__Endpoint=$openAIEndpoint"
    $settings += "OpenAI__DeploymentName=$openAIModelName"
    $settings += "Search__Endpoint=$searchEndpoint"
    $settings += "ManagedIdentityClientId=$managedIdentityClientId"
}

$settingsArgs = $settings -join " "

az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $webAppName `
    --settings $settings `
    --output none

Write-Success "App Service settings configured"

# Summary
Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Resources deployed:" -ForegroundColor White
Write-Host "  Resource Group:     $ResourceGroup" -ForegroundColor Gray
Write-Host "  Web App:            $webAppName" -ForegroundColor Gray
Write-Host "  SQL Server:         $sqlServerName" -ForegroundColor Gray
Write-Host "  Managed Identity:   $managedIdentityName" -ForegroundColor Gray

if ($DeployGenAI) {
    Write-Host "  OpenAI Endpoint:    $openAIEndpoint" -ForegroundColor Gray
    Write-Host "  Search Endpoint:    $searchEndpoint" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Web App URL: https://$webAppName.azurewebsites.net" -ForegroundColor Cyan
Write-Host ""

# Save deployment context for app deployment script
$contextFile = Join-Path $repoRoot ".deployment-context.json"
$context = @{
    resourceGroup = $ResourceGroup
    webAppName = $webAppName
    sqlServerName = $sqlServerName
    sqlServerFqdn = "$sqlServerName.database.windows.net"
    managedIdentityName = $managedIdentityName
    managedIdentityClientId = $managedIdentityClientId
    deployedAt = (Get-Date).ToString("o")
}

if ($DeployGenAI) {
    $context.openAIEndpoint = $openAIEndpoint
    $context.openAIModelName = $openAIModelName
    $context.searchEndpoint = $searchEndpoint
}

$context | ConvertTo-Json | Out-File -FilePath $contextFile -Encoding utf8
Write-Host "Deployment context saved to: $contextFile" -ForegroundColor Yellow
Write-Host "Use this with deploy-app/deploy.ps1 for application deployment." -ForegroundColor Yellow
Write-Host ""

# Output deployment values for reference
Write-Host "To view all deployment outputs, run:" -ForegroundColor Yellow
Write-Host "  az deployment group show --resource-group $ResourceGroup --name main --query 'properties.outputs'" -ForegroundColor Gray
Write-Host ""
