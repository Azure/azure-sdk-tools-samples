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

Import-Module "C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1"

Function IsAdmin
{
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()` 
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") 
    
    return $IsAdmin
}


Function WaitForBoot()
{
    param($serviceName, $vmName)
    do
    {
        $vm = get-azurevm -ServiceName $serviceName -Name $vmName
        if($vm -eq $null)
        {
            Write-Host "WaitForBoot - could not connect to $serviceName - $vmName"
            return
        }
        if(($vm.InstanceStatus -eq "FailedStartingVM") -or ($vm.InstanceStatus -eq "ProvisioningFailed") -or ($vm.InstanceStatus -eq "ProvisioningTimeout"))
        {
            Write-Host "Provisioning of $vmName failed."
            return 
        }
        if($vm.InstanceStatus -eq "ReadyRole")
        {
            break
        }
        Write-Host "Waiting for $vmName to boot"
        Start-Sleep 30 
    
    }while($true)
}


Function Use-RunAs 
{    
    # Check if script is running as Adminstrator and if not use RunAs 
    # Use Check Switch to check if admin 
     
    param([Switch]$Check) 
     
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()` 
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") 
         
    if ($Check) { return $IsAdmin }     
 
    if ($MyInvocation.ScriptName -ne "") 
    {  
        if (-not $IsAdmin)  
        {  
            try 
            {  
                $arg = "-file `"$($MyInvocation.ScriptName)`"" 
                Start-Process "$psHome\powershell.exe" -Verb Runas -ArgumentList $arg -ErrorAction 'stop'  
            } 
            catch 
            { 
                Write-Warning "Error - Failed to restart script with runas"  
                break               
            } 
            exit # Quit this session of powershell 
        }  
    }  
    else  
    {  
        Write-Warning "Error - Script must be saved as a .ps1 file first"  
        break  
    }  
} 

Function GetPasswordKeyByUserName()
{
	param([string]$userName, $serviceAccountList)
	[bool]$found = $false
	foreach($serviceAccount in $serviceAccountList)
	{
		if($serviceAccount.UserName -eq $userName)
		{
			$serviceAccount.PasswordKey
			$found = $true
		}
	}
	if(-not $found)
	{
		Write ("User name {0} not found in service account list" -f $userName)
	}
}

Function GetPasswordByUserName()
{
	param([string]$userName, $serviceAccountList)
	[bool]$found = $false
	foreach($serviceAccount in $serviceAccountList)
	{
		if($serviceAccount.UserName -eq $userName)
		{
			$serviceAccount.Password
			$found = $true
			break
		}
	}
	if(-not $found)
	{
		Write ("User name {0} not found in service account list" -f $userName)
	}
}

Function GetPasswordFromList()
{
	param([string]$passwordKey, $passwordList)
	[bool]$found = $false
	foreach($listedPassword in $passwordList)
	{
		if($listedPassword.Key -eq $passwordKey)
		{
			$listedPassword.Value
			$found = $true
		}
	}
	if(-not $found)
	{
		Write ("Password key {0} is not found in password list" -f $passwordKey)
	}
}


Function CreateDomainJoinedAzureVmIfNotExists()
{
	param([string]$serviceName, [string]$vmName, [string] $size, [string]$imageName, [string]$availabilitySetName, [string[]] $dataDisks,
	[string]$vnetName, [string]$subnetNames,[string]$affinityGroup, [string]$adminUsername, [string]$adminPassword, 
	[string] $domainDnsName, [string] $domainInstallerUsername, [string] $domainInstallerPassword)	# Create VM if one with the specified name doesn't exist
	$existingVm = Get-AzureVM -ServiceName $serviceName -Name $vmName
	if($existingVm -eq $null)
	{
	  Write-Host "Creating VM..."
	  $domainInstallerInfo = $domainInstallerUsername.Split('\')
	  $domainName = $domainInstallerInfo[0]
	  $domainUsername = $domainInstallerInfo[1]
	  $vmConfig = New-AzureVMConfig -Name $vmName -InstanceSize $size -ImageName $imageName -AvailabilitySetName $availabilitySetName | `
	  Add-AzureProvisioningConfig -WindowsDomain -Password $adminPassword -AdminUsername $adminUserName -JoinDomain $domainDnsName `
	  -Domain $domainName -DomainUserName $domainUsername -DomainPassword $domainInstallerPassword | Set-AzureSubnet -SubnetNames $subnetNames
	  
	  for($i=0; $i -lt $dataDisks.Count; $i++)
	  {
	  	$fields = $dataDisks[$i].Split(':')
		$dataDiskLabel = [string] $fields[0]
	  	$dataDiskSize = [string] $fields[1]
	  	Write-Host ("Adding disk {0} with size {1}" -f $dataDiskLabel, $dataDiskSize)	
		
		#Add Data Disk to the newly created VM
		$vmConfig | Add-AzureDataDisk -CreateNew -DiskSizeInGB $dataDiskSize -DiskLabel $dataDiskSize -LUN $i
	  }

	  foreach($ep in $azureVm.Endpoint)
      {
        if($ep -ne $null)
        {
            if($ep.LBSetName -ne "")
            {
                Write-Host "Adding Load Balanced Endpoint"
                Add-AzureEndpoint -VM $vmConfig -Name $ep.Name -Protocol $ep.Protocol -LocalPort $ep.LocalPort -PublicPort $ep.PublicPort -LBSetName $ep.LBSetName -ProbeProtocol $ep.ProbeProtocol -ProbePath $ep.ProbePath -ProbePort $ep.ProbePort 
	        }
            else
            {
                Write-Host "Adding Endpoint"
                Add-AzureEndpoint -VM $vmConfig -Name $ep.Name -Protocol $ep.Protocol -LocalPort $ep.LocalPort -PublicPort $ep.PublicPort 
            }
        }
      }		  

      $existingService = Get-AzureService -ServiceName $serviceName -ErrorAction SilentlyContinue
      if($existingService -eq $null) 
	  {
		  $vmConfig | New-AzureVM -ServiceName $serviceName -AffinityGroup $affinityGroup -VNetName $vnetName -WaitForBoot -Verbose
	  }
	  else
	  {
		  $vmConfig | New-AzureVM -ServiceName $serviceName -WaitForBoot -Verbose	  	
	  }

	  Write-Host "VM created."
	  InstallWinRMCertificateForVM $serviceName $vmName
      Write-Host "Pausing for Services to Start"
      Start-Sleep 300 
	}
	else
	{
	  Write-Host ("VM with Service Name {0} and Name {1} already exists." -f $serviceName, $vmName)
	}
}

Function EnableCredSSPServerIfNotEnabledBackwardCompatible()
{
param([string] $serviceName, [string] $vmName, [string] $adminUser, [string] $adminPassword)
	$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName
	$adminCredential = new-object pscredential($adminUser, (ConvertTo-SecureString $adminPassword -AsPlainText -Force))
    $maxRetry = 5
    For($retry = 0; $retry -le $maxRetry; $retry++)
    {
        Try
        {
	        Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $adminCredential -Port $uris[0].Port -UseSSL `
		        -ArgumentList $adminUser, $adminPassword -ScriptBlock {
		        param([string] $adminUser, [string] $adminPassword)
		        Set-ExecutionPolicy Unrestricted -Force
		        $is2012 = [Environment]::OSVersion.Version -ge (new-object 'Version' 6,2,9200,0)
		        if($is2012)
		        {
			        $line = winrm g winrm/config/service/auth | Where-Object {$_.Contains('CredSSP = true')}
			        $isCredSSPServerEnabled = -not [string]::IsNullOrEmpty($line)
			        if(-not $isCredSSPServerEnabled)
			        {
			            Write-Host "Enabling CredSSP Server..."
				        winrm s winrm/config/service/auth '@{CredSSP="true"}'
				        Write-Host "CredSSP Server is enabled."
			        }
			        else
			        {
				        Write-Host "CredSSP Server is already enabled."
			        }
		        }
		        else
		        {
			        schtasks /CREATE /TN "EnableCredSSP" /SC ONCE /SD 01/01/2020 /ST 00:00:00 /RL HIGHEST /RU $adminUser /RP $adminPassword /TR "winrm set winrm/config/service/auth @{CredSSP=\""True\""}" /F
			        schtasks /RUN /I /TN "EnableCredSSP"
		        }
	        }
            break
        }
	    Catch [System.Exception]
	    {
		    Write-Host "Error - retrying..."
		    Start-Sleep 30
	    }
    }
    Write-Host "Pausing to Allow CredSSP Scheduled Task to Execute on $vmName"
    Start-Sleep 30
}

