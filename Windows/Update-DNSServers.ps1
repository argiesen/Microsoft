# WinRM must be enabled for workstations: https://woshub.com/enable-winrm-management-gpo/

$UpdateDNS = $false
$rootOU = "OU=Servers,OU=vmwdojo,DC=vmwdojo,DC=com"
$Computers = Get-ADComputer -SearchBase $rootOU -Filter '(OperatingSystem -like "Windows Server*")' | Sort-Object Name
$Output = @()

# Iterate through servers
ForEach ($Computer in $Computers){
	Write-Host "$($Computer.Name): Processing" -ForegroundColor Yellow
    $Error.Clear()

    # Connect to server
    $result = Invoke-Command -ComputerName $Computer.Name -ErrorAction SilentlyContinue -ScriptBlock {
        $entry = "" | Select-Object Computer,DNSServersBefore,DNSServersAfter,Status
        
        # Collect DNS servers before update
        $Adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.DHCPEnabled -ne 'True' -and $_.DNSServerSearchOrder -ne $null}
        $entry.DNSServersBefore = $Adapters.DNSServerSearchOrder
        
        # Update DNS servers
        if ($UpdateDNS){
            $NewDnsServerSearchOrder = "10.75.0.119","10.85.0.139"
            $Adapters | ForEach-Object {$_.SetDNSServerSearchOrder($NewDnsServerSearchOrder)} | Out-Null
            Start-Sleep -s 3
            Register-DnsClient

            # Collect DNS servers after update
            $Adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.DHCPEnabled -ne 'True' -and $_.DNSServerSearchOrder -ne $null}
            $entry.DNSServersAfter = $Adapters.DNSServerSearchOrder
        }

        return $entry
    }
    
    # If invoke-command errors write error to status
    if ($Error){
        if (!$result.DNSServersBefore){
            $result = "" | Select-Object @{l='Computer';e={$Computer.Name}},DNSServersBefore,DNSServersAfter,Status
        }
        $result.Status = "$($error[0].Exception.TransportMessage)"
        Write-Host "$($Computer.Name): $($error[0].Exception.TransportMessage)" -ForegroundColor Red
    }
    $Output += $result | Select-Object @{l='Computer';e={$Computer.Name}},DNSServersBefore,DNSServersAfter,Status
}

$Output
