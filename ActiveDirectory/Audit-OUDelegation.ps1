# Author: Andy Giesen
# 04/22/2023
# Generates a list of all top level (non-inherited) permissions delegated to OUs
# https://devblogs.microsoft.com/powershell-community/understanding-get-acl-and-ad-drive-output/

# Hash table for SID lookup
$SIDHash = @{
	"S-1-0" = "Null Authority" 
	"S-1-0-0" = "Nobody"
	"S-1-1" ="World Authority"
	"S-1-1-0" = "Everyone"
	"S-1-2" = "Local Authority"
	"S-1-2-0" = "Local"
	"S-1-2-1" = "Console Logon"
	"S-1-3" = "Creator Authority"
	"S-1-3-0" = "Creator Owner"
	"S-1-3-1" = "Creator Group"
	"S-1-3-4" = "Owner Rights"
	"S-1-5-80-0" ="All Services"
	"S-1-4" = "Non Unique Authority"
	"S-1-5" = "NT Authority"
	"S-1-5-1" = "Dialup"
	"S-1-5-2" = "Network"
	"S-1-5-3" = "Batch"
	"S-1-5-4" = "Interactive"
	"S-1-5-6" = "Service"
	"S-1-5-7" = "Anonymous"
	"S-1-5-9" = "Enterprise Domain Controllers"
	"S-1-5-10" = "Self"
	"S-1-5-11" = "Authenticated Users"
	"S-1-5-12" = "Restricted Code"
	"S-1-5-13" = "Terminal Server Users"
	"S-1-5-14" = "Remote Interactive Logon"
	"S-1-5-15" = "This Organization"
	"S-1-5-17" = "This Organization"
	"S-1-5-18" = "Local System"
	"S-1-5-19" = "NT Authority Local Service"
	"S-1-5-20" = "NT Authority Network Service"
	"S-1-5-32-544" = "Administrators"
	"S-1-5-32-545" = "Users"
	"S-1-5-32-546" = "Guests"
	"S-1-5-32-547" = "Power Users"
	"S-1-5-32-548" = "Account Operators"
	"S-1-5-32-549" = "Server Operators"
	"S-1-5-32-550" = "Print Operators"
	"S-1-5-32-551" = "Backup Operators"
	"S-1-5-32-552" = "Replicators"
	"S-1-5-32-554" = "Pre-Windows 2000 Compatibility Access"
	"S-1-5-32-555" = "Remote Desktop Users"
	"S-1-5-32-556" = "Network Configuration Operators"
	"S-1-5-32-557" = "Incoming forest trust builders"
	"S-1-5-32-558" = "Performance Monitor Users"
	"S-1-5-32-559" = "Performance Log Users"
	"S-1-5-32-560" = "Windows Authorization Access Group"
	"S-1-5-32-561" = "Terminal Server License Servers"
	"S-1-5-32-562" = "Distributed COM Users"
	"S-1-5-32-569" = "Cryptographic Operators"
	"S-1-5-32-573" = "Event Log Readers"
	"S-1-5-32-574" = "Certificate Services DCOM Access"
	"S-1-5-32-575" = "RDS Remote Access Servers"
	"S-1-5-32-576" = "RDS Endpoint Servers"
	"S-1-5-32-577" = "RDS Management Servers"
	"S-1-5-32-578" = "Hyper-V Administrators"
	"S-1-5-32-579" = "Access Control Assistance Operators"
	"S-1-5-32-580" = "Remote Management Users"
}

# Gather ObjectTypes from AD into hash table for lookup
$ObjectTypeGUID = @{}

$GetADObjectParameter = @{
    SearchBase = (Get-ADRootDSE).SchemaNamingContext
    LDAPFilter = '(SchemaIDGUID=*)'
    Properties = @("Name", "SchemaIDGUID")
}

$SchGUID = Get-ADObject @GetADObjectParameter
foreach($SchemaItem in $SchGUID){
    $ObjectTypeGUID.Add([GUID]$SchemaItem.SchemaIDGUID,$SchemaItem.Name)
}

$ADObjExtPar=@{
    SearchBase = "CN=Extended-Rights,$((Get-ADRootDSE).ConfigurationNamingContext)"
    LDAPFilter = '(ObjectClass=ControlAccessRight)'
    Properties = @("Name", "RightsGUID")
}

$SchExtGUID = Get-ADObject @ADObjExtPar
foreach($SchExtItem in $SchExtGUID){
    $ObjectTypeGUID.Add([GUID]$SchExtItem.RightsGUID,$SchExtItem.Name)
}

# Get all AD OUs
$OUs = Get-ADOrganizationalUnit -Filter *

# Gather permissions from OUs
$OUDelegationResults = @()

# Process each OU and gather all non-inherited access list permissions
foreach($OU in $OUs){
    $OUDelegationResults += (Get-Acl -Path $("AD:\" + $OU.DistinguishedName)).Access | `
        Where-Object IsInherited -eq $false | Where-Object IdentityReference -notmatch "^NT AUTHORITY\\|^Everyone$" | `
        Select-Object @{l='OU';e={$OU.DistinguishedName}},`
        @{l='IdentityReference';e={if ($SIDHash.Keys -contains $_.IdentityReference){$SIDHash[$_.IdentityReference.Value]}else{$_.IdentityReference}}},`
        ActiveDirectoryRights,AccessControlType,InheritanceType,`
        @{l='ObjectType';e={if ($_.ObjectType -eq "00000000-0000-0000-0000-000000000000"){"All Properties"}else{$ObjectTypeGUID[$_.ObjectType]}}},`
        @{l='InheritedObjectType';e={if ($_.InheritedObjectType -eq "00000000-0000-0000-0000-000000000000"){"All Objects"}else{$ObjectTypeGUID[$_.InheritedObjectType]}}},`
        InheritanceFlags,PropagationFlags
}

# Export to CSV
$OUDelegationResults | Export-Csv -NoTypeInformation "OUDelegation-$(Get-Date -Format yyyMMdd.HHmm).csv"
