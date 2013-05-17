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

Param(
$vmName, 
$imageName, 
$size,
$subnetNames,
$adminUserName,
$password,
$serviceName,
$availabilitySet,
$vnetName,
$affinityGroup,
$dcInstallMode,
$domainJoin,
$domain,
$dataDisks
)

# Include script file for shared functions
$scriptFolder = Split-Path -parent $MyInvocation.MyCommand.Definition
. "$scriptFolder\..\SharedComponents\SharedFunctions.ps1"


################## Functions ##############################

#Function to create a Remote PowerShell enabled VM
#Should eventually be updated to use the method in SharedFunctions.ps1
function CreateVM
{	
	$vmConfig = New-AzureVMConfig -Name $vmName -InstanceSize $size -ImageName $imageName -AvailabilitySetName $availabilitySet | Set-AzureSubnet -SubnetNames $subnetNames
		
	for($i=0; $i -lt $dataDisks.Count; $i++)
	{
	  	$fields = $dataDisks[$i].Split(':')
		$dataDiskLabel = [string] $fields[0]
	  	$dataDiskSize = [string] $fields[1]
	  	Write-Host ("Adding disk {0} with size {1}" -f $dataDiskLabel, $dataDiskSize)	
		
		#Add Data Disk to the newly created VM
		$vmConfig | Add-AzureDataDisk -CreateNew -DiskSizeInGB $dataDiskSize -DiskLabel $dataDiskLabel -LUN $i
	}
	
	if($dcInstallMode -eq 'NewForest')
	{	
		$vmConfig | Add-AzureProvisioningConfig -Windows -Password $password -AdminUserName $adminUserName 
		#Create the Remote PS enabled Primary DC VM	
		New-AzureVM -ServiceName $serviceName -AffinityGroup $affinityGroup -VNetName $vnetName -VMs $vmConfig -WaitForBoot -Verbose
	}
	else
	{
		$vmConfig | Add-AzureProvisioningConfig -WindowsDomain -Password $password -AdminUserName $adminUserName -JoinDomain $domainjoin -Domain $domain -DomainPassword $password -DomainUserName $adminUserName 
		New-AzureVM -ServiceName $serviceName -VMs $vmConfig -WaitForBoot -Verbose
	}	

    InstallWinRMCertificateForVM $serviceName $vmName
    Write-Host "Pausing for Services to Start"
    Start-Sleep 300 

}

################## Functions ##############################


################## Script execution begin #################

#Call CreateVM
CreateVM

################## Script execution end ###################