Function EnableCredSSPServerIfNotEnabled()
{
param([string] $serviceName, [string] $vmName, [Management.Automation.PSCredential] $adminCredential)
	$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName
    $maxRetry = 5
    For($retry = 0; $retry -le $maxRetry; $retry++)
    {
        Try
        {
	        Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $adminCredential -Port $uris[0].Port -UseSSL `
		        -ScriptBlock {
		        Set-ExecutionPolicy Unrestricted -Force
		        $line = winrm g winrm/config/service/auth | Where-Object {$_.Contains('CredSSP = true')}
		        $isCredSSPServerEnabled = -not [string]::IsNullOrEmpty($line)
		        if(-not $isCredSSPServerEnabled)
		        {
		            Write-Host "Enabling CredSSP Server..."
			        winrm s winrm/config/service/auth '@{CredSSP="true"}'
			        Write-Host "CredSSP Server is enabled."
		        }
		        else
		        {
			        Write-Host "CredSSP Server is already enabled."
		        }
	        }
            break
        }
	    Catch [System.Exception]
	    {
		    Write-Host "Error - retrying..."
		    Start-Sleep 30
	    }
    }
    Write-Host "Pausing to Allow CredSSP to be enabled on $vmName"
    Start-Sleep 30
}

Function InstallWinRMCertificateForVM()
{
param([string] $serviceName, [string] $vmName)
    Write-Host "Installing WinRM Certificate for remote access: $serviceName $vmName"
	$WinRMCert = (Get-AzureVM -ServiceName $serviceName -Name $vmName | select -ExpandProperty vm).DefaultWinRMCertificateThumbprint
	$AzureX509cert = Get-AzureCertificate -ServiceName $serviceName -Thumbprint $WinRMCert -ThumbprintAlgorithm sha1

	$certTempFile = [IO.Path]::GetTempFileName()
	$AzureX509cert.Data | Out-File $certTempFile

	# Target The Cert That Needs To Be Imported
	$CertToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certTempFile

	$store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
	$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
	$store.Add($CertToImport)
	$store.Close()
	
	Remove-Item $certTempFile
}

Function FormatDisk()
{
	Param(
	[string]
	$serviceName,
	[string]
	$vmName,
	[string]
	$adminUserName,
	[string]
	$password
	)

	################## Function execution begin ###########

	#Get the hosted service WinRM Uri
	$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName

	$secPassword = ConvertTo-SecureString $password -AsPlainText -Force
	$credential = New-Object System.Management.Automation.PSCredential($adminUserName, $secPassword)

    $maxRetry = 5
    For($retry = 0; $retry -le $maxRetry; $retry++)
    {
        Try
        {
	        #Create a new remote ps session and pass in the scrip block to be executed
	        $session = New-PSSession -ComputerName $uris[0].DnsSafeHost -Credential $credential -Port $uris[0].Port -UseSSL 
	        Invoke-Command -Session $session -Scriptblock {
		
		        Set-ExecutionPolicy Unrestricted -Force

		        $drives = gwmi Win32_diskdrive
		        $scriptDisk = $Null
		        $script = $Null
		
		        #Iterate through all drives to find the uninitialized disk
		        foreach ($disk in $drives){
	    	        if ($disk.Partitions -eq "0"){
	                $driveNumber = $disk.DeviceID -replace '[\\\\\.\\physicaldrive]',''        
$script = @"
select disk $driveNumber
online disk noerr
attributes disk clear readonly noerr
create partition primary noerr
format quick
"@
			        }
			        $driveNumber = $Null
			        $scriptDisk += $script + "`n"
		        }
		        #output diskpart script
		        $scriptDisk | Out-File -Encoding ASCII -FilePath "c:\Diskpart.txt" 
		        #execute diskpart.exe with the diskpart script as input
		        diskpart.exe /s c:\Diskpart.txt

		        #assign letters and labels to initilized physical drives
		        $volumes = gwmi Win32_volume | where {$_.BootVolume -ne $True -and $_.SystemVolume -ne $True -and $_.DriveType -eq "3"}
		        $letters = 68..89 | ForEach-Object { ([char]$_)+":" }
		        $freeletters = $letters | Where-Object { 
	  		        (New-Object System.IO.DriveInfo($_)).DriveType -eq 'NoRootDirectory'
		        }
		        foreach ($volume in $volumes){
	    	        if ($volume.DriveLetter -eq $Null){
	        	        mountvol $freeletters[0] $volume.DeviceID
	    	        }
		        $freeletters = $letters | Where-Object { 
	    	        (New-Object System.IO.DriveInfo($_)).DriveType -eq 'NoRootDirectory'
		        }
		        }
	        }
	        #exit RPS session
	        Remove-PSSession $session
            break
        }
        Catch [System.Exception]
	    {
		    Write-Host "Error - retrying..."
		    Start-Sleep 30
	    }
    }
	################## Function execution end #############
}

