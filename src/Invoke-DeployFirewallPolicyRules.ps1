param(
    [Parameter(Mandatory = $true)]
    $SubscriptionId,

    [Parameter(Mandatory = $true)]
    $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    $FirewallPolicyName,

    [Parameter(Mandatory = $false)]
    $PolicyCsvPath = '.\src\FirewallPolicies.csv'
)


function Get-AzureFirewallPolicyFromCsv {
    # What to do when this is not working properly?
    #  This probably means that the output format is not matching what is expected in the Bicep template. Try building a resource rule Collection bicep file and compare it with the output of this function.
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $CsvPath
    )
    $csv = Import-Csv -Path $CsvPath
    $ruleCollectionGroupNames = $csv.RuleCollectionGroup | Sort-Object | Get-Unique
    $ruleCollectionGroups = foreach ($ruleCollectionGroup in $ruleCollectionGroupNames) {
        $object = @{
            Name     = $ruleCollectionGroup
            Priority = [int]($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup } | Select-Object -First 1).RuleCollectionGroupPriority
        }
        $ruleCollectionNames = ($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup } | Group-Object -Property RuleCollectionName).Name

        [array]$object['ruleCollections'] = foreach ($ruleCollection in $ruleCollectionNames) {
            # Throw an error if rules are a mix of Network and Application Rules
            $ruleTypes = ($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup -and $_.RuleCollectionName -eq $ruleCollection } | Group-Object -Property RuleType).Name
            if ($ruleTypes.Count -gt 1) {
                throw "The rule types for $($ruleCollectionGroup) > $($ruleCollection) are mixed. This is not supported. All rules in a collection must either be Network or Application."
            }

            @{
                name               = $ruleCollection
                priority           = [int]($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup -and $_.RuleCollectionName -eq $ruleCollection } | Select-Object -First 1).RuleCollectionPriority
                ruleCollectionType = ($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup -and $_.RuleCollectionName -eq $ruleCollection } | Select-Object -First 1).RuleCollectionType
                action             = @{
                    type = ($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup -and $_.RuleCollectionName -eq $ruleCollection } | Select-Object -First 1).RuleCollectionAction
                }
                rules              = [array] $(foreach ($rule in ($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup -and $_.RuleCollectionName -eq $ruleCollection -and -Not [string]::IsNullOrEmpty($_.RuleName)})) {
                        $ruleObject = @{
                            name                  = $rule.RuleName
                            ruleType              = $rule.RuleType
                            $rule.sourceType      = $rule.Source -split ","
                            $rule.DestinationType = $rule.Destination -split ","
                        }
                        if ($rule.RuleType -eq 'ApplicationRule') {

                            if ($rule.Protocols -split ',' | Where-Object { $_ -notmatch "^(Http|Https|mssql):\d+$" }) {
                                throw "The protocol ($($rule.Protocols )) type for $($ruleCollection) > $($ruleObject.name) is not valid for Application Rules."
                            }
                            $ruleObject['protocols'] = [array] ($rule.Protocols -split "," | ForEach-Object {
                                    @{
                                        protocolType = [string] $_.split(":")[0]
                                        port         = [string] $_.split(":")[1]
                                    }
                                })
                            $ruleObject['terminateTLS'] = if ($rule.TerminateTLS -eq "True") { $true } else { $false }
                        }
                        elseif ($rule.RuleType -eq 'NetworkRule') {
                            if ($rule.Protocols -split ',' | Where-Object { $_ -notin 'TCP', 'UDP', 'ICMP', 'Any' }) {
                                throw "The protocol ($($rule.Protocols)) type for $($ruleCollection) > $($ruleObject.name) is not valid for Network Rules."
                            }
                            $ruleObject['ipProtocols'] = $rule.Protocols -split ","
                            $ruleObject['destinationPorts'] = $rule.DestinationPorts -split ","
                        }
                        else{
                            throw "The rule type $($rule.RuleType) used in $($ruleCollection) > $($ruleObject.name) is not supported. Suported types are NetworkRule and ApplicationRule."
                        }
                        $ruleObject
                    })
            }
        }
        $object
    }
    $ruleCollectionGroups
}

$timeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$deployParams = @{
    ResourceGroupName       =  $ResourceGroupName
    Name                    = "AzureFirewallPolicyUpdate-$timeStamp"
    TemplateFile            = '.\src\Firewall.bicep'
    ###
    TemplateParameterObject = @{
        FirewallPolicyName   = $FirewallPolicyName
        RuleCollectionGroups = [array](Get-AzureFirewallPolicyFromCsv -CsvPath $PolicyCsvPath)
    }
}

$null = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
New-AzResourceGroupDeployment @deployParams -Verbose

# Check if there are extra RuleCollectionGroups on Azure that are not in the CSV and delete them
$fwp = Get-AzFirewallPolicy -ResourceGroupName $deployParams.ResourceGroupName -Name $deployParams.TemplateParameterObject.FirewallPolicyName
$ruleCollectionGroupsOnAzure = $fwp.RuleCollectionGroups
$ruleCollectionGroupsInCsv = (Get-AzureFirewallPolicyFromCsv).Name
$ruleCollectionGroupsToDelete = $ruleCollectionGroupsOnAzure.Id  | Where-Object { ($_ | Split-Path -Leaf) -notin $ruleCollectionGroupsInCsv }
if ($ruleCollectionGroupsToDelete) {
    foreach ($ruleCollectionGroupToDelete in $ruleCollectionGroupsToDelete) {
        Write-PSFMessage -Level Host -Message "Deleting $($ruleCollectionGroupToDelete | Split-Path -Leaf)"
        Remove-AzFirewallPolicyRuleCollectionGroup -ResourceId $ruleCollectionGroupToDelete -Force -Confirm:$false
    }
}
