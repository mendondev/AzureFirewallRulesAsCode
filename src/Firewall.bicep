param Location string = resourceGroup().location
param FirewallPolicyName string
param RuleCollectionGroups array = []

module deployFirewallPolicy 'CARML/0.9.0/modules/Microsoft.Network/firewallPolicies/deploy.bicep' = {
  name: 'deployFirewallPolicy'
  params: {
    name: FirewallPolicyName
    location: Location
    tier: 'Premium'
    threatIntelMode: 'Alert'
    ruleCollectionGroups: [for item in RuleCollectionGroups: {
      name: item.Name
      priority: item.Priority
      ruleCollections: item.RuleCollections
    }]
    enableProxy: true
  }
}
