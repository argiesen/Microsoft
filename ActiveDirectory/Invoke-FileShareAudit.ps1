[cmdletbinding()]
param (
	[parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
	[string]$OutFile = "Shares.csv",
	[parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
	[string]$SearchBase
)

#Set SearchBase
if (!($SearchBase)){
	$SearchBase = (Get-ADDomain).DistinguishedName
}

#Get Windows Servers that are enabled
$Servers = Get-ADComputer -Filter "(operatingSystem -like 'Windows Server*') -and (Enabled -eq 'True')" -SearchBase $SearchBase `
	| Select-Object DNSHostName,Name,DistinguishedName,ObjectGUID,@{l='Online';e={$null}}

#Test connectivity to servers for remote PowerShell commands (TCP/5985)
foreach ($Server in $Servers){
	if ((Test-NetConnection $Server.DNSHostName -Port 5985 -InformationLevel Quiet)) {
		$Server.Online = $true
	}else{
		$Server.Online = $false
	}
}

#Query servers for shares and set permissions
$Shares = Invoke-Command -ComputerName ($Servers | Where-Object Online -eq $true).DNSHostName -ScriptBlock {
		Get-SmbShare | Tee-Object -Variable shareOut | Get-SmbShareAccess | Select-Object Name,@{l='Path';e={($shareOut | Where-Object Name -eq $_.Name).Path}}, `
		@{l='Description';e={($shareOut | Where-Object Name -eq $_.Name).Description}},ScopeName,AccountName,AccessControlType,AccessRight
	} | Select-Object @{l='ComputerName';e={$_.PSComputerName}},Name,Path,Description,ScopeName,AccountName,AccessControlType,AccessRight

#Export to CSV
$Shares | Export-Csv $OutFile -NoTypeInformation

