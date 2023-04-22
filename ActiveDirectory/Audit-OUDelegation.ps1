# Author: Andy Giesen
# 04/22/2023
# Generates a list of all top level (non-inherited) permissions delegated to OUs

$OUDelegationResults = @()

# Get all AD OUs
$OUs = Get-ADOrganizationalUnit -Filter *

# Process each OU and gather all non-inherited access list permissions
foreach($OU in $OUs){
    $OUDelegationResults += (Get-Acl -Path $("AD:\" + $OU.DistinguishedName)).Access | Where-Object IsInherited -eq $false | `
    Select-Object @{l='OU';e={$OU.DistinguishedName}},IdentityReference,ActiveDirectoryRights,AccessControlType
}

# Export to CSV
$OUDelegationResults | Export-Csv -NoTypeInformation OUDelegation.csv
