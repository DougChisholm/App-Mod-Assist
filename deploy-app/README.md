# Application Deployment

This folder contains the deployment instructions for the Expense Management application code.

## Prerequisites

1. Infrastructure must already be deployed (see `deploy-infra/README.md`)
2. Azure CLI installed and logged in (`az login`)
3. The web app name from the infrastructure deployment

## Application URL

After deployment, the application is available at:
- **Main UI**: `https://<your-web-app-name>.azurewebsites.net/Index`
- **Swagger API**: `https://<your-web-app-name>.azurewebsites.net/swagger`

> **Note**: Navigate to `/Index` to view the application, not just the root URL.

## Deployment Steps

### Step 1: Set PowerShell Variables

```powershell
$resourceGroup = "rg-expensemgmt-demo"
$webAppName = "app-expensemgmt-UNIQUE"  # Get this from infrastructure deployment output
```

### Step 2: Build and Publish the Application

```powershell
cd src/ExpenseManagement
dotnet publish -c Release -o ./publish
```

### Step 3: Create the Deployment Zip

```powershell
# Remove old zip if exists
Remove-Item -Force ./app.zip -ErrorAction SilentlyContinue

# Create zip from publish folder contents (not the folder itself)
Compress-Archive -Path ./publish/* -DestinationPath ./app.zip
```

**Important**: The zip file must contain the DLL files at the root level, not in a subdirectory.

### Step 4: Deploy to Azure

```powershell
az webapp deploy --resource-group $resourceGroup --name $webAppName --src-path ./app.zip --type zip --clean true --restart true
```

> **Note**: The `--clean true` flag removes old files, and `--restart true` ensures the app restarts after deployment.

### Step 5: Configure App Settings (if not done during infrastructure deployment)

```powershell
# Get the managed identity client ID and SQL server name from infrastructure deployment
$managedIdentityClientId = "YOUR_MANAGED_IDENTITY_CLIENT_ID"
$sqlServerFqdn = "sql-expensemgmt-UNIQUE.database.windows.net"

az webapp config appsettings set `
    --resource-group $resourceGroup `
    --name $webAppName `
    --settings "AZURE_CLIENT_ID=$managedIdentityClientId" `
               "ConnectionStrings__DefaultConnection=Server=tcp:$sqlServerFqdn,1433;Initial Catalog=Northwind;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=Active Directory Managed Identity;User Id=$managedIdentityClientId;"
```

## Local Development

To run the application locally:

1. Update `appsettings.Development.json` with your server details
2. Ensure you're logged in with `az login`
3. Run the application:

```powershell
cd src/ExpenseManagement
dotnet run
```

The local connection string uses `Authentication=Active Directory Default` which will use your Azure CLI credentials.

## Verify Deployment

After deployment, verify by:

1. Navigate to `https://<your-web-app-name>.azurewebsites.net/Index`
2. Check the Swagger UI at `https://<your-web-app-name>.azurewebsites.net/swagger`
3. Test the API endpoints
