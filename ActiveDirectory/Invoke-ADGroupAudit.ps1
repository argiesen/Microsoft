[cmdletbinding()]
param (
	[parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
	[string]$OutFile = "ADGroups.csv",
	[parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
	[string]$SearchBase
)

if (!($SearchBase)){
	$SearchBase = (Get-ADDomain).DistinguishedName
}

$AdGroups = Get-ADGroup -Filter * -SearchBase $SearchBase `
	| Select-Object Name,GroupCategory,GroupScope,DistinguishedName,ObjectGUID,DirectUsers,DirectCount,IndirectUsers,IndirectCount,MemberGroups

foreach ($AdGroup in $AdGroups){
	$directGroupMembership = Get-ADGroupMember -Identity $AdGroup.DistinguishedName
	$indirectGroupMembership = Get-ADGroupMember -Identity $AdGroup.DistinguishedName -Recursive
	$AdGroup.DirectUsers = ($directGroupMembership | Where-Object ObjectClass -eq user).DistinguishedName
	$AdGroup.IndirectUsers = ($indirectGroupMembership | Where-Object ObjectClass -eq user).DistinguishedName
	$AdGroup.MemberGroups = ($directGroupMembership | Where-Object ObjectClass -eq group).DistinguishedName -join ";"
	
	$compare = $null
	try {
		$compare = Compare-Object -ReferenceObject $AdGroup.DirectUsers -DifferenceObject $AdGroup.IndirectUsers -PassThru
	}catch{
		#Discard errors
	}
	
	$AdGroup.DirectCount = ($AdGroup.DirectUsers).Count
	$AdGroup.DirectUsers = $AdGroup.DirectUsers -join ";"
	$AdGroup.IndirectCount = $compare.Count
	$AdGroup.IndirectUsers = $compare -join ";"
}

$AdGroups | Sort-Object Name | Export-Csv $OutFile -NoTypeInformation