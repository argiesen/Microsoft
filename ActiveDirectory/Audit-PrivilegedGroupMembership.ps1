# Author: Andy Giesen
# 04/22/2023
# Generates a list of members of each privileged AD group and, for a different perspective on the same information, a list of users with the privileged groups they are assigned to 

# All AD privileged groups
# https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices/appendix-b--privileged-accounts-and-groups-in-active-directory
$PrivilegedGroups = 
"ADSyncAdmins",
"ADSyncOperators",
"ADSyncBrowse",
"ADSyncPasswordSet",
"Domain Controllers",
"Schema Admins",
"Enterprise Admins",
"Cert Publishers",
"Domain Admins",
"Group Policy Creator Owners",
"RAS and IAS Servers",
"Allowed RODC Password Replication Group",
"Denied RODC Password Replication Group",
"Read-only Domain Controllers",
"Enterprise Read-only Domain Controllers",
"Cloneable Domain Controllers",
"Protected Users",
"Key Admins",
"Enterprise Key Admins",
"DnsAdmins",
"DnsUpdateProxy",
"DHCP Users",
"DHCP Administrators",
"Server Operators",
"Account Operators",
"Pre-Windows 2000 Compatible Access",
"Incoming Forest Trust Builders",
"Windows Authorization Access Group",
"Terminal Server License Servers",
"Administrators",
"Print Operators",
"Backup Operators",
"Replicator",
"Remote Desktop Users",
"Network Configuration Operators",
"Performance Monitor Users",
"Performance Log Users",
"Distributed COM Users",
"IIS_IUSRS",
"Cryptographic Operators",
"Event Log Readers",
"Certificate Service DCOM Access",
"RDS Remote Access Servers",
"RDS Endpoint Servers",
"RDS Management Servers",
"Hyper-V Administrators",
"Access Control Assistance Operators",
"Remote Management Users",
"Storage Replica Administrators"

$GroupMembershipResults = @()

# Process all privileged groups and recursively enumerate members
foreach ($group in $PrivilegedGroups){
    try{
        $GroupMembershipResults += Get-ADGroupMember -Identity $group -Recursive | Select-Object @{l='Group';e={$group}},Name,SamAccountName,DistinguishedName,ObjectClass,ObjectGuid
    }catch{
        Write-Host $error.Exception[0] -ForegroundColor Red
    }
}

# Export group focused membership to CSV
$GroupMembershipResults | Export-Csv -NoTypeInformation GroupMembership.csv

# Export user focused membership to CSV
$UserMembershipResults = $GroupMembershipResults | Group-Object -Property DistinguishedName | ForEach-Object {$_ | Select-Object Name,@{l='Groups';e={$_.Group.Group -join ','}}}
$UserMembershipResults | Export-Csv -NoTypeInformation UserMembership.csv
