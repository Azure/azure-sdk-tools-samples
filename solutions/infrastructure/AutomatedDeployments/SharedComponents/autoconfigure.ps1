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

Function AutoConfigure
{
    # If serviceName, storageAccount or servicePassword is specified do not automatically create
    param([parameter(Mandatory=$true)][string]$TemplateName,
          [parameter(Mandatory=$true)][string]$Location,
          [parameter(Mandatory=$true)][string]$ScriptFolder,
          [parameter(Mandatory=$false)][string]$subscriptionName="",
          [parameter(Mandatory=$false)][string]$serviceName="",
          [parameter(Mandatory=$false)][string]$storageAccountName="",
          [parameter(Mandatory=$false)][string]$adminAccount="spadmin",
          [parameter(Mandatory=$false)][string]$adminPassword="",
          [parameter(Mandatory=$false)][string]$appPoolAccount="spfarm",
          [parameter(Mandatory=$false)][string]$appPoolPassword="",
          [parameter(Mandatory=$false)][string]$Domain="corp",
          [parameter(Mandatory=$false)][string]$DnsDomain="corp.contoso.com",
          [parameter(Mandatory=$false)][string]$configOnly=$false,
          [parameter(Mandatory=$false)][string]$doNotShowCreds=$false
          )

    if($subscriptionName -ne "")
    {
        $subscription = Get-AzureSubscription -SubscriptionName $subscriptionName
    }
    else
    {
        $subscription = Get-AzureSubscription -Current
    }

    if($subscription -eq $null)
    {
        Write-Host "Windows Azure Subscription is not configured or the specified subscription name is invalid."
        Write-Host "Use Get-AzurePublishSettingsFile and Import-AzurePublishSettingsFile first"
        return
    }

    Select-AzureSubscription $subscription.SubscriptionName


    if($adminPassword -eq "")
    {
        $adminPassword = (randomString -length 10) + "0!"
        Write-Host "Generated Service Password"
    }
    if($appPoolPassword -eq "")
    {
        # if not specified use the same as the admin password
        $appPoolPassword = $adminPassword
    }
    if($serviceName -eq "")
    {
        while($true)
        {
            $serviceName = "sp-" + (randomString)
            if((Test-AzureName -Service $serviceName) -eq $true)
            {
                Write-Host "Dynamically generated $serviceName already exists. Looking for another."
            }
            else
            {
                Write-Host "Using $serviceName for Cloud Service Name"
                break
            }
        }
    }
    else
    {
        Write-Host "Use Cloud Service Name $serviceName."
    }

    if($storageAccountName -eq "")
    {
        while($true)
        {
            $storageAccountName = "spstorage" + (randomString)
            if((Test-AzureName -Storage $storageAccountName) -eq $true)
            {
                Write-Host "Dynamically generated $storageAccountName is in use. Looking for another."
            }
            else
            {
                Write-Host "Creating new storage account $storageAccountName in $location"
                try
                {
                    New-AzureStorageAccount -StorageAccountName $storageAccountName -Location $location
                }
                catch
                {
                    return
                }
                break
            }
        }
    }
    else
    {
        Write-Host "Using Storage Account $storageAccountName."
    }





    $ad = "$scriptFolder\AD\ProvisionAD.ps1"
    $sql = "$scriptFolder\SQL\ProvisionSQL.ps1"
    $sp = "$scriptFolder\SharePoint\ProvisionSharePoint.ps1"
    $adConfig = "$scriptFolder\Config\$templateName\AD-Sample.xml"
    $sqlConfig = "$scriptFolder\Config\$templateName\SQL-Sample.xml"
    $spConfig = "$scriptFolder\Config\$templateName\SharePoint-Sample.xml"


    $autoSqlConfig = "$scriptFolder\Config\$templateName\SQL-Sample-AutoGen.xml"
    $autoSPConfig = "$scriptFolder\Config\$templateName\SharePoint-Sample-AutoGen.xml"

    Write-Host "Setting AD Configuration File"
    $autoAdConfig = SetADConfiguration -configPath $adConfig -serviceName $serviceName -storageAccount $storageAccountName -subscription $subscription.SubscriptionName -adminAccount $adminAccount -password $adminPassword -domain $domain -dnsDomain $dnsDomain

    Write-Host "Setting SQL Configuration File"
    $autoSqlConfig = SetSqlConfiguration -configPath $sqlConfig -serviceName $serviceName -storageAccount $storageAccountName -subscription $subscription.SubscriptionName -adminAccount $adminAccount -password $adminPassword -domain $domain -dnsDomain $dnsDomain

    Write-Host "Setting SharePoint Configuration File"
    $autoSPConfig = SetSharePointConfiguration -configPath $spConfig -serviceName $serviceName -storageAccount $storageAccountName -subscription $subscription.SubscriptionName -adminAccount $adminAccount -password $adminPassword -domain $domain -dnsDomain $dnsDomain -appPoolAccount $appPoolAccount -appPoolPassword $appPoolPassword

    if($configOnly -eq $false)
    {
        Write-Host "Installing Active Directory"
        & $ad -configFilePath $autoAdConfig

        Write-Host "Installing SQL Server 2012"
        & $sql -configFilePath $autoSqlConfig

        Write-Host "Installing SharePoint Server 2013"
        & $sp -configFilePath $autoSPconfig

        Write-Host "Script Execution Complete. Verify no errors during execution."

        if($doNotShowCreds -eq $false)
        {
            Write-Host "Credentials: $domain\$adminAccount Password: $adminPassword"
            Write-Host "Created Farm on http://$serviceName.cloudapp.net"
            Write-Host "Created Admin Site on http://$serviceName.clouadpp.net:20000"
        }
    }
    else
    {
        Write-Host "Generated Configuration files in $scriptFolder\Config"
    }

}

