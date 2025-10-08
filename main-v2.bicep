@description('Location for all resources')
param location string = resourceGroup().location

@description('Object ID of the user running the deployment (for Key Vault break-glass).')
param deployerObjectId string = ''


@description('Short base name (letters/numbers). Used to build resource names.')
param baseName string = 'playground'

@description('Optional salt to create a distinct stack when you actually want another copy. Leave empty for stable names.')
param nameSalt string = ''

@allowed([ 'dev', 'test', 'prod' ])
@description('Target environment')
param env string = 'dev'

@description('Name of EXISTING Application Insights instance for this env')
param appInsightsName string

@description('Resource ID of EXISTING Log Analytics Workspace linked to this env\'s App Insights')
param logAnalyticsWorkspaceId string

//
// Common computed values (safe unique suffix so names don’t collide)
//
var hash = uniqueString(subscription().id, resourceGroup().name, baseName, env, nameSalt)
var short = take(hash, 8)

//
// Standard tags applied to all resources
//
var commonTags = {
  env: env
  owner: 'mentor-demo'
  costCenter: 'lab'
}

//
// ===== Storage Account =====
//
var stgName = toLower('st${take(baseName, 10)}${short}')

resource stg 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: stgName
  location: location
  tags: commonTags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

// Use the listKeys() function (not a resource) to fetch an access key
var stgKeys = listKeys(stg.id, '2023-04-01')

// Build a classic connection string (use Azure Public cloud suffix)
var stgConn = 'DefaultEndpointsProtocol=https;AccountName=${stg.name};AccountKey=${stgKeys.keys[0].value};EndpointSuffix=core.windows.net'

//
// ===== Key Vault =====
//
var kvName = toLower('kv${take(baseName, 10)}${short}${env}')

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: commonTags
  properties: {
    enableRbacAuthorization: false
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    softDeleteRetentionInDays: 7
    accessPolicies: length(deployerObjectId) > 0 ? [
      {
        tenantId: subscription().tenantId
        objectId: deployerObjectId
        permissions: {
          secrets: [
            'get'
            'list'
            'set'
            'delete'
            'purge'
          ]
        }
      }
    ] : []
  }
}

resource kvSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'storage-conn'
  properties: {
    value: stgConn
  }
}

//
// ===== App Service Plan (Linux B1) =====
//
var planName = '${take(baseName, 10)}-plan-${env}-${short}'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: commonTags
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    family: 'B'
    capacity: 1
  }
  properties: {
    reserved: true // Linux plan
  }
}

//
// ===== Web App (Linux, System-Assigned Identity) =====
//
var webAppName = toLower('${take(baseName, 10)}-web-${env}-${short}')

// Existing Application Insights (referenced, not created)
resource ai 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      alwaysOn: true
      healthCheckPath: '/health'
      appSettings: [
        {
          name: 'STORAGE_CONN'
          value: '@Microsoft.KeyVault(SecretUri=${kv.properties.vaultUri}/secrets/storage-conn)'
        }
        {
          name: 'APPINSIGHTS_CONNECTIONSTRING'
          value: ai.properties.ConnectionString
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: env
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
  }
}

resource appDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-law'
  scope: app
  properties: {
    workspaceId: logAnalyticsWorkspaceId
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

//
// ===== Grant the Web App MI access to Key Vault secrets =====
//
resource kvAccessForApp 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: kv
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: app.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}

//
// ===== Outputs =====
//
output storageAccountName string = stg.name
output keyVaultName string = kv.name
output keyVaultUri string = kv.properties.vaultUri
output webAppName string = app.name
output webAppUrl string = 'https://${app.name}.azurewebsites.net'
output appInsightsNameOut string = ai.name
output logAnalyticsWorkspaceIdOut string = logAnalyticsWorkspaceId