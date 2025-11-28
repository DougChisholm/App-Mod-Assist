@description('Location for the SQL Server')
param location string = resourceGroup().location

@description('Base name for the SQL resources')
param baseName string

@description('The Object ID of the Azure AD administrator')
param adminObjectId string

@description('The login name (UPN) of the Azure AD administrator')
param adminLogin string

@description('Principal ID of the managed identity for database access')
param managedIdentityPrincipalId string

// Create unique but deterministic names using resource group id
var uniqueSuffix = uniqueString(resourceGroup().id)
var sqlServerName = toLower('sql-${baseName}-${uniqueSuffix}')
var databaseName = 'Northwind'

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: adminLogin
      principalType: 'User'
      sid: adminObjectId
      tenantId: subscription().tenantId
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Allow Azure services to access the server
resource firewallRuleAzure 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
  }
}

@description('The name of the SQL Server')
output sqlServerName string = sqlServer.name

@description('The fully qualified domain name of the SQL Server')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('The name of the database')
output databaseName string = sqlDatabase.name

@description('The resource ID of the SQL Server')
output sqlServerId string = sqlServer.id

@description('The resource ID of the SQL Database')
output sqlDatabaseId string = sqlDatabase.id
