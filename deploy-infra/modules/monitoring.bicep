@description('Location for the monitoring resources')
param location string = resourceGroup().location

@description('Base name for the monitoring resources')
param baseName string

@description('Resource ID of the App Service to monitor')
param appServiceId string

@description('Resource ID of the SQL Server to monitor')
param sqlServerId string

@description('Resource ID of the SQL Database to monitor')
param sqlDatabaseId string

// Create unique but deterministic names using resource group id
var uniqueSuffix = uniqueString(resourceGroup().id)
var logAnalyticsWorkspaceName = toLower('log-${baseName}-${uniqueSuffix}')
var appInsightsName = toLower('appi-${baseName}-${uniqueSuffix}')

// Extract resource names from IDs
var appServiceName = last(split(appServiceId, '/'))
var sqlServerName = split(sqlServerId, '/')[8]
var sqlDatabaseName = last(split(sqlDatabaseId, '/'))

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Reference existing App Service
resource existingAppService 'Microsoft.Web/sites@2023-01-01' existing = {
  name: appServiceName
}

// Diagnostic settings for App Service
resource appServiceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'appservice-to-log-analytics'
  scope: existingAppService
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServiceAuditLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Reference existing SQL Server
resource existingSqlServer 'Microsoft.Sql/servers@2023-05-01-preview' existing = {
  name: sqlServerName
}

// Diagnostic settings for SQL Server
resource sqlServerDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sqlserver-to-log-analytics'
  scope: existingSqlServer
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
      }
      {
        category: 'DevOpsOperationsAudit'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Reference existing SQL Database
resource existingSqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' existing = {
  parent: existingSqlServer
  name: sqlDatabaseName
}

// Diagnostic settings for SQL Database
resource sqlDatabaseDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sqldatabase-to-log-analytics'
  scope: existingSqlDatabase
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'SQLInsights'
        enabled: true
      }
      {
        category: 'AutomaticTuning'
        enabled: true
      }
      {
        category: 'QueryStoreRuntimeStatistics'
        enabled: true
      }
      {
        category: 'QueryStoreWaitStatistics'
        enabled: true
      }
      {
        category: 'Errors'
        enabled: true
      }
      {
        category: 'DatabaseWaitStatistics'
        enabled: true
      }
      {
        category: 'Timeouts'
        enabled: true
      }
      {
        category: 'Blocks'
        enabled: true
      }
      {
        category: 'Deadlocks'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Basic'
        enabled: true
      }
      {
        category: 'InstanceAndAppAdvanced'
        enabled: true
      }
      {
        category: 'WorkloadManagement'
        enabled: true
      }
    ]
  }
}

@description('The resource ID of the Log Analytics Workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The name of the Log Analytics Workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The resource ID of Application Insights')
output appInsightsId string = appInsights.id

@description('The name of Application Insights')
output appInsightsName string = appInsights.name

@description('The instrumentation key of Application Insights')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('The connection string of Application Insights')
output appInsightsConnectionString string = appInsights.properties.ConnectionString
