<#
	.SYNOPSIS
		Set default Lockscreen to a FinalScreen at end of device setup phase for Autopilot SelfDeploying mode.
		Autopilot Supported mode: This script is supported on Shared Kiosk devices with SelfDeploying mode only.

	.DESCRIPTION
		The script is designed to run in 2 phases:
		- During Autopilot SelfDeploying device setup phase:
			- copy source files (including this script) and create a Windows scheduled task with specific triggers and create a flg file for intune detection.
		- Next phase is based on scheduled task triggers: 
			- At next execution of the task, it will check Autopilot Device ESP status: 
				- if succeeded, it set a final screen as default lockscreen, remove scheduled task, before rebooting device, it prepares another task to run only at logon to remove the final screen.
				- if autopilot device setup phase not completed yet, the script will exit and will re-run next time based on scheduled task triggers.
	
	.EXAMPLE
		powershell.exe -executionpolicy Bypass -file .\SetFinalScreen.ps1
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.249
		Created on:   	14.10.2024 - version 1.0.1
		Created by:   	Amar_Maouche - Dell Deployment Engineer
		Organization: 	Dell Inc.
		Filename:     	setFinalScreen.ps1
		===========================================================================
#>

[cmdletbinding()]
Param ()

# If we are running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64")
{
	if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe")
	{
		& "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy bypass -File "$PSCommandPath"
		Exit $lastexitcode
	}
}

# set appname and scriptname
$appName = "FinalScreen"
$scriptName = ($MyInvocation.MyCommand.Name)

# log folder and file
$logName = $($((Split-Path $MyInvocation.MyCommand.Definition -leaf)).replace("ps1", "log"))
$logPath = "$($env:ProgramData)\Microsoft\IntuneManagementExtension\Logs"
$logFile = "$logPath\$logName"
$flagFile = $($((Split-Path $MyInvocation.MyCommand.Definition -leaf)).replace("ps1", "flg"))

# set cache folder used to host this script and other source files: required for 2nd phase of script execution 
$cacheFolder = "$($env:ProgramData)\Microsoft\$appName"

# set success final lock screen variable
$successLockscreenFile = "GreenLockscreen.jpg"

# Windows Scheduled task name: DO NOT CHANGE NAME as used by the script: removalfinalscreen.ps1
$taskName = "setFinalScreen"

# task Folder name:  DO NOT CHANGE FOLDER PATH NAME as used by the script: removalfinalscreen.ps1
$taskPath = '\Microsoft'

# task Action command
$taskCommand = "$($env:WinDir)\System32\WindowsPowerShell\v1.0\powershell.exe"

# task script full path to be executed
$taskScript = "$cacheFolder\$scriptName"

# task Action command argument
$taskArg = "-ExecutionPolicy Bypass -File $taskScript"

# RepetitionInterval: time in minutes between each restart of the task. The task will run, wait for the time interval specified, and then run again
$taskRepetitionInterval = "2"
$taskRepetitionInterval = [int]$taskRepetitionInterval

# Wait Time in seconds before Reboot once Device setup completed
$waitTimeBeforeReboot = "10"
$waitTimeBeforeReboot = [int]$waitTimeBeforeReboot

# Function to enable logging
Function Write-Log
{
	Param (
		[Parameter(
				   Mandatory = $true,
				   Position = 0
				   )]
		[string]$Message,
		[Parameter(
				   Mandatory = $false,
				   Position = 1
				   )]
		[validateset('Information', 'Warning', 'Error')]
		[string]$Class = "Information"
	)
	
	$global:ScriptLogFilePath = $LogFile
	$LogString = "$(Get-Date) $Class  -  $Message"
	$HostString = "$(Get-Date) $Class  -  $Message"
	
	Add-Content -Path $ScriptLogFilePath -Value $LogString
	switch ($Class)
	{
		'Information' {
			Write-host $HostString -ForegroundColor Gray
		}
		'Warning' {
			Write-host $HostString -ForegroundColor Yellow
		}
		'Error' {
			Write-host $HostString -ForegroundColor Red
		}
		Default { }
	}
	
}

