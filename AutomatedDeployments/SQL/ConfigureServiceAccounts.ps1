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
[string]
$vmName,
[string]
$serviceName,
[string]
$ouName,
[string]
$adUserName,
[string]
$samAccountName,
[string]
$displayName,
[string]
$accountPassword,
[string]
$adminUserName,
[string]
$password
)

################## Script execution begin ###########
#Select-AzureSubscription -SubscriptionName $SubscriptionName

#Get the hosted service WinRM Uri
$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName

$secPassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($adminUsername, $secPassword)

#Create a new remote ps session and pass in the scrip block to be executed
 Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $credential -Port $uris[0].Port -UseSSL -Scriptblock {
Param(
[string]
$ouName,
[string]
$adUserName,
[string]
$samAccountName,
[string]
$displayName,
[string]
$accountPassword
)

Set-ExecutionPolicy Unrestricted -Force

# Get the logged-on user's domain in DN form 
 $myDom = (get-addomain).distinguishedname 
 
# Build the full DN of the target OU 
 $ouDn = "OU=$ouName,$myDom" 
 
# Check if the target OU exists. If not, create it. 
 $ou = get-adorganizationalunit -Filter { name -eq $ouName } 
 if($ou -eq $null) 
 {New-ADOrganizationalUnit -Name $ouName -Path $myDom}  
else  
{write-host "The OU " $ou " already exists."} 
 
# Create users 
 New-ADUser –Name $adUserName –SamAccountName $samAccountName –DisplayName $displayName -Path $ouDn –Enabled $true –ChangePasswordAtLogon $false -AccountPassword (ConvertTo-SecureString $accountPassword -AsPlainText -force) -PassThru -verbose
 
 } -ArgumentList $ouName, $adUserName, $samAccountName, $displayName, $accountPassword

################## Script execution end #############