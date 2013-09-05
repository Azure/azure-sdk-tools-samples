<#
.SYNOPSIS
    Creates scheduled tasks to start Virtual Machines.
.DESCRIPTION
    Creates scheduled tasks to start a single Virtual Machine or a set of Virtual Machines (using
    wildcard pattern syntax for the Virtual Machine name).
.EXAMPLE
    Start-AzureVMsOnSchedule.ps1 -ServiceName "MyServiceName" -VMName "testmachine1" `
        -TaskName "Start Test Machine 1" -At 8AM
    
    Start-AzureVMsOnSchedule.ps1 -ServiceName "MyServiceName" -VMName "test*" `
        -TaskName "Start All Test Machines" -At 8:15AM
#>


param(
    # The name of the VM(s) to start on schedule.  Can be wildcard pattern.
    [Parameter(Mandatory = $true)] 
    [string]$VMName,


    # The service name that $VMName belongs to.
    [Parameter(Mandatory = $true)] 
    [string]$ServiceName,


    # The name of the scheduled task.
    [Parameter(Mandatory = $true)] 
    [string]$TaskName,


    # The name of the "Stop" scheduled tasks.
    [Parameter(Mandatory = $true)] 
    [DateTime]$At)


# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3


# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"


# Check if Windows Azure Powershell is avaiable
if ((Get-Module -ListAvailable Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please install from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}


# Define a scheduled task to start the VM(s) on a schedule.
$startAzureVM = "Start-AzureVM -Name " + $VMName + " -ServiceName " + $ServiceName + " -Verbose"
$startTaskTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At $At
$startTaskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $startAzureVM
$startTaskSettingsSet = New-ScheduledTaskSettingsSet  -AllowStartIfOnBatteries 

$startScheduledTask = New-ScheduledTask -Action $startTaskAction -Trigger $startTaskTrigger -Settings $startTaskSettingsSet


# Register the scheduled tasks to start and stop the VM(s).
Register-ScheduledTask -TaskName $TaskName -InputObject $startScheduledTask