# Function to check Device ESP status
Function getDeviceESPStatus
{
	# Autopilot Device ESP status from registry
	[string]$AutoPilotSettingsKey = 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings'
	[string]$DevicePrepName = 'DevicePreparationCategory.Status'
	[string]$DeviceSetupName = 'DeviceSetupCategory.Status'
	
	$DevicePrepDetails = (Get-ItemProperty -Path $AutoPilotSettingsKey -Name $DevicePrepName -ErrorAction 'Ignore').$DevicePrepName
	$DeviceSetupDetails = (Get-ItemProperty -Path $AutoPilotSettingsKey -Name $DeviceSetupName -ErrorAction 'Ignore').$DeviceSetupName
	
	if (-not [string]::IsNullOrEmpty($DevicePrepDetails))
	{
		$DevicePrepDetails = $DevicePrepDetails | ConvertFrom-Json
	}
	if (-not [string]::IsNullOrEmpty($DeviceSetupDetails))
	{
		$DeviceSetupDetails = $DeviceSetupDetails | ConvertFrom-Json
	}
	
	# get device prep status
	$DevicePrepStatus = $DevicePrepDetails.categoryState
	
	# get device setup status
	$DeviceSetupStatus = $DeviceSetupDetails.categoryState
	
	# set DeviceESP status
	switch ($DevicePrepStatus)
	{
		'notStarted' { $DeviceESPStatus = 'notStarted' }
		'succeeded' {
			switch ($DeviceSetupStatus)
			{
				'notStarted' { $DeviceESPStatus = 'inProgress' }
				'inProgress' { $DeviceESPStatus = 'inProgress' }
				'succeeded' { $DeviceESPStatus = 'succeeded' }
				'failed' { $DeviceESPStatus = 'failed' }
			}
		}
		'inProgress' { $DeviceESPStatus = 'inProgress' }
		'failed' { $DeviceESPStatus = 'failed' }
	}
	return $DeviceESPStatus
}

## Function to set LockScreen
Function setLockScreen ($myfile)
{
	$LockScreenImage = "$cacheFolder\$myfile"
	$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
	$backupRegFile = "BakupPersonalizationCSP.reg"
	
	# Create Registry Key if not exist
	Write-Log "Checking registry key $RegPath ..."
	
	if (-not (Test-Path -Path $RegPath))
	{
		write-Log "Presence of '$($RegPath)' key was not detected, attempting to create it"
		New-Item -Path $RegPath -Force | Out-Null
	}
	else
	{
		# save existing configuration to be re-applied later on
		write-Log "Presence of existing '$($RegPath)' key detected. Backup existing settings"
		reg export $RegPath "$cacheFolder\$backupRegFile"
	}
	
	# Apply Lockscreen Registry Keys
	Write-Log "Applying Final success Lockscreen Registry Keys"
	New-ItemProperty -Path $RegPath -Name LockScreenImagePath -Value $LockScreenImage -PropertyType String -Force | Out-Null
	New-ItemProperty -Path $RegPath -Name LockScreenImageUrl -Value $LockScreenImage -PropertyType String -Force | Out-Null
	New-ItemProperty -Path $RegPath -Name LockScreenImageStatus -Value 1 -PropertyType DWORD -Force | Out-Null
	sleep 3
}

## Function to test if a registry value exists
Function Test-RegistryKeyValue
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]# The path to the registry key where the value should be set.  Will be created if it doesn't exist.
        				$Path,
		[Parameter(Mandatory = $true)]
		[string]# The name of the value being set.
        				$Name
	)
	if (-not (Test-Path -Path $Path -PathType Container)) { return $false }
	$properties = Get-ItemProperty -Path $Path
	if (-not $properties) { return $false }
	$member = Get-Member -InputObject $properties -Name $Name
	if ($member)
	{
		return $true
	}
	else
	{
		return $false
	}
}

# initialization
if (-not (Test-Path $cacheFolder)) { mkdir $cacheFolder }

Write-Log "Starting script execution ..."

# pausing for couple of seconds
Sleep 10

# get current user
$details = Get-ComputerInfo
$username = $details.CsUserName

