param location string
param prefix string
param tags object
param vaultId string
param vaultName string
param vmSubnetId string
param vmVnetId string

// Vault-specific zone: linked ONLY to the existing VM VNet. The VM therefore resolves the vault
// to the endpoint in its own subnet, while the shared privatelink.vaultcore.azure.net zone
// (workspace/transit VNets) keeps pointing at the workspace-VNet endpoint. The longest matching
// zone name wins, so there is no multi-IP record and no peering dependency.
var zoneName = '${vaultName}.privatelink.vaultcore.azure.net'

resource zone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: zone
  name: 'link-vm'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vmVnetId
    }
  }
}

// Endpoint resource and its NIC are created in the PoC resource group; only the private IP
// allocation comes from the existing VM subnet.
resource pe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${prefix}-vault-vm'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vmSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'vault-vm'
        properties: {
          privateLinkServiceId: vaultId
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource record 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: zone
  name: '@'
  properties: {
    ttl: 10
    aRecords: [
      {
        ipv4Address: pe.properties.customDnsConfigs[0].ipAddresses[0]
      }
    ]
  }
}

output peName string = pe.name
output zoneName string = zone.name
