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

Write-Host "Formatting data disks"
FormatDisk $serviceName $vmName $installerDomainUsername $installerDomainPassword

Write-Host "Enabling CredSSP on $vmName"
EnableCredSSPServerIfNotEnabledBackwardCompatible $serviceName $vmName $installerDomainUsername $installerDomainPassword

# Configure SQL Server for SharePoint installation
$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName
	  

Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $localAdminCredential -Port $uris[0].Port -UseSSL -Authentication Credssp `
	-ArgumentList $installerDatabaseUsername, $installerDatabasePassword, $installerDomainUsername, $defaultSqlDataFolder, $defaultSqlLogFolder, `
	$highAvailabilityType, $vmType -ScriptBlock {
		param($installerDatabaseUsername, $installerDatabasePassword, $installerDomainUsername, $defaultSqlDataFolder, $defaultSqlLogFolder, $highAvailabilityType, $vmType)
	Set-ExecutionPolicy Unrestricted

	# Add Install User as Local Admin
	net localgroup administrators "$installerDomainUsername" /Add

	# Add Dependent Feature for Creating Failover-Clustering
	Write-Host "High Availabity Type Specified: $highAvailabilityType"
    if($highAvailabilityType -eq "SQLAlwaysOn")
	{
        Write-Host "Installing Failover-Clustering feature"
		Import-Module ServerManager
		$OsBuildNumber = [System.Environment]::OSVersion.Version.Build
		if ($OsBuildNumber -lt 7600)
		{
			Write-Error "Not support on Windows Visa or lower"
			exit 1
		}
		elseif ($OsBuildNumber -lt 9200)
		{
			Write-Output "Windows Server 2008 R2 detected" 
			Add-WindowsFeature 'Failover-Clustering', 'RSAT-Clustering'
		}
		else 
		{
		  Write-Output "Windows Server 2012 or above detected"
		  Add-WindowsFeature 'Failover-Clustering', 'RSAT-Clustering-PowerShell', 'RSAT-Clustering-CmdInterface'
		}		
	}
    else
    {
        Write-Host "Not Installing Failover-Clustering feature"
    }

	if([string]::IsNullOrEmpty($vmType) -or (-not $vmType.Equals('QUORUM')))
	{
		Write-Host "Configuring firewall..."
		netsh advfirewall firewall add rule name='SQL Server (TCP-In)' program='C:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Binn\sqlservr.exe' dir=in action=allow protocol=TCP
		Write-Host "Firewall configured."
					
		Write-Host "Configuring database permissions and options..."	
		Import-Module sqlps -Verbose
		Invoke-Sqlcmd -ServerInstance $env:COMPUTERNAME -Database master -Query `
		"	    
        USE [master]
        IF Not EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$installerDatabaseUsername')
        BEGIN
		    CREATE LOGIN [$installerDatabaseUsername] WITH PASSWORD='$installerDatabasePassword' 
		    EXEC sp_addsrvrolemember '$installerDatabaseUsername', 'dbcreator'
			EXEC sp_addsrvrolemember '$installerDatabaseUsername', 'securityadmin'
        END
        
        IF Not EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$installerDomainUsername')
        BEGIN
		    CREATE LOGIN [$installerDomainUsername] FROM WINDOWS
		    EXEC sp_addsrvrolemember '$installerDomainUsername', 'sysadmin'
        END      
        EXEC sp_addsrvrolemember 'NT AUTHORITY\SYSTEM', 'sysadmin'
        "

	
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
	