// ===== Parameters =====
@description('Object ID of the user running the deployment (for Key Vault access policy).')
param deployerObjectId string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Storage account name (must be globally unique; lower-case + digits).')
param storageAccountName string = 'st${uniqueString(resourceGroup().id)}'

@description('Key Vault name (must be globally unique).')
param keyVaultName string = 'kv${uniqueString(resourceGroup().id, deployment().name)}'


// ===== Storage Account =====
resource stg 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

// Get storage keys to build a connection string
var stgKeys = listKeys(stg.id, '2023-01-01')
var stgKey  = stgKeys.keys[0].value
var connStr = 'DefaultEndpointsProtocol=https;AccountName=${stg.name};AccountKey=${stgKey};EndpointSuffix=${environment().suffixes.storage}'

// ===== Key Vault (access policy model) =====
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enabledForTemplateDeployment: true

    // Access policy so the deploying user can set/list secrets
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: deployerObjectId
        permissions: {
          secrets: [
            'get'
            'list'
            'set'
            'delete'
          ]
        }
      }
    ]
  }
}

// ===== Secret: store the storage connection string =====
resource kvSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: '${kv.name}/storage-conn'
  properties: {
    value: connStr
  }
  dependsOn: [
    stg
    kv
  ]
}

// ===== App Service Plan (Basic B1) =====
resource appPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: 'playground-plan'
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    capacity: 1
  }
  properties: {
    reserved: false
  }
}

// ===== Web App (System-assigned Managed Identity) =====
resource appService 'Microsoft.Web/sites@2022-09-01' = {
  name: 'playground-webapp-${uniqueString(resourceGroup().id)}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appPlan.id
    httpsOnly: true
  }
}

// ===== Give Web App identity access to Key Vault =====
resource kvAccessForApp 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  name: '${kv.name}/add'
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: appService.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
  dependsOn: [
    kv
    appService
  ]
}



// ===== Web App: App Settings (Key Vault reference) =====
resource appSettings 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appService
  name: 'appsettings'
  properties: {
    // Key Vault reference to the secret (no version is fine; it uses latest)
    STORAGE_CONN: '@Microsoft.KeyVault(SecretUri=https://${kv.name}.vault.azure.net/secrets/storage-conn)'
  }
  dependsOn: [
    kvAccessForApp
  ]
}

// ===== Outputs =====
output storageAccountName string = stg.name
output keyVaultName string = kv.name
output keyVaultUri string = kv.properties.vaultUri
output webAppName string = appService.name
output webAppUrl string = 'https://${appService.name}.azurewebsites.net'
