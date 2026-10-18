param location string
param prefix string
param tags object
param workspaceVnetCidr string
param transitVnetCidr string

var delegation = [
  {
    name: 'databricks'
    properties: {
      serviceName: 'Microsoft.Databricks/workspaces'
    }
  }
]

// Databricks-delegated subnets require an attached NSG. Once the workspace exists, Databricks attaches
// network intent policies that REQUIRE these outbound rules; omitting them makes any redeployment fail
// with ConflictWithNetworkIntentPolicy. They are the documented worker-to-SQL/Storage/EventHub rules.
var intentRules = [
  {
    name: 'databricks-worker-to-sql'
    properties: {
      priority: 100
      direction: 'Outbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: 'VirtualNetwork'
      sourcePortRange: '*'
      destinationAddressPrefix: 'Sql'
      destinationPortRange: '3306'
    }
  }
  {
    name: 'databricks-worker-to-storage'
    properties: {
      priority: 101
      direction: 'Outbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: 'VirtualNetwork'
      sourcePortRange: '*'
      destinationAddressPrefix: 'Storage'
      destinationPortRange: '443'
    }
  }
  {
    name: 'databricks-worker-to-eventhub'
    properties: {
      priority: 102
      direction: 'Outbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: 'VirtualNetwork'
      sourcePortRange: '*'
      destinationAddressPrefix: 'EventHub'
      destinationPortRange: '9093'
    }
  }
]

resource workspaceNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${prefix}-ws'
  location: location
  tags: tags
  properties: {
    securityRules: intentRules
  }
}

resource authNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${prefix}-auth'
  location: location
  tags: tags
  properties: {
    securityRules: intentRules
  }
}

// Explicit outbound-only egress for classic compute (new VNets have no default outbound access).
resource natIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${prefix}-nat'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nat 'Microsoft.Network/natGateways@2023-11-01' = {
  name: 'nat-${prefix}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: natIp.id
      }
    ]
  }
}

resource workspaceVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${prefix}-ws'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        workspaceVnetCidr
      ]
    }
    subnets: [
      {
        name: 'snet-host'
        properties: {
          addressPrefix: cidrSubnet(workspaceVnetCidr, 26, 0)
          networkSecurityGroup: {
            id: workspaceNsg.id
          }
          natGateway: {
            id: nat.id
          }
          delegations: delegation
        }
      }
      {
        name: 'snet-container'
        properties: {
          addressPrefix: cidrSubnet(workspaceVnetCidr, 26, 1)
          networkSecurityGroup: {
            id: workspaceNsg.id
          }
          natGateway: {
            id: nat.id
          }
          delegations: delegation
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: cidrSubnet(workspaceVnetCidr, 27, 4)
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource transitVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${prefix}-transit'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        transitVnetCidr
      ]
    }
    subnets: [
      {
        name: 'snet-auth-host'
        properties: {
          addressPrefix: cidrSubnet(transitVnetCidr, 27, 0)
          networkSecurityGroup: {
            id: authNsg.id
          }
          delegations: delegation
        }
      }
      {
        name: 'snet-auth-container'
        properties: {
          addressPrefix: cidrSubnet(transitVnetCidr, 27, 1)
          networkSecurityGroup: {
            id: authNsg.id
          }
          delegations: delegation
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: cidrSubnet(transitVnetCidr, 26, 1)
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

output workspaceVnetId string = workspaceVnet.id
output workspaceVnetName string = workspaceVnet.name
output transitVnetId string = transitVnet.id
output transitVnetName string = transitVnet.name
output workspaceHostSubnetName string = 'snet-host'
output workspaceContainerSubnetName string = 'snet-container'
output authHostSubnetName string = 'snet-auth-host'
output authContainerSubnetName string = 'snet-auth-container'
output workspacePeSubnetId string = '${workspaceVnet.id}/subnets/snet-pe'
output transitPeSubnetId string = '${transitVnet.id}/subnets/snet-pe'