function SetADConfiguration
{
    param($configPath,$serviceName,$storageAccount,$subscription, $adminAccount, $password, $domain, $dnsDomain)

    $w2k12img = (GetLatestImage "Windows Server 2012 Datacenter")
    $configPathAutoGen = $configPath.Replace(".xml", "-AutoGen.xml")

    [xml] $config = gc $configPath
    $config.Azure.SubscriptionName = $subscription
    $config.Azure.ServiceName = $serviceName
    $config.Azure.StorageAccount = $storageAccount
    $config.Azure.Location = $location
    $config.Azure.AzureVMGroups.VMRole.StartingImageName = $w2k12img
    $config.Azure.AzureVMGroups.VMRole.ServiceAccountName = $adminAccount
    $config.Azure.ActiveDirectory.Domain = $domain
    $config.Azure.ActiveDirectory.DnsDomain = $dnsDomain

    foreach($serviceAccount in $config.Azure.ServiceAccounts.ServiceAccount)
    {
        $serviceAccount.UserName = $adminAccount
        $serviceAccount.Password = $password
    }
    $config.Save($configPathAutoGen)
    return $configPathAutoGen
}

function SetSQLConfiguration
{
    param($configPath,$serviceName,$storageAccount,$subscription, $adminAccount, $password, $domain, $dnsDomain)
    $sql2k12img = (GetLatestImage "SQL Server 2012 SP1 Enterprise on Windows Server 2008 R2")
    $configPathAutoGen = $configPath.Replace(".xml", "-AutoGen.xml")
    [xml] $config = gc $configPath
    $config.Azure.SubscriptionName = $subscription
    $config.Azure.ServiceName = $serviceName
    $config.Azure.StorageAccount = $storageAccount
    $config.Azure.Connections.ActiveDirectory.ServiceName = $serviceName
    $config.Azure.Connections.ActiveDirectory.Domain = $domain
    $config.Azure.Connections.ActiveDirectory.DnsDomain = $dnsDomain
    $config.Azure.Connections.ActiveDirectory.ServiceAccountName = "$domain\$adminAccount"
    $config.Azure.AzureVMGroups.VMRole.ServiceAccountName = "$adminAccount"
    $config.Azure.AzureVMGroups.VMRole.StartingImageName = $sql2k12img

    if($config.Azure.AzureVMGroups.VMRole.QuorumStartingImageName -ne $null)
    {
        $config.Azure.AzureVMGroups.VMRole.QuorumStartingImageName = (GetLatestImage "Windows Server 2008 R2 SP1")
    }
    foreach($serviceAccount in $config.Azure.ServiceAccounts.ServiceAccount)
    {
        if(($serviceAccount.Type -eq "WindowsLocal") -or ($serviceAccount.Type -eq "SQL"))
        {
           $serviceAccount.UserName = $adminAccount
        }
        else #domain account
        {
          $serviceAccount.UserName = "$domain\$adminAccount"
        }
        $serviceAccount.Password = $password
    }

    $config.Azure.SQLCluster.InstallerDomainUsername = "$domain\$adminAccount"
    $config.Azure.SQLCluster.InstallerDatabaseUserName = $adminAccount

    if($config.Azure.AzureVMGroups.VMRole.HighAvailabilityType -ne $null)
    {
        $config.Azure.SQLCluster.PrimaryServiceAccountName = "$domain\$adminAccount"
        $config.Azure.SQLCluster.SecondaryServiceAccountName = "$domain\$adminAccount"
    }
    $config.Save($configPathAutoGen)
    return $configPathAutoGen
}

