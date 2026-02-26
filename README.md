# Description
Only supported for Self Deploying mode with Shared devices (Kiosk mode with Autologon enabled not supported): once Device setup is completed, the default lock screen will be changed to a final screen (green one) as a proof of the success of the deployment.

## Requirements and Dependencies
This uses the Microsoft Win32 Content Prep Tool (a.k.a. IntuneWinAppUtil.exe, available from https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool) to package the PowerShell script and related files into a .intunewin file that can be uploaded to Intune as a Win32 app. 

## Using
Add the Win32 app (.intunewin) to Intune.  

The installation command line should be:
powershell.exe -noprofile -executionpolicy bypass -file .\SetFinalScreen.ps1

The uninstall command line should be:
powershell.exe -executionpolicy Bypass -file .\RemoveFinalScreen.ps1


Device restart behavior:  no specific action

The detection rule should look for the existence of this file:
Path:  %ProgramData%\Microsoft\IntuneManagementExtension\Logs
File or folder:  SetFinalScreen.flg
Detection method:  File or folder exists
