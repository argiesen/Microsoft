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

function Manage-ScheduledTask {
	param (
		[parameter(Mandatory = $true, HelpMessage = "No task name specified")]
		[ValidateNotNullOrEmpty()]
		[string]$TaskName,
		[ValidateSet("Add", "Remove")]
		[string]$Action,
		[string]$Execute,
		[string]$Argument,
		[ValidateSet("AtStartup", "AtLogon", "OnDemand", "Scheduled")]
		[string]$StartupType,
		[ValidateSet("Once", "Daily", "Weekly")]
		[string]$Recurrence,
		[string]$Time,
		[array]$DaysOfWeek,
		[string]$User,
		[string]$Password,
		[PSCredential]$Credential
	)
	
	if (Get-ScheduledTask $TaskName -ErrorAction SilentlyContinue){
		if ($Action -eq "Add"){
			return "$TaskName already exists."
		}
	}else{
		if ($Action -eq "Remove"){
			return "$TaskName does not exist"
		}
	}
	
	$error.Clear()
	if ($Action -eq "Add"){
		$Script:TaskAction = New-ScheduledTaskAction -Execute $Execute -Argument $Argument
		if ($StartupType -eq "OnDemand"){
			$schedTask = New-ScheduledTask -Action $Script:TaskAction
		}elseif ($StartupType -eq "AtStartup"){
			$Script:TaskTrigger = New-ScheduledTaskTrigger -AtStartup
			$schedTask = New-ScheduledTask -Action $Script:TaskAction -Trigger $Script:TaskTrigger
		}elseif ($StartupType -eq "AtLogon"){
			$Script:TaskTrigger = New-ScheduledTaskTrigger -AtLogon
			$schedTask = New-ScheduledTask -Action $Script:TaskAction -Trigger $Script:TaskTrigger
		}elseif ($StartupType -eq "Scheduled"){
			if ($Recurrence -eq "Once"){
				$Script:TaskTrigger = New-ScheduledTaskTrigger -At $Time -Once
			}elseif ($Recurrence -eq "Daily"){
				$Script:TaskTrigger = New-ScheduledTaskTrigger -At $Time -Daily
			}elseif ($Recurrence -eq "Weekly"){
				$Script:TaskTrigger = New-ScheduledTaskTrigger -At $Time -Weekly -DaysOfWeek $DaysOfWeek
			}
			$schedTask = New-ScheduledTask -Action $Script:TaskAction -Trigger $Script:TaskTrigger
		}
		
		if ($Credential){
			Register-ScheduledTask $TaskName -InputObject $schedTask -User $Credential.Username -Password $Credential.GetNetworkCredential().Password | Out-Null
		}elseif ($Password){
			Register-ScheduledTask $TaskName -InputObject $schedTask -User $User -Password $Password | Out-Null
		}else{
			Register-ScheduledTask $TaskName -InputObject $schedTask -User $User | Out-Null
		}
		
		if ($error){
			return "Failed to register $TaskName."
		}else{
			return "Successfully registered $TaskName."
		}
	}
	
	$error.Clear()
	if ($Action -eq "Remove"){
		Unregister-ScheduledTask $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
		
		if ($error){
			return "Failed to unregister $TaskName."
		}else{
			return "Successfully unregistered $TaskName."
		}
	}
}

#Windows Updates functions
function Check-WindowsUpdates() {
	Write-Log "Checking for Windows Updates..."
	Write-Log
	$script:UpdateSearcher = $script:UpdateSession.CreateUpdateSearcher()
	$script:SearchResult = $script:UpdateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
	if ($SearchResult.Updates.Count -ne 0){
		$script:SearchResult.Updates | Select-Object -Property Title, Description, SupportUrl, UninstallationNotes, RebootRequired, EulaAccepted | Format-List
		$global:MoreUpdates = 1
	}else{
		Write-Log "There are no applicable updates"
		$global:RestartRequired = 0
		$global:MoreUpdates = 0
	}
}

