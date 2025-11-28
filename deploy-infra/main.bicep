@description('Location for all resources')
param location string = 'uksouth'

@description('Base name for resources')
param baseName string = 'expensemgmt'

@description('The Object ID of the Azure AD administrator for SQL')
param adminObjectId string

@description('The login name (UPN) of the Azure AD administrator for SQL')
param adminLogin string

@description('Whether to deploy GenAI resources')
param deployGenAI bool = false

// Deploy Managed Identity first
module managedIdentity 'modules/managed-identity.bicep' = {
  name: 'managedIdentityDeployment'
  params: {
    location: location
    baseName: baseName
  }
}

// Deploy App Service
module appService 'modules/app-service.bicep' = {
  name: 'appServiceDeployment'
  params: {
    location: location
    baseName: baseName
    managedIdentityId: managedIdentity.outputs.managedIdentityId
    managedIdentityClientId: managedIdentity.outputs.managedIdentityClientId
  }
}

// Deploy Azure SQL
module azureSQL 'modules/azure-sql.bicep' = {
  name: 'azureSQLDeployment'
  params: {
    location: location
    baseName: baseName
    adminObjectId: adminObjectId
    adminLogin: adminLogin
    managedIdentityPrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
  }
}

// Conditionally deploy GenAI resources
module genAI 'modules/genai.bicep' = if (deployGenAI) {
  name: 'genAIDeployment'
  params: {
    baseName: baseName
    managedIdentityPrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
  }
}

// Deploy Monitoring resources (Azure Monitor, Log Analytics, Application Insights)
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoringDeployment'
  params: {
    location: location
    baseName: baseName
    appServiceId: appService.outputs.webAppId
    sqlServerId: azureSQL.outputs.sqlServerId
    sqlDatabaseId: azureSQL.outputs.sqlDatabaseId
  }
}

// Outputs
@description('The name of the web app')
output webAppName string = appService.outputs.webAppName

@description('The hostname of the web app')
output webAppHostName string = appService.outputs.webAppHostName

@description('The SQL server name')
output sqlServerName string = azureSQL.outputs.sqlServerName

@description('The SQL server FQDN')
output sqlServerFqdn string = azureSQL.outputs.sqlServerFqdn

@description('The database name')
output databaseName string = azureSQL.outputs.databaseName

@description('The managed identity name')
output managedIdentityName string = managedIdentity.outputs.managedIdentityName

@description('The managed identity client ID')
output managedIdentityClientId string = managedIdentity.outputs.managedIdentityClientId

@description('The managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.outputs.managedIdentityPrincipalId

// GenAI outputs (conditional)
@description('The Azure OpenAI endpoint')
output openAIEndpoint string = deployGenAI ? genAI.outputs.openAIEndpoint : ''

@description('The Azure OpenAI model deployment name')
output openAIModelName string = deployGenAI ? genAI.outputs.openAIModelName : ''

@description('The Azure AI Search endpoint')
output searchEndpoint string = deployGenAI ? genAI.outputs.searchEndpoint : ''

// Monitoring outputs
@description('The Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId

@description('The Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = monitoring.outputs.logAnalyticsWorkspaceName

@description('The Application Insights ID')
output appInsightsId string = monitoring.outputs.appInsightsId

@description('The Application Insights name')
output appInsightsName string = monitoring.outputs.appInsightsName

@description('The Application Insights instrumentation key')
output appInsightsInstrumentationKey string = monitoring.outputs.appInsightsInstrumentationKey

@description('The Application Insights connection string')
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