if ($username -match "defaultUser")
{
	# Script execution at default user session
	Write-Log "Running at default user session."
	
	# Check for Task Named as $taskName variable value if already scheduled
	$existingTask = Get-ScheduledTask -TaskName "$taskName" -ErrorAction SilentlyContinue
	if ($existingTask -ne $null)
	{
		Write-Log "Scheduled task $taskName already exists."
		Write-Log "Script execution will re-run at next reboot or at repetition interval of scheduled task."
		Exit 0
	}
	else
	{
		# Copy required files to $cacheFolder directory, for later use
		    if (-not (Test-Path "$cacheFolder\$scriptName"))
		    {
			    Write-Log "copy source files to $cacheFolder directory, for later use."
			    Copy-Item -Path $PSScriptRoot\* -Destination $cacheFolder -Recurse -force
		    }
		
		# Create the Scheduled Task thar re-execute this script depending on defined triggers
			$taskAction = New-ScheduledTaskAction -Execute "$taskCommand" -Argument "$taskArg"
			
			# set task trigger list object
			$taskTriggerList = New-Object -TypeName "System.Collections.ArrayList"
			
			# set a trigger at startup
			$taskTrigger = New-ScheduledTaskTrigger -AtStartup
			$taskTriggerList.Add($taskTrigger) | Out-Null
			
			# set a trigger at logon
			$taskTrigger = New-ScheduledTaskTrigger -AtLogon
			$taskTriggerList.Add($taskTrigger) | Out-Null
			
			# set a trigger at repetition interval
			$taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $taskRepetitionInterval)
			$taskTriggerList.Add($taskTrigger) | Out-Null
			
			# set principal account to NT AUTHORITY\SYSTEM
			$taskPrincipal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
			
			# set settings
			$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
			
			# create and register task
			$task = New-ScheduledTask -Action $taskAction -Trigger $taskTriggerList -Principal $taskPrincipal -Settings $taskSettings
			Register-ScheduledTask -TaskName "$taskName" -InputObject $task -TaskPath $taskPath
			
		    Write-Log "Windows Scheduled Task $($taskName) created and registred to run at next reboot/logon/log off or at next repetition interval."
		
		# Create a tag file just so Intune knows that script completed
		    Write-Log "Create a tag file just so Intune knows that staging phase completed: '$logPath\$flagFile'"
		    Set-Content -Path "$logPath\$flagFile" -Value "Staging-Phase-Completed."
		
		# Exit
		    Write-Log "Script execution will re-run at next reboot or at repetition interval of scheduled task."
		    Write-Log "Staging phase is completed."
		    Write-Log "Exit script."
		    Exit 0
	}
}
else
{
	Write-Log "Not in defaultuser session."
	
	# check script exist in cachefolder otherise exit.
	if (-not (Test-Path "$cacheFolder\$scriptName"))
	{
		Write-Log "Not supported scenario. Exit script."
		# Create a tag file just so Intune knows that script completed
		Write-Log "Create a tag file just so Intune knows that is completed: '$logPath\$flagFile'"
		Set-Content -Path "$logPath\$flagFile" -Value "Not supported scenario."
		Exit 0
	}
	
	# check for Task Named as $taskName variable value if already scheduled
	$existingTask = Get-ScheduledTask -TaskName "$taskName" -ErrorAction SilentlyContinue
	if ($existingTask -ne $null)
	{
		Write-Log "Scheduled task $taskName already exists."
	}
	else
	{
		Write-Log "Not supported scenario. Exit script."
		# Create a tag file just so Intune knows that script completed
		Write-Log "Create a tag file just so Intune knows that is completed: '$logPath\$flagFile'"
		Set-Content -Path "$logPath\$flagFile" -Value "Not supported scenario."
		Exit 0
	}
	
	# check for Device ESP status
	Write-Log "Checking Device ESP status..."
	$deviceESP = getDeviceESPStatus
	switch ($deviceESP)
	{
		'succeeded' {
			Write-Log "Device ESP status: Completed with success."
			
			# set success final lock screen
			Write-Log "Set a success lock screen as final screen..."
			setLockScreen($successLockscreenFile)
			
			# check and confirm final lockscreen is set as expected
			$LockScreenImage = "$cacheFolder\$successLockscreenFile"
			$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
			
			if ((Test-RegistryKeyValue -Path $RegPath -Name "LockScreenImagePath") -and (Test-RegistryKeyValue -Path $RegPath -Name "LockScreenImageUrl") -and (Test-RegistryKeyValue -Path $RegPath -Name "LockScreenImageStatus"))
			{
				Write-Log "Final screen set as expected."
				$finalScreenApplied = $true
			}
			else
			{
				$finalScreenApplied = $false
				Write-Log "Final screen NOT set as expected."
				Write-Log "Final screen is not set. Exit script..."
				Write-Log "Script execution will re-run at next reboot/logon or at next repetition interval."
				Exit 0
			}
			
			if ($finalScreenApplied)
			{
				# check for TaskName $taskName if already scheduled and remove it
				$taskName = "setFinalScreen"
				$existingTask = Get-ScheduledTask -TaskName "$taskName" -ErrorAction SilentlyContinue
				if ($existingTask -ne $null)
				{
					Write-Log "Unregistering  Scheduled Task named: $taskName."
					Disable-ScheduledTask -TaskName "$taskName" -ErrorAction Ignore
					Unregister-ScheduledTask -TaskName "$taskName" -TaskPath "$taskPath\" -Confirm:$false -ErrorAction Ignore
				}
				
				# prepare another new scheduled task for final screen removal to run at logon
					$newTaskName = "RemoveFinalScreen"
					$newTaskPath = '\Microsoft'
					$newTaskCommand = "$($env:WinDir)\System32\WindowsPowerShell\v1.0\powershell.exe"
					$newTaskScript = "$cacheFolder\RemoveFinalScreen.ps1"
					$newTaskArg = "-ExecutionPolicy Bypass -File $newTaskScript"
					$newTaskAction = New-ScheduledTaskAction -Execute "$newTaskCommand" -Argument "$newTaskArg"
					$newTaskTriggerList = New-Object -TypeName "System.Collections.ArrayList"
					
                    # set trigger at logon
					$newTaskTrigger = New-ScheduledTaskTrigger -AtLogon
					$newTaskTriggerList.Add($newTaskTrigger) | Out-Null
				
                    # set principal
					$newTaskPrincipal = New-ScheduledTaskPrincipal "NT Authority\System"
				
					# set settings
					$newTaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
				
					# create and register the task
					$newTask = New-ScheduledTask -Action $newTaskAction -Trigger $newTaskTriggerList -Principal $newTaskPrincipal -Settings $newTaskSettings
					Register-ScheduledTask -TaskName "$newTaskName" -InputObject $newTask -TaskPath $newTaskPath
					
				Write-Log "A new Windows Scheduled Task $($newTaskName) created and registred to run at next user logon to remove the applied final screen."
				
				# schedule a reboot to apply final screen and exit
				Write-Log "Initiating a restart in $($waitTimeBeforeReboot) seconds to apply final screen..."
				& shutdown.exe /g /t $waitTimeBeforeReboot /f /c "Computer will restart after $($waitTimeBeforeReboot) seconds to apply final screen."
				Exit 0
			}
		}
		'failed' {
			Write-Log "Device ESP status: Completed with failure."
			
			# Check for TaskName $taskName if already scheduled and remove it
			$existingTask = Get-ScheduledTask -TaskName "$taskName" -ErrorAction SilentlyContinue
			if ($existingTask -ne $null)
			{
				Write-Log "Unregistering  Scheduled Task named: $taskName"
				Disable-ScheduledTask -TaskName "$taskName" -ErrorAction Ignore
				Unregister-ScheduledTask -TaskName "$taskName" -TaskPath "$taskPath\" -Confirm:$false -ErrorAction Ignore
			}
			
			# Cleanup
			  if (Test-Path -path $cacheFolder) {
			  	Write-Log "Removing content from cache folder:$cacheFolder"
			  	Remove-Item -Path $cacheFolder -Recurse -Force -ErrorAction SilentlyContinue
			  }
		}
		'inProgress' {
			Write-Log "Device ESP status: inProgress. Exit script..."
			Write-Log "Script execution will re-run at next reboot/logon or at next repetition interval."
			Exit 0
		}
		'notStarted' {
			Write-Log "Device ESP status: notStarted yet. Exit script..."
			Write-Log "Script execution will re-run at next reboot/logon or at next repetition interval."
			Exit 0
		}
		default {
			Write-Log "Device ESP status: unknown. Cleanup and Exit script..."
			# Check for TaskName $taskName if already scheduled and remove it
			$existingTask = Get-ScheduledTask -TaskName "$taskName" -ErrorAction SilentlyContinue
			if ($existingTask -ne $null)
			{
				Write-Log "Unregistering  Scheduled Task named: $taskName"
				Disable-ScheduledTask -TaskName "$taskName" -ErrorAction Ignore
				Unregister-ScheduledTask -TaskName "$taskName" -TaskPath "$taskPath\" -Confirm:$false -ErrorAction Ignore
			}
			
			# Cleanup
			if (Test-Path -path $cacheFolder)
			{
				Write-Log "Removing content from cache folder:$cacheFolder"
				Remove-Item -Path $cacheFolder -Recurse -Force -ErrorAction SilentlyContinue
			}
			
			Exit 0
		}
	}
}