function SetSharePointConfiguration
{
    param($configPath,$serviceName,$storageAccount,$subscription, $adminAccount, $password, $domain, $dnsDomain, $appPoolAccount, $appPoolPassword)
    $sp2013img = (GetLatestImage "SharePoint Server 2013 Trial")
    $configPathAutoGen = $configPath.Replace(".xml", "-AutoGen.xml")
    [xml] $config = gc $configPath
    $config.Azure.SubscriptionName = $subscription
    $config.Azure.ServiceName = $serviceName
    $config.Azure.StorageAccount = $storageAccount
    $config.Azure.Connections.ActiveDirectory.ServiceName = $serviceName
    $config.Azure.Connections.ActiveDirectory.Domain = $domain
    $config.Azure.Connections.ActiveDirectory.DnsDomain = $dnsdomain
    $config.Azure.Connections.ActiveDirectory.ServiceAccountName = "$domain\$adminAccount"
    $config.Azure.Connections.SQLServer.ServiceName = $serviceName
    $config.Azure.Connections.SQLServer.UserName = $adminAccount
    $config.Azure.SharePointFarm.FarmAdminUsername = "$domain\$adminAccount"
    $config.Azure.SharePointFarm.InstallerDomainUsername = "$domain\$adminAccount"
    $config.Azure.SharePointFarm.InstallerDatabaseUsername = $adminAccount
    $config.Azure.SharePointFarm.ApplicationPoolAccount = "$domain\$appPoolAccount"

    foreach($vmRole in $config.Azure.AzureVMGroups.VMRole)
    {
        $vmRole.StartingImageName = $sp2013Img
        $vmRole.AdminUserName = $adminAccount
    }
    foreach($serviceAccount in $config.Azure.ServiceAccounts.ServiceAccount)
    {
        if(($serviceAccount.Type -eq "WindowsLocal") -or ($serviceAccount.Type -eq "SQL"))
        {
           $serviceAccount.UserName = $adminAccount
           $serviceAccount.Password = $password
        }
        else #domain account
        {
           if($serviceAccount.Usage -ne $null -and $serviceAccount.Usage -eq "SPAppPool")
           {
              $serviceAccount.UserName = "$domain\$appPoolAccount"
              $serviceAccount.Password = $appPoolPassword
           }
           else
           {
              $serviceAccount.UserName = "$domain\$adminAccount"
              $serviceAccount.Password = $password
           }
        }
    }
    foreach($webApp in $config.Azure.SharePointFarm.WebApplications.WebApplication)
    {
        $webApp.Url = "http://$serviceName.cloudapp.net"
        $webApp.TopLevelSiteOwner = "$domain\$adminAccount"
    }
    $config.Save($configPathAutoGen)
    return $configPathAutoGen
}

function randomString ($length = 6)
{

    $digits = 48..57
    $letters = 65..90 + 97..122
    $rstring = get-random -count $length `
            -input ($digits + $letters) |
                    % -begin { $aa = $null } `
                    -process {$aa += [char]$_} `
                    -end {$aa}
    return $rstring.ToString().ToLower()
}

function GetLatestImage
{
   param($imageFamily)
   $images = Get-AzureVMImage | where { $_.ImageFamily -eq $imageFamily } | Sort-Object -Descending -Property PublishedDate
   return $images[0].ImageName
}

