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

#Command line arguments
param(
$subscriptionName,
$storageAccount,
$serviceName,
$vmName,
$vmSize,
$imageName,
$availabilitySetName,
$dataDisks,
$adminUsername,
$adminPassword,
$subnetNames,
$domainDnsName,
$installerDomainUsername,
$installerDomainPassword,
$installerDatabaseUsername,
$installerDatabasePassword,
$spFarmUsername,
$spFarmPassword,
$createFarm,
$affinityGroup,
$sqlServer,
$configDbName,
$adminContentDbName,
$spFarmParaphrase,
$spServicesToStart
)
Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1'

# Create credential object
$secPassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
$adminCredential = New-Object System.Management.Automation.PSCredential($adminUsername, $secPassword)

$domainSecPassword = ConvertTo-SecureString $installerDomainPassword -AsPlainText -Force
$installerDomainCredential = New-Object System.Management.Automation.PSCredential($installerDomainUsername, $domainSecPassword)

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
	
Write-Host "Pausing to allow services to start"
Start-Sleep -Seconds 180 # ensure that all services are fully started

Write-Host "Formatting data disks"
FormatDisk $serviceName $vmName $installerDomainUsername $installerDomainPassword

Write-Host "Enabling CredSSP on $vmName"
EnableCredSSPServerIfNotEnabled $serviceName $vmName $installerDomainCredential

# Perform installation
$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName


$maxRetry = 5
For($retry = 0; $retry -le $maxRetry; $retry++)
{
	Try
	{
		Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $installerDomainCredential -Authentication Credssp -Port $uris[0].Port -UseSSL `
			-ArgumentList $createFarm, $sqlServer, $configDbName, $adminContentDbName, $installerDatabaseUsername, $installerDatabasePassword, $spFarmUsername, $spFarmPassword, $spFarmParaphrase, $spServicesToStart -ScriptBlock {
				param($createFarm, $sqlServer, $configDbName, $adminContentDbName, $installerDatabaseUsername, $installerDatabasePassword, $spFarmUsername, $spFarmPassword, $spFarmParaphrase, $spServicesToStart, 
				$timeoutsec = 30)
				$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, $timeoutsec
			Add-PSSnapin Microsoft.SharePoint.PowerShell
			$spfarm = $null 
            try
            {
                $spfarm = Get-SPFarm -ErrorAction SilentlyContinue
            }
            catch
            {
                Write-Host "This server is not in a SharePoint farm."
            }
			if($spfarm -eq $null) {
				# Create or connect to database and farm
			    $databaseSecPassword = ConvertTo-SecureString $installerDatabasePassword -AsPlainText -Force
				$databaseCredential = New-Object System.Management.Automation.PSCredential $installerDatabaseUsername, $databaseSecPassword
			    $farmSecPassword = ConvertTo-SecureString $spFarmPassword -AsPlainText -Force
				$farmCredential = New-Object System.Management.Automation.PSCredential $spFarmUsername, $farmSecPassword
				if($createFarm)
				{
					Write-Host "Creating farm..."
					New-SPConfigurationDatabase -DatabaseName $configDbName -DatabaseServer $sqlServer -AdministrationContentDatabaseName $adminContentDbName `
					-Passphrase (ConvertTo-SecureString $spFarmParaphrase -AsPlainText -Force) -DatabaseCredential $databaseCredential -FarmCredentials $farmCredential
					Write-Host "Farm created."
				
					# Install help collections
					Write-Host "Install help collections..."
					Install-SPHelpCollection -All
					Write-Host "Help collections installed."
					
					# Secure the SharePoint resources
					Write-Host "Securing SharePoint resources..."
					Initialize-SPResourceSecurity
					Write-Host "SharePoint resources secured."
					
					# Install services
					Write-Host "Installing services..."
					Install-SPService
					Write-Host "Services installed."
					
					# Register SharePoint features
					Write-Host "Registering SharePoint features..."
					Install-SPFeature -AllExistingFeatures
					Write-Host "SharePoint features registered."
					
					# Provision SharePoint Central Admin web application
					Write-Host "Provisioning Central Admin web app..."
					New-SPCentralAdministration -Port 20000 -WindowsAuthProvider "NTLM"
					Write-Host "Central Admin web app provisioned."
					
					# Install application content files
					Write-Host "Installing application content files..."
					Install-SPApplicationContent
					Write-Host "Application content files installed."
    

					# Workaround to fix bug where user profile service is not installed correctly when automated
			        Write-Host "Configuring User Profile Service"
                	$saAppPool = Get-SPServiceApplicationPool "SharePoint Web Services System" 
                   	New-SPProfileServiceApplication -Name "User Profile Service Application" -ApplicationPool $saAppPool -ProfileDBName "UPA1_Profile" -SocialDBName "UPA1_Social" -ProfileSyncDBName "UPA1_Sync" 

	                # ensure SharePoint Timer Service is started
					$timersvc = Get-Service -Name 'SPTimerV4'
					if($timersvc.Status -ne 'Running')
					{
						Start-Service $timersvc
						$timersvc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout)
						Write-Host ("{0} started." -f $timersvc.DisplayName)
					}
				}
				else
				{
					Write-Host "Joining farm..."
					Connect-SPConfigurationDatabase -DatabaseName $configDbName -DatabaseServer $sqlServer -DatabaseCredential $databaseCredential `
					-Passphrase (ConvertTo-SecureString $spFarmParaphrase -AsPlainText -Force)
					Write-Host "Joined farm."
				
					# Install help collections
					Write-Host "Install help collections..."
					Install-SPHelpCollection -All
					Write-Host "Help collections installed."
					
					# Secure the SharePoint resources
					Write-Host "Securing SharePoint resources..."
					Initialize-SPResourceSecurity
					Write-Host "SharePoint resources secured."
					
					# Install services
					Write-Host "Installing services..."
					Install-SPService
					Write-Host "Services installed."
					
					# Register SharePoint features
					Write-Host "Registering SharePoint features..."
					Install-SPFeature -AllExistingFeatures
					Write-Host "SharePoint features registered."
					
					# Install application content files
					Write-Host "Installing application content files..."
					Install-SPApplicationContent
					Write-Host "Application content files installed."
					
					# ensure SharePoint Timer Service is started
					$timersvc = Get-Service -Name 'SPTimerV4'
					if($timersvc.Status -ne 'Running')
					{
						Start-Service $timersvc
						$timersvc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout)
						Write-Host ("{0} started." -f $timersvc.DisplayName)
					}
				}
			}
			else
			{
				Write-Host "This server is already in a SharePoint farm."
			}
			
			Get-SPServiceInstance | 
			Where-Object {
			$_.Server.Address -eq $env:COMPUTERNAME -and
			$_.Status -ne 'Online' -and $_.TypeName -in $spServicesToStart} |
			ForEach-Object {
			Write-Host ("Starting Service Application {0}..." -f $_.TypeName)
			Start-SPServiceInstance $_.Id
			Write-Host "Service Application Started."
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
