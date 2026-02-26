<#
.SYNOPSIS
<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.249
	 Created on:   	14.10.2024 - version 1.0.0
	 Created by:   	Amar_Maouche - Dell Deployment Engineer
	 Organization: 	Dell Inc.
	 Filename:     	removeFinalScreen.ps1
	===========================================================================
	.DESCRIPTION
		It removes the previously applied final screen as defined in $successLockscreenFile variable and cleanup cache folder and existing scheduled tasks.
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

# set scheduled task variables
$taskName = "RemoveFinalScreen"
$taskPath = '\Microsoft\'

# Log folder and file
$logName = $($((Split-Path $MyInvocation.MyCommand.Definition -leaf)).replace("ps1", "log"))
$logPath = "$($env:ProgramData)\Microsoft\IntuneManagementExtension\Logs"
$logFile = "$logPath\$logName"

# Cache folder used to host source files
$cacheFolder = "$($env:ProgramData)\Microsoft\$appName"

# set Variable for Lockscreen
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$backupRegFile = "BakupPersonalizationCSP.reg"

# set varible for the applied success final lock screen
$successLockscreenFile = "GreenLockscreen.jpg"

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

# start logging...
Write-Log "Starting script execution ..."

# check and confirm final lockscreen is detected
    $LockScreenImage = "$cacheFolder\$successLockscreenFile"
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

    if ((Test-RegistryKeyValue -Path $RegPath -Name "LockScreenImagePath") -and (Test-RegistryKeyValue -Path $RegPath -Name "LockScreenImageUrl") -and (Test-RegistryKeyValue -Path $RegPath -Name "LockScreenImageStatus"))
    {
	    $lockScreenImagePathRegValue = Get-ItemPropertyValue -Path $RegPath -Name "LockScreenImagePath"
	    $lockScreenImageUrlRegValue = Get-ItemPropertyValue -Path $RegPath -Name "LockScreenImageUrl"
	    #$lockScreenImageStatusRegValue = Get-ItemPropertyValue -Path $RegPath -Name "LockScreenImageStatus"
	
	    if (($lockScreenImagePathRegValue -eq $LockScreenImage) -and ($lockScreenImageUrlRegValue -eq $LockScreenImage))
	    {
		    Write-Log "Final screen detected. Removing it..."
		    $finalScreenDetected = $true
	    }
	    else
	    {
		    $finalScreenDetected = $false
		    Write-Log "Final screen NOT detected. Skip removal."
	    }
    }
    else
    {
	    $finalScreenDetected = $false
	    Write-Log "Final screen NOT detected. Skip removal."
    }

# remove applied lock screen
    if ($finalScreenDetected)
    {
	    if (Test-Path -Path "$cacheFolder\$backupRegFile")
	    {
		    # import existing backup configuration
		    write-Log "Import existing backed-up up file:'$($backupRegFile)'."
		    reg import "$cacheFolder\$backupRegFile"
		    sleep 3
	    }
	    else
	    {
		    # Remove final screen from LockScreen registry keys
		    Write-Log "Removing previously applied final screen from LockScreen registry keys."
		    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" -Name "LockScreenImagePath" -ErrorAction SilentlyContinue
		    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" -Name "LockScreenImageUrl" -ErrorAction SilentlyContinue
		    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" -Name "LockScreenImageStatus" -ErrorAction SilentlyContinue
	    }
    }

# remove scheduled task named setFinalScreen if exists
    $previousTaskName = "setFinalScreen"
    $existingTask = Get-ScheduledTask -TaskName "$previousTaskName" -ErrorAction SilentlyContinue
    if ($existingTask -ne $null)
    {
	    Write-Log "Unregistering  Scheduled Task named: $previousTaskName"
	    Disable-ScheduledTask -TaskName "$previousTaskName" -ErrorAction Ignore
	    Unregister-ScheduledTask -TaskName "$previousTaskName" -TaskPath "$taskPath\" -Confirm:$false -ErrorAction Ignore
    }

# remove scheduled tak named removeFinalScreen if exists
    $existingTask = Get-ScheduledTask -TaskName "$taskName" -ErrorAction SilentlyContinue
    if ($existingTask -ne $null)
    {
	    # Unregistering  Scheduled Task named: $taskName
	    Write-Log "Unregistering  Scheduled Task named: $taskName"
	    Disable-ScheduledTask -TaskName "$taskName" -ErrorAction Ignore
	    Unregister-ScheduledTask -TaskName "$taskName" -TaskPath "$taskPath" -Confirm:$false -ErrorAction Ignore
    }

# cleanup
    if (Test-Path -path $cacheFolder)
    {
	    Write-Log "Removing content from cache folder:$cacheFolder"
	    Remove-Item -Path $cacheFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

# exit
    Write-Log "Script execution completed."
    Exit