Function EnsureSPDatabasesInAvailabilityGroup()
{param(
[string] $spServerServiceName,
[string] $spServerName,
[string] $spInstallerDatabaseUsername,
[string] $spFarmDomainUsername,
[string] $sqlClusterServiceName,
[string] $sqlServerPrimary,
[string] $sqlServerSecondary,
[string] $installerDomainUsername,
[string] $installerDomainPassword,
[string] $availabilityGroup
)
	#Get the hosted service WinRM Uri
	$spuris = Get-AzureWinRMUri -ServiceName $spServerServiceName -Name $spServerName
	$uris = Get-AzureWinRMUri -ServiceName $sqlClusterServiceName -Name $sqlServerPrimary
	$uris2 = Get-AzureWinRMUri -ServiceName $SqlClusterServiceName -Name $sqlServerSecondary

	$secPassword = ConvertTo-SecureString $installerDomainPassword -AsPlainText -Force
	$credential = New-Object System.Management.Automation.PSCredential($installerDomainUsername, $secPassword)

	$configdb, $cadb, $databases = Invoke-Command -ComputerName $spuris[0].DnsSafeHost -Authentication Credssp -Credential $credential -Port $spuris[0].Port -UseSSL `
	-ArgumentList $sqlServerSecondary -ScriptBlock {
	param([string]$failoverInstance)
		Add-PSSnapin Microsoft.SharePoint.PowerShell
		$configdb = (Get-SPFarm).Name
		$configdb
		$cawebapp=Get-SPWebApplication -includecentraladministration | where {$_.IsAdministrationWebApplication}
		$cadb = $cawebapp.ContentDatabases.Name
		$cadb
		Get-SPDatabase | ForEach-Object {
			$_.AddFailoverServiceInstance($failoverInstance) 
			$_.Update()
			Write-Host ("Updated database {0} with failover instance." -f $_.Name) 
			$_.Name
		}
	}
	
	#Back up SharePoint databases to backup share and add them to availability group if not already added
	Invoke-Command -ComputerName $uris[0].DnsSafeHost -Credential $credential -Authentication Credssp -Port $uris[0].Port -UseSSL `
	-ArgumentList $sqlServerPrimary, $sqlServerSecondary, $availabilityGroup, $spInstallerDatabaseUsername, $spFarmDomainUsername, $configdb, $cadb, $databases -ScriptBlock {
		param
		(
		[String]$serverPrimary, 
		[String]$serverSecondary, 
		[String]$ag,
		[String]$spdbaccess,
		[String]$spfarm,
		[String]$configdb,
		[String]$cadb,
		[String[]] $databases,
		[String]$backupShare = "\\$serverPrimary\backup"
		)
		$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, $timeoutsec

		Set-ExecutionPolicy RemoteSigned -Force
		Import-Module "sqlps" -DisableNameChecking

		Invoke-Sqlcmd -Query "ALTER DATABASE UPA1_PROFILE SET RECOVERY FULL"
		Invoke-Sqlcmd -Query "ALTER DATABASE UPA1_SOCIAL SET RECOVERY FULL"
		Invoke-Sqlcmd -Query "ALTER DATABASE UPA1_SYNC SET RECOVERY FULL"
		Invoke-Sqlcmd -Query "ALTER DATABASE Search15_AdminDB SET RECOVERY FULL"
        Invoke-Sqlcmd -Query "ALTER DATABASE Search15_AdminDB_AnalyticsReportingStore SET RECOVERY FULL"
        Invoke-Sqlcmd -Query "ALTER DATABASE Search15_AdminDB_CrawlStore SET RECOVERY FULL"
        Invoke-Sqlcmd -Query "ALTER DATABASE Search15_AdminDB_LinksStore SET RECOVERY FULL"
        Invoke-Sqlcmd -Query "ALTER DATABASE WSS_UsageApplication SET RECOVERY FULL"

		$dbsInAvailabilityGroup = dir "SQLSERVER:\SQL\$serverPrimary\Default\AvailabilityGroups\$ag\AvailabilityDatabases" | ForEach-Object {$_.Name}
		foreach($db in $databases)
		{
			Backup-SqlDatabase -Database $db -BackupFile "$backupShare\$db.bak" -ServerInstance $serverPrimary `
			-Initialize
			Backup-SqlDatabase -Database $db -BackupFile "$backupShare\$db.log" -ServerInstance $serverPrimary `
			-BackupAction Log -Initialize
			Write-Host ("Database {0} backed up to {1}." -f $db, $backupShare)
			
			if(($dbsInAvailabilityGroup | Where-Object {$_ -eq $db}) -eq $null)
			{
				Add-SqlAvailabilityDatabase -Path "SQLSERVER:\SQL\$serverPrimary\Default\AvailabilityGroups\$ag" -Database $db
				Write-Host ("Database {0} added to Availability Group {1}." -f $db, $ag)
			}
		}
	}
	
	#Restore SharePoint each database from backup folder if it doesn't already exist in availability group
	#Add db access account to db_owner role of SharePoint config db and CA content db
	#Add spfarm to all other content dbs
	Invoke-Command -ComputerName $uris2[0].DnsSafeHost -Authentication Credssp -Credential $credential -Port $uris2[0].Port -UseSSL `
	-ArgumentList  $sqlServerPrimary, $sqlServerSecondary, $availabilityGroup, $spInstallerDatabaseUsername, $spFarmDomainUsername, $configdb, $cadb, $databases {
		param
		(
		[String]$serverPrimary, 
		[String]$serverSecondary, 
		[String]$ag,
		[String]$spdbaccess,
		[String]$spfarm,
		[String]$configdb,
		[String]$cadb,
		[String[]]$databases, 
		[String]$backupShare = "\\$serverPrimary\backup"
		)

		Set-ExecutionPolicy RemoteSigned -Force
		Import-Module "sqlps" -DisableNameChecking

		$dbsInAvailabilityGroup = dir "SQLSERVER:\SQL\$serverSecondary\Default\AvailabilityGroups\$ag\AvailabilityDatabases" `
		| Where-Object {$_.IsJoined} | ForEach-Object {$_.Name}
		foreach($db in $databases)
		{
			if(($dbsInAvailabilityGroup | Where-Object {$_ -eq $db}) -eq $null)
			{
				Restore-SqlDatabase -Database $db -BackupFile "$backupShare\$db.bak" -ServerInstance $serverSecondary `
				-NoRecovery -ReplaceDatabase
				Restore-SqlDatabase -Database $db -BackupFile "$backupShare\$db.log" -ServerInstance $serverSecondary `
				-RestoreAction Log -NoRecovery
				Write-Host ("Database {0} restored from {1}." -f $db, $backupShare)
				
				Add-SqlAvailabilityDatabase -Path "SQLSERVER:\SQL\$serverSecondary\Default\AvailabilityGroups\$ag" -Database $db
				Write-Host ("Database {0} added to Availability Group {1}." -f $db, $ag)
			}
		}
		
		Start-Sleep -Seconds 120
		Switch-SqlAvailabilityGroup -Path "SQLSERVER:\SQL\$serverSecondary\Default\AvailabilityGroups\$ag"
		Write-Host ("Failed over availability group {0} to instance {1}." -f $ag, $serverSecondary)

		foreach($db in $databases)
		{
			Invoke-SqlCmd ("use {0}; create user [{1}] from login [{1}]; alter role db_owner add member [{1}]" -f $db, $spdbaccess)
			Write-Host ("{0} added to db_owner role for database {1}." -f $spdbaccess, $db)
		}

		Start-Sleep -Seconds 120
		Switch-SqlAvailabilityGroup -Path "SQLSERVER:\SQL\$serverPrimary\Default\AvailabilityGroups\$ag"
		Write-Host ("Failed over availability group {0} to instance {1}." -f $ag, $serverPrimary)
	}
}
