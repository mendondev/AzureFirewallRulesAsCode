param Location string = resourceGroup().location
param FirewallPolicyName string = ''
param RuleCollectionGroups array = []


module deployFirewallPolicy 'br/public:avm/res/network/firewall-policy:0.3.1' = {
  name: '${uniqueString(deployment().name, Location)}-firewallPolicy'
  params: {
    name: FirewallPolicyName
    location: Location
    tier: 'Standard'
    threatIntelMode: 'Deny'
    ruleCollectionGroups: [for item in RuleCollectionGroups: {
      name: item.Name
      priority: item.Priority
      ruleCollections: item.RuleCollections
    }]
    enableProxy: true
  }
}

// If using the Basic SKU, please replace with the following Version.
// module deployFirewallPolicy 'br/public:avm/res/network/firewall-policy:0.3.1' = {
//   name: '${uniqueString(deployment().name, Location)}-firewallPolicy'
//   params: {
//     name: FirewallPolicyName
//     location: Location
//     tier: 'Basic'
//     threatIntelMode: 'Alert'
//     ruleCollectionGroups: [for item in RuleCollectionGroups: {
//       name: item.Name
//       priority: item.Priority
//       ruleCollections: item.RuleCollections
//     }]
//     enableProxy: false
//   }
// }
