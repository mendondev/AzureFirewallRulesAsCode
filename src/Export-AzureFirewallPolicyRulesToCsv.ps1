param (
    [Parameter(Mandatory = $true)]
    $FirewallPolicyId,

    [Parameter(Mandatory = $false)]
    $OutputCSVPath = '.\src\FirewallPolicies.csv'
)

$fwp = Get-AzFirewallPolicy -ResourceId $FirewallPolicyId

$ruleCollectionGroups = $fwp.RuleCollectionGroups.Id | ForEach-Object { Get-AzFirewallPolicyRuleCollectionGroup -Name (($_ -split "/")[-1])-AzureFirewallPolicy $fwp }

$policySummary = foreach ($group in $ruleCollectionGroups) {
    foreach ($ruleCollection in $group.Properties.RuleCollection) {
        foreach ($rule in $ruleCollection.Rules) {
            #SourceType
            $rulePossibleSourceTypes = @( 'SourceAddresses', 'SourceIpGroups' )
            $ruleSourceType = $rulePossibleSourceTypes | ForEach-Object { if ($rule.$_) { $_ } }

            #Destination

            #protocols for rule types
            switch ($rule.RuleType) {
                "ApplicationRule" {
                    $ruleProtocols = ($rule.protocols | ForEach-Object { "{0}:{1}" -f $_.ProtocolType, $_.Port }) -join ","
                    $rulePossibleDestinations = @( 'TargetFqdns', 'FqdnTags', 'WebCategories', 'TargetUrls' )

                }
                "NetworkRule" {
                    $ruleProtocols = $rule.Protocols -join ","
                    $rulePossibleDestinations = @( 'DestinationAddresses', 'DestinationFqdns', 'DestinationIpGroups')
                }
            }
            $ruleDestinationType = $rulePossibleDestinations | ForEach-Object { if ($rule.$_) { $_ } }
            [PSCustomObject]@{
                RuleCollectionGroup         = $group.Name
                RuleCollectionGroupPriority = $group.Properties.Priority
                RuleCollectionName          = $ruleCollection.Name
                RuleCollectionPriority      = $ruleCollection.Priority
                RuleCollectionAction        = $ruleCollection.Action.Type
                RuleCollectionType          = $ruleCollection.RuleCollectionType
                RuleType                    = $rule.RuleType
                RuleName                    = $rule.Name
                SourceType                  = $ruleSourceType
                Source                      = $rule.$ruleSourceType -join ","
                Protocols                   = $ruleProtocols
                TerminateTLS                = $rule.TerminateTLS
                DestinationPorts            = $rule.DestinationPorts -join ","
                DestinationType             = $ruleDestinationType
                Destination                 = $rule.$ruleDestinationType -join ","
            }
        }
    }
}

# $policySummary | ConvertTo-Csv | Out-String | Set-Clipboard

$policySummary | Export-Csv -Path $OutputCSVPath
