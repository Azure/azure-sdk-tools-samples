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
#The name of the Azure subscription to use
$SubscriptionName,
[string]
#The name of the VM to remote into
$VMName,
[string]
#The name of the service to remote into
$ServiceName,
[string]
#OU to be created
$OuName,
[string]
#AD User name
$ADUserName,
[string]
#SAM Account name
$SamAccountName,
[string]
#Display name of the user
$DisplayName,
[string]
#Password
$AccountPassword,
[string]
$AdminUserName,
[string]
$Password
)

################## Script execution begin ###########
Select-AzureSubscription -SubscriptionName $SubscriptionName

#Get the hosted service WinRM Uri
$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName

$secPassword = ConvertTo-SecureString $Password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($AdminUsername, $secPassword)

#Create a new remote ps session and pass in the scrip block to be executed
 Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $credential -Port $uris[0].Port -UseSSL -Scriptblock {
Param(
[string]
#OU to be created
$OuName,
[string]
#AD User name
$ADUserName,
[string]
#SAM Account name
$SamAccountName,
[string]
#Display name of the user
$DisplayName,
[string]
#Password
$AccountPassword
)

Set-ExecutionPolicy Unrestricted -Force

# Get the logged-on user's domain in DN form 
 $Mydom = (get-addomain).distinguishedname 
 
# Build the full DN of the target OU 
 $OuDn = "OU=$OuName,$Mydom" 
 
# Check if the target OU exists. If not, create it. 
 $OU = get-adorganizationalunit -Filter { name -eq $OuName } 
 if($OU -eq $null) 
 {New-ADOrganizationalUnit -Name $OuName -Path $Mydom}  
else  
{write-host "The OU " $OU " already exists."} 
 
 $user = Get-ADUser -Filter { Name -eq $adUserName }
 if($user -eq $null)
 {
    # Create users 
    New-ADUser -Name $ADUserName -SamAccountName $SamAccountName -DisplayName $DisplayName -Path $OuDn -Enabled $true -ChangePasswordAtLogon $false -AccountPassword (ConvertTo-SecureString $AccountPassword -AsPlainText -force) -PassThru -verbose
 }

 } -ArgumentList $OuName, $ADUserName, $SamAccountName, $DisplayName, $AccountPassword

################## Script execution end ##############
