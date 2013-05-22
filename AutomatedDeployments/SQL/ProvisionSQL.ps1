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


$sqlScriptPath = (Join-Path -Path $scriptFolder -ChildPath 'SQL\ProvisionSqlVm.ps1')
[string]$sqlServerName = [string]::Empty

. "$scriptFolder\SharedComponents\SharedFunctions.ps1"

Use-RunAs

Write-Host "Installing SQL Server using Configuration Template: $configFilePath"

Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1'
Select-AzureSubscription $config.Azure.SubscriptionName
Set-AzureSubscription $config.Azure.SubscriptionName -CurrentStorageAccount $config.Azure.StorageAccount

$dcServiceName = $config.Azure.Connections.ActiveDirectory.ServiceName
$dcVmName = $config.Azure.Connections.ActiveDirectory.DomainControllerVM
$domainInstallUserName = $config.Azure.Connections.ActiveDirectory.ServiceAccountName
$password = GetPasswordByUserName $domainInstallUserName $config.Azure.ServiceAccounts.ServiceAccount

#Get the ConfigureServiceAccounts.ps1 script path
$ConfigureServiceAccountsScriptPath = (Join-Path -Path $scriptFolder -ChildPath "SQL\ConfigureServiceAccounts.ps1")

#Add AD Accounts
foreach($sqlac in $config.Azure.ServiceAccounts.ServiceAccount) {
	if($sqlac.UserName.Contains('\') -and ([string]::IsNullOrEmpty($sqlac.Create) -or (-not $sqlac.Create.Equals('No'))))
	{
		$sqlacUname = $sqlac.UserName.Split('\')[1]		
		$sqlacPassword = GetPasswordByUserName $sqlac.UserName $config.Azure.ServiceAccounts.ServiceAccount

		
		#fill in the argument list
		$configureServiceAccountsArgumentList = @()
		$configureServiceAccountsArgumentList += ("-VMName",'$dcVmName')
		$configureServiceAccountsArgumentList += ("-ServiceName",'$dcServiceName')
		$configureServiceAccountsArgumentList += ("-OuName",'ServiceAccounts')
		$configureServiceAccountsArgumentList += ("-ADUserName",'$sqlacUname')
		$configureServiceAccountsArgumentList += ("-SamAccountName",'$sqlacUname')
		$configureServiceAccountsArgumentList += ("-DisplayName",'$sqlacUname')
		$configureServiceAccountsArgumentList += ("-AccountPassword",'$sqlacPassword')
		$configureServiceAccountsArgumentList += ("-AdminUserName",'$domainInstallUserName')
		$configureServiceAccountsArgumentList += ("-Password",'$password')
		
		#Invoke Configure DC with arguments
		Invoke-Expression ". '$ConfigureServiceAccountsScriptPath' $configureServiceAccountsArgumentList"
	}
}

# Provision VMs in each VM Group
foreach($vmRole in $config.Azure.AzureVMGroups.VMRole)
{
	if($vmRole.Name -eq 'SQLServers')
	{
		$subnetNames = @($vmRole.SubnetNames)
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
			
			$defaultSqlBackupFolder = ''

			$adminUsername = $vmRole.ServiceAccountName
			$adminPassword = GetPasswordByUserName $VMRole.ServiceAccountName $config.Azure.ServiceAccounts.ServiceAccount
			 
			$domainDnsName = $config.Azure.Connections.ActiveDirectory.DnsDomain
			$installerDomainUsername = $config.Azure.SQLCluster.InstallerDomainUsername			
			$installerDomainPassword = GetPasswordByUserName $installerDomainUsername $config.Azure.ServiceAccounts.ServiceAccount
			
			$installerDatabaseUsername = $config.Azure.SQLCluster.InstallerDatabaseUsername			
			$installerDatabasePassword = GetPasswordByUserName $installerDatabaseUsername $config.Azure.ServiceAccounts.ServiceAccount
			$vnetName = $config.Azure.VNetName 
            $affinityGroup = $config.Azure.AffinityGroup
			$imageName = $vmRole.StartingImageName
            $vmSize = $vmRole.VMSize
			if($azureVm.Type -ne $null -and $azureVm.Type.Equals('QUORUM'))
			{
				$imageName = $vmRole.QuorumStartingImageName
                $vmSize = $vmRole.QuorumVMSize
			}
		

			& $sqlScriptPath -subscriptionName $config.Azure.SubscriptionName -storageAccount $config.Azure.StorageAccount -subnetNames $subnetNames `
			-vmName $azureVm.Name -serviceName $config.Azure.ServiceName -vmSize $vmSize -vmType $azureVm.Type -imageName $imageName -availabilitySetName $availabilitySetName `
			-dataDisks $dataDisks -defaultSqlDataFolder $vmRole.DefaultSQLDataFolder -defaultSqlLogFolder $vmRole.DefaultSQLLogFolder `
			-highAvailabilityType $vmRole.HighAvailabilityType -defaultSqlBackupFolder $defaultSqlBackupFolder `
			-adminUsername $adminUsername -adminPassword $adminPassword -vnetName $vnetName -AffinityGroup $affinityGroup -domainDnsName $domainDnsName -installerDomainUsername $installerDomainUsername `
			-installerDomainPassword $installerDomainPassword -installerDatabaseUsername $installerDatabaseUsername -installerDatabasePassword $installerDatabasePassword

			if(-not [string]::IsNullOrEmpty($config.Azure.ServiceName))
			{
				# next VM will join the same group
				$affinityGroup = ''
			}

			# Create cluster and availability group after all servers are added PRIMARY is last
			if ($azureVm.Type -eq 'PRIMARY')
				{
					# Cluster and SQL AG Creation part Begin. Pre-req Quorum and Secondary are already created and Domain joined

					# Get the Primary Secondary and Quorum Servernames from Config
					$SQLServerPrimary = ''
					$SQLServerSecondary = ''
					$SQLServerQuorum = ''

					foreach($vmRole in $config.Azure.AzureVMGroups.VMRole) {
						if($vmRole.Name -eq 'SQLServers')
							{
						foreach($azureVm in $vmRole.AzureVM) {
							if($azureVm.Type -eq 'QUORUM') {
								$SQLServerQuorum = $azureVm.Name
									}
									elseif($azureVm.Type -eq 'SECONDARY')
									{
								$SQLServerSecondary = $azureVm.Name
									}
									elseif($azureVm.Type -eq 'PRIMARY')
									{
								$SQLServerPrimary = $azureVm.Name
									}
								}
							}
						}
	
						$clusterName = $config.Azure.SQLCluster.Name
						$db = $config.Azure.SQLCluster.FailOverTestDBName
						$ag = $config.Azure.SQLCluster.SQLAvailabilityGroup
	
				#Get the hosted service WinRM Uri
				$uris = Get-AzureWinRMUri -ServiceName $config.Azure.ServiceName -Name $SQLServerPrimary
				$uris2 = Get-AzureWinRMUri -ServiceName $config.Azure.ServiceName -Name $SQLServerSecondary

				$secPassword = ConvertTo-SecureString $installerDomainPassword -AsPlainText -Force
				$credential = New-Object System.Management.Automation.PSCredential($installerDomainUsername, $secPassword)
				$secLocalPassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
				$localCredential = New-Object System.Management.Automation.PSCredential("$vmName\$adminUsername", $secLocalPassword)

				#Get the CreateAzureFailoverCluster.ps1 script path
				$createAzureFailOverClusterScriptPath = (Join-Path -Path $scriptFolder -ChildPath "SQL\CreateAzureFailoverCluster.ps1")
				$createAzureFailOverClusterScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($createAzureFailOverClusterScriptPath)
				$cNode = @($SQLServerPrimary, $SQLServerSecondary, $SQLServerQuorum)
					
				$SQLSvcActPrim = $config.Azure.SQLCluster.PrimaryServiceAccountName
				$commonSvcPwd = GetPasswordByUserName $SQLSvcActPrim $config.Azure.ServiceAccounts.ServiceAccount
				$SQLSvcActSec = $config.Azure.SQLCluster.SecondaryServiceAccountName
				#Set Service Account and restart SQL Service on both Primary and Secondary

				Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $credential -Port $uris[0].Port -UseSSL -Authentication Credssp `
				-ArgumentList $SQLServerPrimary, $SQLServerSecondary, $SQLServerQuorum, $SQLSvcActPrim, $SQLSvcActSec, $commonSvcPwd, $clusterName, $ag, $db `
				-ScriptBlock {
					param
					(
					[String]$serverPrimary, 
					[String]$serverSecondary, 
					[String]$serverQuorum, 
					[String]$SQLSvcActPrim, 
					[String]$SQLSvcActSec, 
					[String]$commonSvcPwd, 
					[String]$clusterName, 
					[String]$ag,
					[String]$db, 
					[String]$backupShare = "\\$serverPrimary\backup", 
					[String]$quorumShare = "\\$serverPrimary\quorum", 
					[Int32]$timeoutsec = 30
					)
					$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, $timeoutsec
	    
					Set-ExecutionPolicy RemoteSigned -Force
					Import-Module "sqlps" -DisableNameChecking

					$wmi1 = new-object ("Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer") localhost
					$wmi1.services | where {$_.Type -eq 'SqlServer'} | foreach{$_.SetServiceAccount($SQLSvcActPrim,$commonSvcPwd)}
					$svc1 = Get-Service -ComputerName $serverPrimary -Name 'MSSQLSERVER'
					$svc1.Stop()
					$svc1.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped,$timeout)
					$svc1.Start(); 
					$svc1.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout)
				}
				
				Invoke-Command -ComputerName $uris2[0].DnsSafeHost -Credential $credential -Port $uris2[0].Port -UseSSL -Authentication Credssp `
				-ArgumentList  $SQLServerPrimary, $SQLServerSecondary, $SQLServerQuorum, $SQLSvcActPrim, $SQLSvcActSec, $commonSvcPwd, $clusterName, $ag, $db `
				-ScriptBlock {
					param
					(
					[String]$serverPrimary, 
					[String]$serverSecondary, 
					[String]$serverQuorum, 
					[String]$SQLSvcActPrim, 
					[String]$SQLSvcActSec, 
					[String]$commonSvcPwd, 
					[String]$clusterName, 
					[String]$ag,
					[String]$db, 
					[String]$backupShare = "\\$serverPrimary\backup", 
					[String]$quorumShare = "\\$serverPrimary\quorum", 
					[Int32]$timeoutsec = 30
					)
					$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, $timeoutsec
	    
					Set-ExecutionPolicy RemoteSigned -Force
					Import-Module "sqlps" -DisableNameChecking

					$wmi2 = new-object ("Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer") $serverSecondary
					$wmi2.services | where {$_.Type -eq 'SqlServer'} | foreach{$_.SetServiceAccount($SQLSvcActSec,$commonSvcPwd)}
					$svc2 = Get-Service -ComputerName $serverSecondary -Name 'MSSQLSERVER'
					$svc2.Stop()
					$svc2.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped,$timeout)
					$svc2.Start(); 
					$svc2.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout)

					Set-ExecutionPolicy Unrestricted -Force
				}
				
				#Invoke the CreateAzureFailoverCluster script with arguments
				Write-Host $createAzureFailOverClusterScriptPath
				$session = New-PSSession -ComputerName $uris[0].DnsSafeHost -Authentication Credssp -Credential $credential -Port $uris[0].Port -UseSSL 
				Invoke-Command -Session $session -ArgumentList $clusterName, $cNode `
				-FilePath $createAzureFailOverClusterScriptPath
				#exit RPS session
				Remove-PSSession $session
              
                $domainDnsName = $config.Azure.Connections.ActiveDirectory.DnsDomain
                Write-Host "domainDnsName $domainDnsName"
				Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $credential -Port $uris[0].Port -UseSSL -Authentication Credssp `
				-ArgumentList $SQLServerPrimary, $SQLServerSecondary, $SQLServerQuorum, $SQLSvcActPrim, $SQLSvcActSec, $commonSvcPwd, $clusterName, $ag, $db, $domainDnsName -ScriptBlock {
					param
					(
					[String]$serverPrimary, 
					[String]$serverSecondary, 
					[String]$serverQuorum, 
					[String]$SQLSvcActPrim, 
					[String]$SQLSvcActSec, 
					[String]$commonSvcPwd, 
					[String]$clusterName, 
					[String]$ag,
					[String]$db, 
                    [String]$dnsDomain,
                    [String]$backupShare = "\\$serverPrimary\backup", 
					[String]$quorumShare = "\\$serverPrimary\quorum", 
					[Int32]$timeoutsec = 30
                    
					)

                    
					$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, $timeoutsec
	    
					Set-ExecutionPolicy RemoteSigned -Force
					Import-Module "sqlps" -DisableNameChecking

					Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\$serverPrimary\Default -Force

					$backup = "C:\backup"
					New-Item $backup -ItemType directory
					net share backup=$backup "/grant:$SQLSvcActPrim,FULL" "/grant:$SQLSvcActSec,FULL"
					icacls.exe "$backup" /grant:r ("$SQLSvcActPrim" + ":(OI)(CI)F") ("$SQLSvcActSec" + ":(OI)(CI)F") 

					Invoke-SqlCmd -Query "CREATE database $db"
					Backup-SqlDatabase -Database $db -BackupFile "$backupShare\db.bak" -ServerInstance $serverPrimary
					Backup-SqlDatabase -Database $db -BackupFile "$backupShare\db.log" -ServerInstance $serverPrimary -BackupAction Log

					$endpoint = (dir "SQLSERVER:\SQL\$serverPrimary\Default\endpoints") | Where-Object {$_.Name -eq 'MyMirroringEndPoint'}
					if($endpoint -eq $null)
					{
						$endpoint = 
						    New-SqlHadrEndpoint MyMirroringEndpoint `
						    -Port 5022 `
						    -Path "SQLSERVER:\SQL\$serverPrimary\Default"
					}
					Set-SqlHadrEndpoint `
					    -InputObject $endpoint `
					    -State "Started"


		            Invoke-Sqlcmd -ServerInstance $serverPrimary -Query `
		            "	    
                    IF Not EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$SQLSvcActSec')
                    BEGIN
		                CREATE LOGIN [$SQLSvcActSec] FROM WINDOWS
                    END      
                    "
					Invoke-SqlCmd -Query "GRANT CONNECT ON ENDPOINT::[MyMirroringEndpoint] TO [$SQLSvcActSec]" -ServerInstance $serverPrimary

                    $primaryEP = $serverPrimary + "." + $dnsDomain + ":5022"
                    $secondaryEP = $serverSecondary + "." + $dnsDomain + ":5022"
                    Write-Host "Creating SqlAvailabilityGroup on Endpoints TCP://$primaryEP and TCP://$secondaryEP"
                    
					$primaryReplica = 
					    New-SqlAvailabilityReplica `
					    -Name $serverPrimary `
					    -EndpointURL "TCP://$primaryEP" `
					    -AvailabilityMode "SynchronousCommit" `
					    -FailoverMode "Automatic" `
					    -Version 11 `
					    -AsTemplate
					$secondaryReplica = 
					    New-SqlAvailabilityReplica `
					    -Name $serverSecondary `
					    -EndpointURL "TCP://$secondaryEP" `
					    -AvailabilityMode "SynchronousCommit" `
					    -FailoverMode "Automatic" `
					    -Version 11 `
					    -AsTemplate 
    
					New-SqlAvailabilityGroup -Name $ag -Path "SQLSERVER:\SQL\$serverPrimary\Default" -AvailabilityReplica @($primaryReplica, $secondaryReplica) -Database $db
				}
				
				Invoke-Command -ComputerName $uris2[0].DnsSafeHost -Credential $credential -Port $uris2[0].Port -UseSSL -Authentication Credssp `
				-ArgumentList  $SQLServerPrimary, $SQLServerSecondary, $SQLServerQuorum, $SQLSvcActPrim, $SQLSvcActSec, $commonSvcPwd, $clusterName, $ag, $db -ScriptBlock {
					param
					(
					[String]$serverPrimary, 
					[String]$serverSecondary, 
					[String]$serverQuorum, 
					[String]$SQLSvcActPrim, 
					[String]$SQLSvcActSec, 
					[String]$commonSvcPwd, 
					[String]$clusterName, 
					[String]$ag,
					[String]$db, 
					[String]$backupShare = "\\$serverPrimary\backup", 
					[String]$quorumShare = "\\$serverPrimary\quorum", 
					[Int32]$timeoutsec = 30
					)

					$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, $timeoutsec
	    
					Set-ExecutionPolicy RemoteSigned -Force
					Import-Module "sqlps" -DisableNameChecking

					$svc2 = Get-Service -ComputerName $serverSecondary -Name 'MSSQLSERVER'
					$svc2.Stop()
					$svc2.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped,$timeout)
					$svc2.Start(); 
					$svc2.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout)

					Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\$serverSecondary\Default -NoServiceRestart

					$svc2 = Get-Service -ComputerName $serverSecondary -Name 'MSSQLSERVER'
					$svc2.Stop()
					$svc2.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped,$timeout)
					$svc2.Start(); 
					$svc2.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout) 

					Restore-SqlDatabase -Database $db -BackupFile "$backupShare\db.bak" -ServerInstance $serverSecondary -NoRecovery
					Restore-SqlDatabase -Database $db -BackupFile "$backupShare\db.log" -ServerInstance $serverSecondary -RestoreAction Log -NoRecovery

					$endpoint = (dir "SQLSERVER:\SQL\$serverSecondary\Default\endpoints") | Where-Object {$_.Name -eq 'MyMirroringEndPoint'}
					if($endpoint -eq $null)
					{
						$endpoint = 
						    New-SqlHadrEndpoint MyMirroringEndpoint `
						    -Port 5022 `
						    -Path "SQLSERVER:\SQL\$serverSecondary\Default"
					}
					Set-SqlHadrEndpoint `
					    -InputObject $endpoint `
					    -State "Started"

		            Invoke-Sqlcmd -ServerInstance $serverSecondary -Query `
		            "	    
                    IF Not EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$SQLSvcActPrim')
                    BEGIN
		                CREATE LOGIN [$SQLSvcActPrim] FROM WINDOWS
                    END      
                    "
					Invoke-SqlCmd -Query "GRANT CONNECT ON ENDPOINT::[MyMirroringEndpoint] TO [$SQLSvcActPrim]" -ServerInstance $serverSecondary 

					Join-SqlAvailabilityGroup -Path "SQLSERVER:\SQL\$serverSecondary\Default" -Name $ag
					Add-SqlAvailabilityDatabase -Path "SQLSERVER:\SQL\$serverSecondary\Default\AvailabilityGroups\$ag" -Database $db

					Set-ExecutionPolicy Unrestricted -Force
				}
			}	
		}
	}
}
