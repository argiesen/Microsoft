function Install-SQLInstance {
	param (
		[ValidateNotNullOrEmpty()]
		[string]$Instance,
		[ValidateNotNullOrEmpty()]
		[string]$SQLPath = "$env:ProgramFiles\Microsoft SQL Server",
		[ValidateNotNullOrEmpty()]
		[string]$SQLMediaDir,
		[ValidateNotNullOrEmpty()]
		[string]$SQLConfigPath,
		[switch]$OpenPorts
	)
	
	if (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL" -Name "$Instance" -ErrorAction SilentlyContinue){
		Write-Log "SQL Express 2014 ($Instance) already installed" -Indent $Indent -OutTo $LogOutTo
		return
	}
	
	if (!(Test-Path $SQLMediaDir\SQLEXPR_x64_ENU)){
		Write-Log "$SQLMediaDir\SQLEXPR_x64_ENU does not exist." -Indent $Indent -Level "Error" -OutTo $LogOutTo
		return
	}
	
	#Configure SQL parameters
	$Config = "/ACTION=`"Install`"", `
			  "/QUIET=`"True`"", `
			  "/IACCEPTSQLSERVERLICENSETERMS=`"True`"", `
			  "/FEATURES=SQLENGINE,Tools", `
			  "/INSTALLSHAREDDIR=`"$SQLPath`"", `
			  "/INSTANCEDIR=`"$SQLPath`"", `
			  "/INSTANCENAME=`"$Instance`"", `
			  "/INSTANCEID=`"$Instance`"", `
			  "/SQLSYSADMINACCOUNTS=`"BUILTIN\ADMINISTRATORS`"", `
			  "/ADDCURRENTUSERASSQLADMIN=`"True`"", `
			  "/BROWSERSVCSTARTUPTYPE=`"Automatic`"", `
			  "/AGTSVCACCOUNT=`"NT AUTHORITY\NETWORK SERVICE`"", `
			  "/AGTSVCSTARTUPTYPE=`"Automatic`"", `
			  "/SQLSVCACCOUNT=`"NT AUTHORITY\NETWORK SERVICE`"", `
			  "/SQLSVCSTARTUPTYPE=`"Automatic`"", `
			  "/TCPENABLED=`"1`""
	
	$process = Start-Process -FilePath "$SQLMediaDir\SQLEXPR_x64_ENU\Setup.exe" -ArgumentList $Config -Wait -Passthru -Verb RunAs
	if ($process.ExitCode -ne 0 -and !(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL" -Name "$Instance" -ErrorAction SilentlyContinue)){
		Write-Log "SQLEXPR_x64_ENU.exe ($Instance) returned error code: $($process.ExitCode)" -Level "Error" -OutTo $LogOutTo
		if ($process.ExitMessage){
			Write-Log "SQLEXPR_x64_ENU.exe ($Instance) returned exit message: $($process.ExitMessage)" -Level "Error" -OutTo $LogOutTo
		}
		return
	}
	
	if ($OpenPorts){
		if (!(Get-NetFirewallRule -DisplayName "SQL Database Engine ($Instance)" -ErrorAction SilentlyContinue)){
			Write-Log "Creating firewall rule for SQL Database Engine ($Instance)." -Indent $Indent -OutTo $LogOutTo
			$path = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$Instance\Setup" | Select-Object -ExpandProperty SQLPath
			New-NetFirewallRule -DisplayName "SQL Database Engine ($Instance)" -Direction Inbound -Action Allow -Profile Any -Program $path\Binn\sqlservr.exe | Out-Null
		}
	}
}

function Write-Log {
	param(
		[string]$Message,
		[ValidateSet("File", "Screen", "FileAndScreen")]
		[string]$OutTo = "FileAndScreen",
		[ValidateSet("Info", "Warn", "Error", "Verb", "Debug")]
		[string]$Level = "Info",
		[ValidateSet("Black", "DarkMagenta", "DarkRed", "DarkBlue", "DarkGreen", "DarkCyan", "DarkYellow", "Red", "Blue", "Green", "Cyan", "Magenta", "Yellow", "DarkGray", "Gray", "White")]
		[String]$ForegroundColor = "White",
		[ValidateRange(1,30)]
		[int]$Indent = 0,
		[switch]$Clobber,
		[switch]$NoNewLine
	)
	
	if (!($LogPath)){
		$LogPath = "$($env:ComputerName)-$(Get-Date -f yyyyMMdd).log"
	}
	
	$msg = "{0} : {1} : {2}{3}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level.ToUpper(), ("  " * $Indent), $Message
	if ($OutTo -match "File"){
		if (($Level -ne "Verb") -or ($VerbosePreference -eq "Continue")){
			if ($Clobber){
				$msg | Out-File $LogPath -Force
			}else{
				$msg | Out-File $LogPath -Append
			}
		}
	}
	
	$msg = "{0}{1}" -f ("  " * $Indent), $Message
	if ($OutTo -match "Screen"){
		switch ($Level){
			"Info" {
				if ($NoNewLine){
					Write-Host $msg -ForegroundColor $ForegroundColor -NoNewLine
				}else{
					Write-Host $msg -ForegroundColor $ForegroundColor
				}
			}
			"Warn" {Write-Warning $msg}
			"Error" {$host.ui.WriteErrorLine($msg)}
			"Verb" {Write-Verbose $msg}
			"Debug" {Write-Debug $msg}
		}
	}
}

$InstallDrive = "C:"
$SoftwareDir = "C:\software"
$Indent = 1
$UserTempDir = [environment]::GetEnvironmentVariable("temp","user")
$LogPath = "C:\software\InstallSQL.txt"

Write-Log "Extracting SQL Express 2014"
$Process = Start-Process -FilePath "$SoftwareDir\SQLEXPR_x64_ENU.exe" -ArgumentList /q, /x:"$UserTempDir\SQLEXPR_x64_ENU" -Wait -Passthru -Verb RunAs
if ($process.ExitCode -ne 0){throw "$SoftwareDir\SQLEXPR_x64_ENU.exe /x: returned error code: $($process.ExitCode)"}

#Write-Log "Installing RTC" -OutTo $LogOutTo
Install-CsSQLInstance -Instance RTC -SQLMediaDir $UserTempDir -SQLPath "$InstallDrive\Program Files\Microsoft SQL Server" -OpenPorts | Out-Null