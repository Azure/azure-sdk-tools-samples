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
$appPoolAccount,
$appPoolPassword,
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
	
Write-Host "Formatting data disks"
FormatDisk $serviceName $vmName $installerDomainUsername $installerDomainPassword

Write-Host "Enabling CredSSP on $vmName"
EnableCredSSPServerIfNotEnabled $serviceName $vmName $installerDomainCredential

# Perform installation
$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName



Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $installerDomainCredential -Authentication Credssp -Port $uris[0].Port -UseSSL `
	-ArgumentList $createFarm, $sqlServer, $configDbName, $adminContentDbName, $installerDatabaseUsername, $installerDatabasePassword, $spFarmUsername, $spFarmPassword, $spFarmParaphrase, $spServicesToStart, $serviceName, $vmName, $appPoolAccount, $appPoolPassword -ScriptBlock {
		param($createFarm, $sqlServer, $configDbName, $adminContentDbName, $installerDatabaseUsername, $installerDatabasePassword, $spFarmUsername, $spFarmPassword, $spFarmParaphrase, $spServicesToStart, $serviceName, $vmName, $appPoolAccount, $appPoolPassword, $timeoutsec = 30)
		$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, $timeoutsec
	Add-PSSnapin Microsoft.SharePoint.PowerShell


    # disable loopback to fix 401s from SP Webs Service calls
    New-ItemProperty HKLM:\System\CurrentControlSet\Control\Lsa -Name “DisableLoopbackCheck” -value "1" -PropertyType dword

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

	        # ensure SharePoint Timer Service is started
			$timersvc = Get-Service -Name 'SPTimerV4'
			if($timersvc.Status -ne 'Running')
			{
				Start-Service $timersvc
				$timersvc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout)
				Write-Host ("{0} started." -f $timersvc.DisplayName)
			}

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
					
			# Install application content files
			Write-Host "Installing application content files..."
			Install-SPApplicationContent
			Write-Host "Application content files installed."

			# Register SharePoint features
			Write-Host "Registering SharePoint features..."
			Install-SPFeature -AllExistingFeatures -Force
			Write-Host "SharePoint features registered."

			# Provision SharePoint Central Admin web application
			Write-Host "Provisioning Central Admin web app..."
			New-SPCentralAdministration -Port 20000 -WindowsAuthProvider "NTLM"
			Write-Host "Central Admin web app provisioned."

            Write-Host "Adding Alternative Access Mapping for Central Admin Web App..."
            New-SPAlternateUrl -WebApplication ("http://" + $vmName + ":20000") -Url ("http://" + $serviceName + ".cloudapp.net:20000") -Zone Internet
            New-SPAlternateUrl -WebApplication ("http://" + $vmName + ":20000") -Url ("http://" + $serviceName + ":20000") -Zone Intranet

            # Start the user profile service before creating the service application
            $service = Get-SPServiceInstance | where {$_.TypeName -eq "User Profile Service"}
            if ($service.Status -ne "Online") {
                Write-Host "Starting User Profile Service instance" -NoNewline
                $service | Start-SPServiceInstance | Out-Null
                while ($true) {
                    Start-Sleep 2
                    $svc = Get-SPServiceInstance | where {$_.TypeName -eq "User Profile Service"}
                    if ($svc.Status -eq "Online") { break }
                }
                Write-Host
            }
            
            

          	$saAppPool = Get-SPServiceApplicationPool "SharePoint Web Services System" 
           	New-SPProfileServiceApplication -Name "User Profile Service Application" -ApplicationPool $saAppPool -ProfileDBName "UPA1_Profile" -SocialDBName "UPA1_Social" -ProfileSyncDBName "UPA1_Sync" 


            $svc = Get-SPServiceInstance | where {$_.TypeName -eq "User Profile Synchronization Service"}
            $app = Get-SPServiceApplication -Name "User Profile Service Application"

            if ($svc.Status -ne "Online") {
                Write-Host "Starting the User Profile Service Synchronization instance" -NoNewline
                $svc.Status = "Provisioning"
                $svc.IsProvisioned = $false
                $svc.UserProfileApplicationGuid = $app.Id
                $svc.Update()

                Write-Host "Setting Synchronization Server to $vmName"
                $app.SetSynchronizationMachine($vmName, $svc.Id, $spFarmUsername, $spFarmPassword)
          
                $svc | Start-SPServiceInstance | Out-Null
            }



            $accountName = $spFarmUsername
 
            $claimType = "http://schemas.microsoft.com/sharepoint/2009/08/claims/userlogonname"
            $claimValue = $accountName
            $claim = New-Object Microsoft.SharePoint.Administration.Claims.SPClaim($claimType, $claimValue, "http://www.w3.org/2001/XMLSchema#string", [Microsoft.SharePoint.Administration.Claims.SPOriginalIssuers]::Format("Windows"))
            $claim.ToEncodedString()
 
            $permission = [Microsoft.SharePoint.Administration.AccessControl.SPIisWebServiceApplicationRights]"FullControl"
 
            $SPAclAccessRule = [Type]"Microsoft.SharePoint.Administration.AccessControl.SPAclAccessRule``1"
            $specificSPAclAccessRule = $SPAclAccessRule.MakeGenericType([Type]"Microsoft.SharePoint.Administration.AccessControl.SPIisWebServiceApplicationRights")
            $ctor = $SpecificSPAclAccessRule.GetConstructor(@([Type]"Microsoft.SharePoint.Administration.Claims.SPClaim",[Type]"Microsoft.SharePoint.Administration.AccessControl.SPIisWebServiceApplicationRights"))
            $accessRule = $ctor.Invoke(@([Microsoft.SharePoint.Administration.Claims.SPClaim]$claim, $permission))
 
            $ups = Get-SPServiceApplication | ? { $_.TypeName -eq 'User Profile Service Application' }
            $accessControl = $ups.GetAccessControl()
            $accessControl.AddAccessRule($accessRule)
            $ups.SetAccessControl($accessControl)
            $ups.Update()

            Write-Host "Configuring Search Application"

            $managedAcct = Get-SPManagedAccount -Identity $appPoolAccount -ErrorAction SilentlyContinue
            if($managedAcct -eq $null)
            {
                Write-Host "Creating Managed Account for App Pool Identity $appPoolAccount"
                $appPoolCreds = New-Object System.Management.Automation.PSCredential($appPoolAccount, (ConvertTo-SecureString $appPoolPassword -AsPlainText -Force))
                New-SPManagedAccount -Credential $appPoolCreds
            }
            else
            {
                Write-Host "Managed Account $appPoolAccount already exists."
            }
                

            $IndexLocation = "F:\Data\Search15Index” 
            $SearchAppPoolName = "Search App Pool" 
            $SearchAppPoolAccountName = $appPoolAccount
            $SearchServerName = (Get-ChildItem env:computername).value 
            $SearchServiceName = "Search15" 
            $SearchServiceProxyName = "Search15 Proxy" 
            $DatabaseName = "Search15_ADminDB" 
            Write-Host -ForegroundColor Yellow "Checking if Search Application Pool exists" 
            $SPAppPool = Get-SPServiceApplicationPool -Identity $SearchAppPoolName -ErrorAction SilentlyContinue

            if (!$SPAppPool) 
            { 
                Write-Host -ForegroundColor Green "Creating Search Application Pool" 
                $spAppPool = New-SPServiceApplicationPool -Name $SearchAppPoolName -Account $SearchAppPoolAccountName -Verbose 
            }

            # Start Services search service instance 
            Write-host "Start Search Service instances...." 
            Start-SPEnterpriseSearchServiceInstance $SearchServerName -ErrorAction SilentlyContinue 
            Start-SPEnterpriseSearchQueryAndSiteSettingsServiceInstance $SearchServerName -ErrorAction SilentlyContinue

            Write-Host -ForegroundColor Yellow "Checking if Search Service Application exists" 
            $ServiceApplication = Get-SPEnterpriseSearchServiceApplication -Identity $SearchServiceName -ErrorAction SilentlyContinue

            if (!$ServiceApplication) 
            { 
                Write-Host -ForegroundColor Green "Creating Search Service Application" 
                $ServiceApplication = New-SPEnterpriseSearchServiceApplication -Partitioned -Name $SearchServiceName -ApplicationPool $spAppPool.Name -DatabaseName $DatabaseName 
            }

            Write-Host -ForegroundColor Yellow "Checking if Search Service Application Proxy exists" 
            $Proxy = Get-SPEnterpriseSearchServiceApplicationProxy -Identity $SearchServiceProxyName -ErrorAction SilentlyContinue

            if (!$Proxy) 
            { 
                Write-Host -ForegroundColor Green "Creating Search Service Application Proxy" 
                New-SPEnterpriseSearchServiceApplicationProxy -Partitioned -Name $SearchServiceProxyName -SearchApplication $ServiceApplication 
            }


            $ServiceApplication.ActiveTopology 
            Write-Host $ServiceApplication.ActiveTopology

            # Clone the default Topology (which is empty) and create a new one and then activate it 
            Write-Host "Configuring Search Component Topology...." 
            $clone = $ServiceApplication.ActiveTopology.Clone() 
            $SSI = Get-SPEnterpriseSearchServiceInstance -local 
            New-SPEnterpriseSearchAdminComponent –SearchTopology $clone -SearchServiceInstance $SSI 
            New-SPEnterpriseSearchContentProcessingComponent –SearchTopology $clone -SearchServiceInstance $SSI 
            New-SPEnterpriseSearchAnalyticsProcessingComponent –SearchTopology $clone -SearchServiceInstance $SSI 
            New-SPEnterpriseSearchCrawlComponent –SearchTopology $clone -SearchServiceInstance $SSI 

            Remove-Item -Recurse -Force -LiteralPath $IndexLocation -ErrorAction SilentlyContinue 
            mkdir -Path $IndexLocation -Force

            New-SPEnterpriseSearchIndexComponent –SearchTopology $clone -SearchServiceInstance $SSI -RootDirectory $IndexLocation 
            New-SPEnterpriseSearchQueryProcessingComponent –SearchTopology $clone -SearchServiceInstance $SSI 
            $clone.Activate()

            Write-host "Your search service application $SearchServiceName is now ready"
		}
		else
		{
            Write-Host "Enabling ICMP for PING"
            & netsh advfirewall firewall set rule name="File and Printer Sharing (Echo Request - ICMPv4-In)" new enable=yes

			Write-Host "Joining farm..."
			Connect-SPConfigurationDatabase -DatabaseName $configDbName -DatabaseServer $sqlServer -DatabaseCredential $databaseCredential `
			-Passphrase (ConvertTo-SecureString $spFarmParaphrase -AsPlainText -Force)
			Write-Host "Joined farm."

	        # ensure SharePoint Timer Service is started
			$timersvc = Get-Service -Name 'SPTimerV4'
			if($timersvc.Status -ne 'Running')
			{
				Start-Service $timersvc
				$timersvc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout)
				Write-Host ("{0} started." -f $timersvc.DisplayName)
			}

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

			# Install application content files
			Write-Host "Installing application content files..."
			Install-SPApplicationContent
			Write-Host "Application content files installed."

			# Register SharePoint features
			Write-Host "Registering SharePoint features..."
			Install-SPFeature -AllExistingFeatures -Force
			Write-Host "SharePoint features registered."
				
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
