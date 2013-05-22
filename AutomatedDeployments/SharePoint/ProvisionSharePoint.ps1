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

param([parameter(Mandatory=$true)][string]$configFilePath)

Import-Module "C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1"

$scriptFolder = Split-Path -Parent (Split-Path -parent $MyInvocation.MyCommand.Definition)
$config = [xml](gc $configFilePath)

Select-AzureSubscription -SubscriptionName $config.Azure.SubscriptionName

$serviceAccountScriptPath = (Join-Path -Path $scriptFolder -ChildPath 'SharePoint\ConfigureServiceAccounts.ps1')
$spScriptPath = (Join-Path -Path $scriptFolder -ChildPath 'SharePoint\ProvisionSharePointVm.ps1')

. "$scriptFolder\SharedComponents\SharedFunctions.ps1"


Use-RunAs

Write-Host "Installing SharePoint Server 2013 using Configuration Template: $configFilePath"

$ouName = 'ServiceAccounts'
foreach($serviceAccount in $config.Azure.ServiceAccounts.ServiceAccount)
{
	if($serviceAccount.Username.Contains('\') -and ([string]::IsNullOrEmpty($serviceAccount.Create) -or (-not $serviceAccount.Create.Equals('No'))))
	{
		$username = $serviceAccount.Username.Split('\')[1]
		$password = $serviceAccount.Password
		$adminPassword = GetPasswordByUsername $config.Azure.Connections.ActiveDirectory.ServiceAccountName $config.Azure.ServiceAccounts.ServiceAccount
		& $serviceAccountScriptPath -SubscriptionName $config.Azure.SubscriptionName -VMName $config.Azure.Connections.ActiveDirectory.DomainControllerVM `
		-ServiceName $config.Azure.Connections.ActiveDirectory.ServiceName `
		-OuName $ouName -ADUsername $username -SamAccountName $username -DisplayName $username -AccountPassword $password `
		-AdminUsername $config.Azure.Connections.ActiveDirectory.ServiceAccountName `
		-Password $adminPassword
	}
}

# Provision VMs in each VM Role
$spFarmUsername = $config.Azure.SharePointFarm.FarmAdminUsername
$configDbName = $config.Azure.SharePointFarm.ConfigDBName
$isFirstServer = $true
$firstServerServiceName = [string]::Empty
$firstServerVmName = [string]::Empty
foreach($vmRole in $config.Azure.AzureVMGroups.VMRole)
{
	$subnetNames = @($vmRole.SubnetNames)
	$servicesToStart = @()
	foreach($saDeploymentGroup in $config.Azure.SharePointFarm.ServiceApplications.SADeploymentGroup)
	{
		if($saDeploymentGroup.StartOnVMRoles -ne $null -and $saDeploymentGroup.StartOnVMRoles.Contains($vmRole.Name))
		{
			foreach($serviceApp in $saDeploymentGroup.ServiceApplication)
			{
				$servicesToStart += @($serviceApp.DisplayName)
			}
		}
	}
	$affinityGroup = $config.Azure.AffinityGroup
    $vnetName = $config.Azure.VNetName
	foreach($azureVm in $vmRole.AzureVM)
	{		
		$dataDisks = @()
		foreach($dataDiskEntry in $vmRole.DataDiskSizesInGB.Split(';'))
		{
			$dataDisks += @($dataDiskEntry)
		}
		$availabilitySetName = $vmRole.AvailabilitySet
		if([string]::IsNullOrEmpty($availabilitySetName))
		{
			$availabilitySetName = $config.Azure.ServiceName
		}
		
		$password = GetPasswordByUsername $vmRole.AdminUsername $config.Azure.ServiceAccounts.ServiceAccount
		$spFarmPassword = GetPasswordByUsername $spFarmUsername $config.Azure.ServiceAccounts.ServiceAccount
		$installerDomainPassword = GetPasswordByUsername $config.Azure.SharePointFarm.InstallerDomainUsername $config.Azure.ServiceAccounts.ServiceAccount
		$installerDatabasePassword = GetPasswordByUsername $config.Azure.SharePointFarm.InstallerDatabaseUsername $config.Azure.ServiceAccounts.ServiceAccount
		$farmParaphrase = GetPasswordByUsername $config.Azure.SharePointFarm.FarmparaphraseServiceAccountName $config.Azure.ServiceAccounts.ServiceAccount
        $appPoolPassword = GetPasswordByUsername $config.Azure.SharePointFarm.ApplicationPoolAccount $config.Azure.ServiceAccounts.ServiceAccount

		& $spScriptPath -subscriptionName $config.Azure.SubscriptionName -storageAccount $config.Azure.StorageAccount `
		-vnetName $vnetName -subnetNames $subnetNames -vmName $azureVm.Name -serviceName $config.Azure.ServiceName -vmSize $vmRole.VMSize `
		-availabilitySetName $availabilitySetName -dataDisks $dataDisks -sqlServer $config.Azure.Connections.SQLServer.Instance `
		-configDbName $configDbName -createFarm $isFirstServer -affinityGroup $affinityGroup `
		-spFarmUsername $spFarmUsername -spServicesToStart $servicesToStart	-ImageName $vmRole.StartingImageName -AdminUserName $vmRole.AdminUsername `
		-AdminPassword $password -appPoolAccount $config.Azure.SharePointFarm.ApplicationPoolAccount -appPoolPassword $appPoolPassword -DomainDnsName $config.Azure.Connections.ActiveDirectory.DnsDomain `
		-InstallerDomainUsername $config.Azure.SharePointFarm.InstallerDomainUsername -spFarmPassword $spFarmPassword `
		-InstallerDomainPassword $installerDomainPassword -InstallerDatabaseUsername $config.Azure.SharePointFarm.InstallerDatabaseUsername `
		-InstallerDatabasePassword $installerDatabasePassword -adminContentDbName $config.Azure.SharePointFarm.AdminContentDBName -spFarmParaphrase $farmParaphrase 
        
		
		
	
		if($isFirstServer)
		{
			$firstServerServiceName = $config.Azure.ServiceName
			$firstServerVmName = $azureVm.Name
			$isFirstServer = $false
		}
	}
}

# Create Web Applications and top-level site
$databases = @()
if(-not [string]::IsNullOrEmpty($firstServerServiceName) -and -not [string]::IsNullOrEmpty($firstServerVmName))
{
	$spuris = Get-AzureWinRMUri -ServiceName $firstServerServiceName -Name $firstServerVmName
	$spusername = $config.Azure.SharePointFarm.InstallerDomainUserName
	$sppassword = GetPasswordByUserName $spusername $config.Azure.ServiceAccounts.ServiceAccount
	$credential = New-Object System.Management.Automation.PSCredential($spusername, (ConvertTo-SecureString $sppassword -AsPlainText -Force))
	$databaseUsername = $config.Azure.SharePointFarm.InstallerDatabaseUsername
	$databasePassword = GetPasswordByUsername $config.Azure.SharePointFarm.InstallerDatabaseUsername $config.Azure.ServiceAccounts.ServiceAccount
	$databaseCredential = New-Object System.Management.Automation.PSCredential($databaseUsername, (ConvertTo-SecureString $databasePassword -AsPlainText -Force))
	$session = New-PSSession -ComputerName $spuris[0].DnsSafeHost -Credential $credential -Authentication Credssp -Port $spuris[0].Port -UseSSL
	
    
	foreach($webApp in $config.Azure.SharePointFarm.WebApplications.WebApplication)
	{
        Invoke-Command -session $session -ArgumentList $webApp.Name, $config.Azure.SharePointFarm.ApplicationPoolName, $config.Azure.SharePointFarm.ApplicationPoolAccount, $webApp.Url, `
		$webApp.TopLevelSiteName, $webApp.TopLevelSiteTemplate, $webApp.TopLevelSiteOwner, $databaseCredential, $config.Azure.ServiceName, $webApp.Port -ScriptBlock {
			param(
			[string]$name,
			[string]$appPoolName,
			[string]$appPoolAccount,
			[string]$url,
			[string]$siteName,
			[string]$siteTemplate,
			[string]$siteOwner,
			[Management.Automation.PSCredential]$databaseCredential,
            [string]$serviceName,
            [string]$port
			)
			Add-PSSnapin Microsoft.SharePoint.PowerShell
			$existingWebApp = Get-SPWebApplication | Where-Object {$_.Url.Trim('/') -eq $url.Trim('/')}
			if($existingWebApp -eq $null)
			{
				Write-Host "Creating web application..."

                $authProvider = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication -UseBasicAuthentication
                # remove protocol for hostheader
                $hostHeader = $url.ToLower().Replace("http://", "")
                $hostHeader = $hostHeader.ToLower().Replace("https://", "")
				$spwebapp = New-SPWebApplication -Name $name -URL $url -Port $port -HostHeader $hostHeader -ApplicationPool $appPoolName -ApplicationPoolAccount $appPoolAccount -DatabaseCredentials $databaseCredential -AuthenticationProvider $authProvider
				$spsite = New-SPSite -name $siteName -url $url -Template $siteTemplate -OwnerAlias $siteOwner
				Write-Host "Web application created."
                Write-Host "Adding Alternative Access Mapping for Web App..."
                New-SPAlternateUrl -WebApplication $url -Url ("http://" + $serviceName + ".cloudapp.net") -Zone Default
			}
			else
			{
				Write-Host "Web application already exists."
			}
		}
	}
	
	Remove-PSSession $session
    

	# Configure databases for high availability
	if(-not [string]::IsNullOrEmpty($config.Azure.Connections.SQLServer.FailoverInstance) -and
		-not [string]::IsNullOrEmpty($config.Azure.Connections.SQLServer.AvailabilityGroup))
	{
		$installerDomainUserName = $config.Azure.SharePointFarm.InstallerDomainUserName
		$installerDomainPassword = GetPasswordByUserName $installerDomainUserName $config.Azure.ServiceAccounts.ServiceAccount
		EnsureSPDatabasesInAvailabilityGroup -spServerServiceName $firstServerServiceName -spServerName $firstServerVmName `
		-spInstallerDatabaseUsername $config.Azure.SharePointFarm.InstallerDatabaseUsername `
		-spFarmDomainUsername $config.Azure.SharePointFarm.FarmAdminUsername -availabilityGroup $config.Azure.Connections.SQLServer.AvailabilityGroup `
		-installerDomainUsername $installerDomainUserName -installerDomainPassword $installerDomainPassword `
		-sqlClusterServiceName $config.Azure.Connections.SQLServer.ServiceName -sqlServerPrimary $config.Azure.Connections.SQLServer.Instance `
		-sqlServerSecondary $config.Azure.Connections.SQLServer.FailOverInstance
	}
}



# Enable health probes for the WFEs to allow traffic in 
# Only needed for load balanced WFEs 
foreach($vmRole in $config.Azure.AzureVMGroups.VMRole)
{
    if($vmRole.Name -eq "SharePointWebServers")
    {
        Write-Host "Configuring Default Website to Allow Health Probes"
        foreach($azureVm in $vmRole.AzureVM)
	    {	
            $uri = Get-AzureWinRMUri -ServiceName $config.Azure.ServiceName -Name $azureVm.Name
            Invoke-Command -ConnectionUri $uri.ToString() -Credential $credential -Authentication Credssp -ScriptBlock {  
                Set-ExecutionPolicy Unrestricted     
                Import-Module WebAdministration     
                # Open up the firewall for 8080
                netsh advfirewall firewall add rule name="LB Health Check 8080" protocol=TCP dir=in localport=8080 action=allow
                # Change default website to listen on 8080
                Set-WebBinding -Name 'Default Web Site' -BindingInformation "*:80:" -PropertyName Port -Value 8080
                # Tell default website to start on iisreset
                Set-ItemProperty 'IIS:\Sites\Default Web Site' serverAutoStart True
                iisreset 
                Start-WebSite "Default Web Site"
            }
        }
    }
}