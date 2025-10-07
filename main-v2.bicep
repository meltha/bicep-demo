@description('Location for all resources')
param location string = resourceGroup().location

@description('Object ID of the user running the deployment (for Key Vault break-glass).')
param deployerObjectId string

@description('Environment tag')
@allowed([ 'dev', 'test', 'prod' ])
param environment string = 'dev'

@description('Short base name (letters/numbers). Used to build resource names.')
param baseName string = 'playground'

@description('Optional salt to create a distinct stack when you actually want another copy. Leave empty for stable names.')
param nameSalt string = ''

//
// Common computed values (safe unique suffix so names don’t collide)
//
var hash = uniqueString(subscription().id, resourceGroup().name, baseName, environment, nameSalt)
var short = take(hash, 8)

//
// Standard tags applied to all resources
//
var commonTags = {
  env: environment
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
var kvName = toLower('kv${take(baseName, 10)}${short}')

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: commonTags
  properties: {
    enableRbacAuthorization: false
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    softDeleteRetentionInDays: 7
    accessPolicies: [
      // You (break-glass)
      {
        tenantId: subscription().tenantId
        objectId: deployerObjectId
        permissions: { secrets: [ 'get', 'list', 'set', 'delete', 'purge' ] }
      }
    ]
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
var planName = '${take(baseName, 10)}-plan-${short}'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: commonTags
  sku: { name: 'B1', tier: 'Basic', size: 'B1', family: 'B', capacity: 1 }
  properties: {
    reserved: true // Linux plan
  }
}

//
// ===== Web App (Linux, System-Assigned Identity) =====
//
var webAppName = toLower('${take(baseName, 10)}-web-${short}')

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
      appSettings: [
        {
          name: 'STORAGE_CONN'
          value: '@Microsoft.KeyVault(SecretUri=${kv.properties.vaultUri}secrets/storage-conn)'
        }
      ]
    }
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
          secrets: [ 'get', 'list' ]
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