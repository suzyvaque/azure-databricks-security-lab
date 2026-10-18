param location string
param prefix string
param tags object
param workspaceId string
param authWorkspaceId string
param vaultId string
param workspacePeSubnetId string
param transitPeSubnetId string
param workspaceVnetId string
param transitVnetId string

resource dbxZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azuredatabricks.net'
  location: 'global'
  tags: tags
}

resource kvZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource dbxLinkWorkspace 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dbxZone
  name: 'link-ws'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: workspaceVnetId
    }
  }
}

resource dbxLinkTransit 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dbxZone
  name: 'link-transit'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: transitVnetId
    }
  }
}

resource kvLinkTransit 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: kvZone
  name: 'link-transit'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: transitVnetId
    }
  }
}

resource kvLinkWorkspace 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: kvZone
  name: 'link-ws'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: workspaceVnetId
    }
  }
}

// One databricks_ui_api endpoint serves both front-end and back-end roles.
resource peUiApi 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${prefix}-uiapi'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: workspacePeSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'uiapi'
        properties: {
          privateLinkServiceId: workspaceId
          groupIds: [
            'databricks_ui_api'
          ]
        }
      }
    ]
  }
  dependsOn: [
    dbxLinkWorkspace
  ]
}

resource peUiApiDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: peUiApi
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'dbx'
        properties: {
          privateDnsZoneId: dbxZone.id
        }
      }
    ]
  }
}

resource peAuth 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${prefix}-auth'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: transitPeSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'auth'
        properties: {
          privateLinkServiceId: authWorkspaceId
          groupIds: [
            'browser_authentication'
          ]
        }
      }
    ]
  }
  dependsOn: [
    dbxLinkTransit
  ]
}

// Serialized after the UI/API zone group to avoid concurrent writes to the same zone.
resource peAuthDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: peAuth
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'dbx'
        properties: {
          privateDnsZoneId: dbxZone.id
        }
      }
    ]
  }
  dependsOn: [
    peUiApiDns
  ]
}

// Vault PE lives in the workspace VNet so classic compute and the (peered) VM both reach it privately.
resource peVault 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${prefix}-vault'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: workspacePeSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'vault'
        properties: {
          privateLinkServiceId: vaultId
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
  dependsOn: [
    kvLinkTransit
    kvLinkWorkspace
  ]
}

resource peVaultDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: peVault
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'kv'
        properties: {
          privateDnsZoneId: kvZone.id
        }
      }
    ]
  }
}