function Install-WindowsUpdates(){
	$script:Cycles++
	$resultcode= @{0="Not Started"; 1="In Progress"; 2="Succeeded"; 3="Succeeded With Errors"; 4="Failed"; 5="Aborted"}
	
	Write-Log "Evaluating Available Updates:"
	$UpdatesToDownload = New-Object -ComObject 'Microsoft.Update.UpdateColl'
	foreach ($Update in $SearchResult.Updates) {
		if (($Update -ne $null) -and (!$Update.IsDownloaded)){
			[bool]$addThisUpdate = $false
			if ($Update.InstallationBehavior.CanRequestUserInput){
				Write-Log "> Skipping: $($Update.Title) because it requires user input"
			}else{
				if (!($Update.EulaAccepted)){
					Write-Log "> Note: $($Update.Title) has a license agreement that must be accepted. Accepting the license."
					$Update.AcceptEula()
					[bool]$addThisUpdate = $true
				} else {
					[bool]$addThisUpdate = $true
				}
			}
			
			if ([bool]$addThisUpdate){
				Write-Log "Adding: $($Update.Title)"
				$UpdatesToDownload.Add($Update) | Out-Null
			}
		}
	}
	Write-Log
	
	if ($UpdatesToDownload.Count -eq 0){
		Write-Log "No updates to download..."
	}else{
		Write-Log "Downloading updates..."
		$Downloader = $UpdateSession.CreateUpdateDownloader()
		$Downloader.Updates = $UpdatesToDownload
		$Downloader.Download() | Out-Null
	}
	Write-Log
	
	$UpdatesToInstall = New-Object -ComObject 'Microsoft.Update.UpdateColl'
	[bool]$rebootMayBeRequired = $false
	Write-Log "The following updates are downloaded and ready to be installed:"
	foreach ($Update in $SearchResult.Updates){
		if (($Update.IsDownloaded)){
			Write-Log "> $($Update.Title)"
			$UpdatesToInstall.Add($Update) |Out-Null
			
			if ($Update.InstallationBehavior.RebootBehavior -gt 0){
				[bool]$rebootMayBeRequired = $true
			}
		}
	}
	Write-Log
	
	if ($UpdatesToInstall.Count -eq 0){
		Write-Log "No updates available to install..."
		$global:MoreUpdates = 0
		$global:RestartRequired = 0
		break
	}
	
	if ($rebootMayBeRequired) {
		Write-Log "These updates may require a reboot"
		$global:RestartRequired = 1
	}
	Write-Log
	
	Write-Log "Installing updates..."
	Write-Log
	
	$Installer = $script:UpdateSession.CreateUpdateInstaller()
	$Installer.Updates = $UpdatesToInstall
	$InstallationResult = $Installer.Install()
	
	Write-Log "Listing of updates installed and individual installation results:"
	if ($InstallationResult.RebootRequired){
		$global:RestartRequired = 1
	}else{
		$global:RestartRequired = 0
	}
	
	$UpdateResults = @()
	for($i=0; $i -lt $UpdatesToInstall.Count; $i++){
		$UpdateResult = "" | Select-Object Title,Result
		$UpdateResult.Title = $UpdatesToInstall.Item($i).Title
		$UpdateResult.Result = $resultcode[$InstallationResult.GetUpdateResult($i).ResultCode]
		$UpdateResults += $UpdateResult
	}
	foreach ($result in $UpdateResults){
		Write-Log "$($result.Result): $($result.Title)"
	}
	
	Write-Log
	Write-Log "Installation Result: $($resultcode[$InstallationResult.ResultCode])"
	Write-Log "Reboot Required: $($InstallationResult.RebootRequired)"
	
	Check-ContinueRestartOrEnd
}

function Check-ContinueRestartOrEnd(){
	switch ($global:RestartRequired){
		0 {
			<# if (Get-ScheduledTask "WindowsUpdates" -ErrorAction SilentlyContinue){
				Manage-ScheduledTask -TaskName "WindowsUpdates" -Action "Remove"
			} #>
			
			Write-Log
			Write-Log "No restart required"
			Write-Log
			Check-WindowsUpdates
			
			if (($global:MoreUpdates -eq 1) -and ($script:Cycles -le $global:MaxCycles)){
				Install-WindowsUpdates
			} elseif ($script:Cycles -gt $global:MaxCycles){
				Write-Log "Exceeded cycle count - Stopping"
			}else{
				Write-Log "Done installing Windows Updates"     
			}
		}
		1 {
			<# if (!(Get-ScheduledTask "WindowsUpdates" -ErrorAction SilentlyContinue)){
				$arg = '-File "'+$($script:ScriptPath)+'"'
				Manage-ScheduledTask -TaskName "WindowsUpdates" -Action "Add" -StartupType AtStartup -Execute powershell -Argument $arg -User "SYSTEM"
			} #>
			
			#Toggle-ScheduledTask -TaskName "CSDeploymentReboot" -Action "Enable" | Write-Log -Level "Verb" -OutTo $LogOutTo
			
			Write-Log
			Write-Log "Restart required"
			Write-Log "Rebooting"
			Write-Log
			Restart-Computer -Force
			exit
		}
		default {
			Write-Log
			Write-Log "Unsure if a restart is required" 
			break
		}
	}
}

$LogPath = "C:\cerium\$($env:ComputerName)-$(Get-Date -f yyyyMMdd).log"

$global:MoreUpdates = 0
$global:MaxCycles = 10

#$script:ScriptName = $MyInvocation.MyCommand.ToString()
#$script:ScriptPath = $MyInvocation.MyCommand.Path
$script:UpdateSession = New-Object -ComObject 'Microsoft.Update.Session'
$script:UpdateSession.ClientApplicationID = 'Packer Windows Update Installer'
$script:UpdateSearcher = $script:UpdateSession.CreateUpdateSearcher()
$script:SearchResult = New-Object -ComObject 'Microsoft.Update.UpdateColl'
$script:Cycles = 0

if (!(Get-ScheduledTask "WindowsUpdates" -ErrorAction SilentlyContinue)){
	$arg = "-File `"$($MyInvocation.MyCommand.Path)`""
	Manage-ScheduledTask -TaskName "WindowsUpdates" -Action "Add" -StartupType AtStartup -Execute powershell -Argument $arg -User "SYSTEM"
}

Check-WindowsUpdates
if ($global:MoreUpdates -eq 1){
	Install-WindowsUpdates
}else{
	Check-ContinueRestartOrEnd
}

Manage-ScheduledTask -TaskName "WindowsUpdates" -Action "Remove"