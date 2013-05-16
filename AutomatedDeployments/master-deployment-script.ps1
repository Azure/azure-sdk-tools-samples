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

cls

$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptFolder\SharedComponents\sharedfunctions.ps1"
. "$scriptFolder\SharedComponents\autoconfigure.ps1"

if((IsAdmin) -eq $false)
{
    Write-Host "Must run elevated."
   # return
}


Write-Host "Starting Deployment $d"


## Parameters
## -TemplateName - Required -  (SingleVMs or HighlyAvailable)
## -Location - Required - Data Center location to create resources in. (Get-AzureLocation | Select DisplayName)
## -ServiceName - Optional - Cloud Service name for VMs. Will be created (name generated automatically if not specified)
## -ScriptFolder - path to configuration files 
## -SubscriptionName - Optional - name of your subscription as configured in PowerShell. Uses Get-AzureSubscription -Current if not specified.
## -StorageAccountName - Optional - name of the storage account to use. One is created if not specified. Must be in the same location as -Location.
## -ServicePassword - Optional - password for service accounts for AD/SQL/SharePoint - randomly created if not specified 
## -adminAccount - Optional - user name that will be created for the deployment (AD and Local account will be created) - default spadmin
## -domain - Optional - netbios domain name - default corp
## -dnsDomain - Optional - FQDN - default corp.contoso.com
## -configOnly - optional - pass if you want to create the configuration files but not run the deployment scripts. Note: Will create a storage account if one is not specified.
AutoConfigure -TemplateName "SingleVMs" -Location "West US" -ScriptFolder $scriptFolder -configOnly $true -Domain "mydom" -DnsDomain "mydom.fabrikam.com" -storageAccountName "spstorageps"




Write-Host "End Deployment $d"
