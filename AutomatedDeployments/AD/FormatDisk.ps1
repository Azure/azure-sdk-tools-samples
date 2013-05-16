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
$password
)

################## Script execution begin ###########

#Get the hosted service WinRM Uri
$uris = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName

$secPassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($adminUserName, $secPassword)

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

################## Script execution end #############