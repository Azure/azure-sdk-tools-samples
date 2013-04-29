<#
 * Copyright Microsoft Corporation
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
#>

#Command line arguments with defaults
param(
$subscriptionName,
$storageAccount,
$serviceName,
$highAvailabilityType,
$vmName,
$vmSize,
$vmType,
$imageName,
$availabilitySetName,
$dataDisks,
$defaultSqlDataFolder,
$defaultSqlLogFolder,
$defaultSqlBackupFolder,
$adminUsername,
$adminPassword,
$vnetName,
$subnetNames,
$affinityGroup,
$domainDnsName,
$installerDomainUsername,
$installerDomainPassword,
$installerDatabaseUsername,
$installerDatabasePassword
)
Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1'

# Create credential object
$secPassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
$adminCredential = New-Object System.Management.Automation.PSCredential($adminUsername, $secPassword)
$localAdminCredential = New-Object System.Management.Automation.PSCredential(("{0}\{1}" -f $vmName, $adminUsername), $secPassword)

# Ensure correct subscription and storage account is selected
Select-AzureSubscription -SubscriptionName $subscriptionName
Set-AzureSubscription $subscriptionName -CurrentStorageAccount $storageAccount

# Display current subscription
$currentSubscription = Get-AzureSubscription -Current
"Current subscription: {0}" -f $currentSubscription.SubscriptionName

# Include script file for shared functions
$scriptFolder = Split-Path -parent $MyInvocation.MyCommand.Definition
. "$scriptFolder\..\SharedComponents\SharedFunctions.ps1"

CreateDomainJoinedAzureVmIfNotExists $serviceName $vmName $vmSize $imageName $availabilitySetName $dataDisks $vnetName $subnetNames $affinityGroup $adminUsername $adminPassword `
	$domainDnsName $installerDomainUsername $installerDomainPassword
	
Start-Sleep -Seconds 180 # ensure that SQL Services are fully started

FormatDisk $serviceName $vmName $installerDomainUsername $installerDomainPassword

EnableCredSSPServerIfNotEnabledBackwardCompatible $serviceName $vmName $installerDomainUsername $installerDomainPassword

# Configure SQL Server for SharePoint installation
$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName
	  
$maxRetry = 5
For($retry = 0; $retry -le $maxRetry; $retry++)
{
	Try
	{
		Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $localAdminCredential -Port $uris[0].Port -UseSSL `
			-ArgumentList $installerDatabaseUsername, $installerDatabasePassword, $installerDomainUsername, $defaultSqlDataFolder, $defaultSqlLogFolder, `
			$highAvailabilityType, $vmType -ScriptBlock {
				param($installerDatabaseUsername, $installerDatabasePassword, $installerDomainUsername, $defaultSqlDataFolder, $defaultSqlLogFolder, $highAvailibilityType, $vmType)
			Set-ExecutionPolicy Unrestricted

			# Add Install User as Local Admin
			net localgroup administrators "$installerDomainUsername" /Add

			# Add Dependent Feature for Creating Failover-Clustering
			if((-not [string]::IsNullOrEmpty($highAvailibilityType)) -and $highAvailibilityType.Equals("SQLAlwaysOn"))
			{
				Import-Module ServerManager
				Add-WindowsFeature Failover-Clustering
			}

			if([string]::IsNullOrEmpty($vmType) -or (-not $vmType.Equals('QUORUM')))
			{
				Write-Host "Configuring firewall..."
				netsh advfirewall firewall add rule name='SQL Server (TCP-In)' program='C:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Binn\sqlservr.exe' dir=in action=allow protocol=TCP
				Write-Host "Firewall configured."
					
				Write-Host "Configuring database permissions and options..."	
				Import-Module sqlps -Verbose
				Invoke-Sqlcmd -ServerInstance $env:COMPUTERNAME -Database master -Query `
				"USE [master]
				GO
				CREATE LOGIN [$installerDatabaseUsername] WITH PASSWORD='$installerDatabasePassword', DEFAULT_DATABASE=master 
				GO
				ALTER SERVER ROLE [dbcreator] ADD MEMBER [$installerDatabaseUsername]
				GO
				ALTER SERVER ROLE [securityadmin] ADD MEMBER [$installerDatabaseUsername]
				GO
				EXEC sp_addsrvrolemember [$installerDomainUsername], 'sysadmin'
				GO
				EXEC sp_addsrvrolemember 'NT AUTHORITY\SYSTEM', 'sysadmin'
				GO"
				
			    Invoke-Sqlcmd -ServerInstance $env:COMPUTERNAME -database master -Query `
				"USE [master]
				GO
				sp_configure 'show advanced options', 1;RECONFIGURE WITH OVERRIDE;
				GO
				sp_configure 'max degree of parallelism', 1;RECONFIGURE WITH OVERRIDE;
				GO"
				Write-Host "Database configured."

				Write-Host "Enabling mixed authentication mode and setting folder locations..."
				$s = new-object ('Microsoft.SqlServer.Management.Smo.Server') $env:COMPUTERNAME
				$s.Settings.LoginMode = [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed
				if(-not [string]::IsNullOrEmpty($defaultSqlDataFolder))
				{
					mkdir $defaultSqlDataFolder
					$s.Settings.DefaultFile = $defaultSqlDataFolder
				}
				if(-not [string]::IsNullOrEmpty($defaultSqlLogFolder))
				{
					mkdir $defaultSqlLogFolder
					$s.Settings.DefaultLog = $defaultSqlLogFolder
				}
				if(-not [string]::IsNullOrEmpty($defaultSqlBackupFolder))
				{
					mkdir $defaultSqlBackupFolder
					$s.Settings.BackupDirectory = $defaultSqlBackupFolder
				}
				$s.Alter()
				Restart-Service -Name MSSQLSERVER -Force
				Write-Host "Mixed authentication mode enabled and folder locations set."
			}
		}
		Break
	}
	Catch [System.Exception]
	{
		Write-Host "Error - retrying..."
		Start-Sleep 10
	}
}
