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
. "$scriptFolder\SharedComponents\SharedFunctions.ps1"


Use-RunAs
Write-Host "Installing Active Directory using Configuration Template: $configFilePath"

$config = [xml](gc $configFilePath)

$dcScriptPath = (Join-Path -Path $scriptFolder -ChildPath 'AD\AD-DCDeploy.ps1')


# Provision VMs in each VM Group
foreach($VMRole in $config.Azure.AzureVMGroups.VMRole)
{
	$dataDisks = @()
	foreach($dataDiskEntry in $VMRole.DataDiskSizesInGB.Split(';'))
	{
		$dataDisks += @($dataDiskEntry)
	}
				
	if($VMRole.Name -eq 'DomainControllers')
	{		
		foreach($azureVm in $VMRole.AzureVM)
		{			
			
						
		$password = GetPasswordByUserName $VMRole.ServiceAccountName $config.Azure.ServiceAccounts.ServiceAccount
	
			$createDCArgumentList = @()
			$createDCArgumentList += ("-SubscriptionName", '$config.Azure.SubscriptionName')
			$createDCArgumentList += ("-StorageAccount", $config.Azure.StorageAccount)
			$createDCArgumentList += ("-DCLocation", '$config.Azure.Location')
			$createDCArgumentList += ("-AffinityGroupName", '$config.Azure.AffinityGroup')
			$createDCArgumentList += ("-VMName", '$azureVm.Name')
			$createDCArgumentList += ("-ServiceName", '$config.Azure.ServiceName')
			$createDCArgumentList += ("-AvailabilitySet", '$VMRole.AvailabilitySet')
			$createDCArgumentList += ("-Size", '$VMRole.VMSize')
			$createDCArgumentList += ("-ImageName", '$VMRole.StartingImageName ')
			$createDCArgumentList += ("-SubnetNames", '$VMRole.SubnetNames')
			$createDCArgumentList += ("-Password", '$password')
			$createDCArgumentList += ("-AdminUserName", '$VMRole.ServiceAccountName')			
			$createDCArgumentList += ("-VNetName", '$config.Azure.VNetName')
			$createDCArgumentList += ("-NetBiosDomainName", '$config.Azure.ActiveDirectory.Domain')	
			$createDCArgumentList += ("-DCInstallMode", '$azureVm.DCType')						
			$createDCArgumentList += ("-DnsDomain", '$config.Azure.ActiveDirectory.DnsDomain')
			$createDCArgumentList += ("-DataDisks", '(,$dataDisks)')
            $createDCArgumentList += ("-createVNET", '$config.Azure.AzureVNET.CreateVNET')
			
			Invoke-Expression ".'$dcScriptPath' $createDCArgumentList"    		             
		}
	}	
}

