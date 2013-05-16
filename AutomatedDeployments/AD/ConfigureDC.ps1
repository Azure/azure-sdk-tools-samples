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
$adminUserName,
[string]
$password,
[string]
$dcInstallMode,
[string]
$netBiosDomainName,
[string]
$domain
)

################## Script execution begin ###########

#Get the hosted service WinRM Uri
$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName

$secPassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($adminUserName, $secPassword)

#Create a new remote ps session and pass in the scrip block to be executed
$session = New-PSSession -ComputerName $uris[0].DnsSafeHost -Credential $credential -Port $uris[0].Port -UseSSL 
Invoke-Command -Session $session -Scriptblock {
		Param([string]$dcInstallMode,[string]$adminUserName,[string]$password,[string]$domain,[string]$netBiosDomainName)
		
		Set-ExecutionPolicy Unrestricted -Force	
		
		#initialize DCPromo/ADDSDeployment arguments
		$computer = $env:COMPUTERNAME
		$dcPromoAnswerFile = $Env:TEMP + '\dcpromo.ini'
		
		$locationNTDS = "F:\DATA"		
		$locationNTDSLogs = "F:\LOGS"	
		$locationSYSVOL = "F:\SYSVOL"		
				
		#Create output files
		[IO.Directory]::CreateDirectory($locationNTDSLogs) 
		[IO.Directory]::CreateDirectory($locationSYSVOL) 
		
	#check if server 2012
	$is2012 = [Environment]::OSVersion.Version -ge (new-object 'Version' 6,2,9200,0)
		
	if($is2012)
	{
		#use ADDSDeployment module		
		Write-Output "Running AD-DS Deployment module to install AD DS..."
		$locationNTDS = "F:\NTDS"
		
		#Create output file
		[IO.Directory]::CreateDirectory($locationNTDS) 
		
		#Add AD-DS Role
		Install-windowsfeature -name AD-Domain-Services –IncludeManagementTools -verbose
		
		Write-Output "DC Install mode is " $dcInstallMode
		if($dcInstallMode -eq "NewForest")
		{
			#Installing a new forest root domain
			Install-ADDSForest –DomainName $domain –DomainMode Win2012 –ForestMode Win2012 -Force -SafeModeAdministratorPassword (convertto-securestring $password -asplaintext -force) –DatabasePath $locationNTDS –SYSVOLPath $locationSYSVOL –LogPath $locationNTDSLogs -verbose
		}		
		elseif($dcInstallMode -eq "Replica")
		{
			#Installing a Replica domain
			$secPassword = ConvertTo-SecureString $password -AsPlainText -Force
			$domainCredential = New-Object System.Management.Automation.PSCredential("$domain\$adminUserName", $secPassword)
			Install-ADDSDomainController –Credential $domainCredential –DomainName $domain -Force -SafeModeAdministratorPassword (convertto-securestring $password -asplaintext -force) –DatabasePath $locationNTDS –SYSVOLPath $locationSYSVOL –LogPath $locationNTDSLogs -verbose
		}
		
		Write-Output "AD-DS Deployment completed..."
	}
	else
	{	
		#Create output file
		[IO.Directory]::CreateDirectory($locationNTDS) 
		
		#use DC Promo		
		Write-Output "Running DC promo to install AD DS..."
		#Reboot server after DCPromo completes
		$dcPromoReboot = "Yes"
		
		#Install Domain Controller as a DNS Server
		$dnsInstallSwitch = "Yes"
		
		#Import server manager module
		import-module servermanager	

if($dcInstallMode -eq "NewForest")
{
$dcPromoFile = @"
[DCINSTALL]
UserName=$adminUserName
Password=$password
InstallDNS=$dnsInstallSwitch
NewDomain=forest
NewDomainDNSName=$domain
DomainNetBiosName=$netBiosDomainName
ReplicaOrNewDomain=Domain
DomainLevel=4
DatabasePath=$locationNTDS 
LogPath=$locationNTDSLogs 
RebootOnCompletion=$dcPromoReboot
SYSVOLPath=$locationSYSVOL
SafeModeAdminPassword=$password
"@
}
elseif($dcInstallMode -eq "Replica")
{
$dcInstallType = "Replica"
$criticalReplication = "No"
$isGC = "Yes"
$dcPromoFile = @"
[DCINSTALL]
UserName=$adminUserName
UserDomain=$domain
Password=$password
InstallDNS=$dnsInstallSwitch
ReplicaOrNewDomain=$dcInstallType
ReplicaDomainDNSName=$domain
DatabasePath=$locationNTDS
LogPath=$locationNTDSLogs
SYSVOLPath=$locationSYSVOL
CriticalReplicationOnly=$criticalReplication
ConfirmGc=$isGC
RebootOnCompletion=$dcPromoReboot
SafeModeAdminPassword=$password
"@ 
}
		$dcPromoFile | out-file $dcPromoAnswerFile -force
		
		#run dcpromo with DCPromoFile argument
		dcpromo /unattend:$dcPromoAnswerFile 
		
		Write-Output "DC promo installation completed..."
	}
	
	

} -ArgumentList $dcInstallMode, $adminUserName, $password, $domain, $netBiosDomainName
#exit RPS session
Remove-PSSession $session

################## Script execution end #############