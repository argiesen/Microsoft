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
function Invoke-WindowsUpdates {
	if (!($UpdateSession)){
		$UpdateSession = New-Object -ComObject 'Microsoft.Update.Session'
		$UpdateSession.ClientApplicationID = 'Packer Windows Update Installer'
		$UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
		$SearchResult = New-Object -ComObject 'Microsoft.Update.UpdateColl'
	}

	#Checking WU for available updates
	Write-Log "Checking for Windows Updates..."
	Write-Log
	$UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
	$SearchResult = $UpdateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
	
	if ($SearchResult.Updates.Count -ne 0){
		#List raw update output for debugging
		#$SearchResult.Updates | Select-Object -Property Title, Description, SupportUrl, UninstallationNotes, RebootRequired, EulaAccepted | Format-List
		
		$resultcode = @{0="Not Started"; 1="In Progress"; 2="Succeeded"; 3="Succeeded With Errors"; 4="Failed"; 5="Aborted"}
	
		#Checking available updates for applicable updates
		Write-Log "Evaluating $($SearchResult.Updates.Count) available updates:"
		$UpdatesToDownload = New-Object -ComObject 'Microsoft.Update.UpdateColl'
		foreach ($Update in $SearchResult.Updates) {
			if (($Update -ne $null) -and (!$Update.IsDownloaded)){
				if ($Update.InstallationBehavior.CanRequestUserInput){
					Write-Log "> Skipping: $($Update.Title) because it requires user input"
				}else{
					if (!($Update.EulaAccepted)){
						Write-Log "> Note: $($Update.Title) has a license agreement that must be accepted. Accepting the license."
						$Update.AcceptEula()
					}
					Write-Log "Adding: $($Update.Title)"
					$UpdatesToDownload.Add($Update) | Out-Null
				}
			}
		}
		Write-Log
		
		#Checking if updates are already downloaded, if not download
		if ($UpdatesToDownload.Count -ne 0){
			Write-Log "Downloading $($UpdatesToDownload.Count) updates..."
			$Downloader = $UpdateSession.CreateUpdateDownloader()
			$Downloader.Updates = $UpdatesToDownload
			$Downloader.Download() | Out-Null
		}else{
			Write-Log "No updates to download"
		}
		Write-Log
		
		#Determine which downloaded updates to install
		if (($SearchResult.Updates | Where-Object {$_.IsDownloaded -eq $true}).Count -ne 0){
			$UpdatesToInstall = New-Object -ComObject 'Microsoft.Update.UpdateColl'
			Write-Log "The following updates are downloaded and ready to be installed:"
			foreach ($Update in $SearchResult.Updates){
				if (($Update.IsDownloaded)){
					Write-Log "> $($Update.Title)"
					$UpdatesToInstall.Add($Update) | Out-Null
				}
			}
			Write-Log
			
			if (($UpdatesToInstall | Select-Object -ExpandProperty InstallationBehavior) | Where-Object {$_.RebootBehavior -gt 0}){
				Write-Log "These updates may require a reboot"
				Write-Log
			}
		}
		
		#Install downloaded updates
		if ($UpdatesToInstall.Count -ne 0){
			Write-Log "Installing updates..."
			Write-Log
			
			$Installer = $UpdateSession.CreateUpdateInstaller()
			$Installer.Updates = $UpdatesToInstall
			$InstallationResult = $Installer.Install()
			
			#Display results
			Write-Log "Listing of updates installed and individual installation results:"
			for($i=0; $i -lt $UpdatesToInstall.Count; $i++){
				Write-Log "$($resultcode[$InstallationResult.GetUpdateResult($i).ResultCode]): $($UpdatesToInstall.Item($i).Title)"
			}
			Write-Log
			
			Write-Log "Installation Result: $($resultcode[$InstallationResult.ResultCode])"
			Write-Log "Reboot Required: $($InstallationResult.RebootRequired)"
			Write-Log
			
			#Reboot if needed, otherwise check for additional updates
			if ($InstallationResult.RebootRequired){
				Write-Log "Rebooting"
				Write-Log
				Restart-Computer -Force
				exit
			}else{
				Write-Log "No restart required"
				Write-Log
				Invoke-WindowsUpdates
			}
		}else{
			#If no updates available, drop from function
			Write-Log "There are no applicable updates. Windows Updates complete"
			Write-Log
			return
		}
	}else{
		Write-Log "There are no applicable updates. Windows Updates complete"
		Write-Log
		return
	}
}

$LogPath = "C:\$($env:ComputerName)-$(Get-Date -f yyyyMMdd).log"

if (!(Get-ScheduledTask "WindowsUpdates" -ErrorAction SilentlyContinue)){
	$arg = "-File `"$($MyInvocation.MyCommand.Path)`""
	Manage-ScheduledTask -TaskName "WindowsUpdates" -Action "Add" -StartupType AtStartup -Execute powershell -Argument $arg -User "SYSTEM"
	Write-Log
}

Invoke-WindowsUpdates

Manage-ScheduledTask -TaskName "WindowsUpdates" -Action "Remove"