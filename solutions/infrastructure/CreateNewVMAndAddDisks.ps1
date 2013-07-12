<#
.Synopsis
   Installs a WinRm certificate to the local store
.DESCRIPTION
   Gets the WinRM certificate from the VM on the specified service and installs it on the Current User's personal store.
.EXAMPLE
    Install-WinRmCertificate -ServiceName testservice -vmName testVm
.INPUTS
   None
.OUTPUTS
   Microsoft.WindowsAzure.Management.ServiceManagement.Model.OSImageContext
#>
function Install-WinRmCertificate($ServiceName, $VMName)
{
    $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName
    $winRmCertificateThumbprint = $vm.VM.DefaultWinRMCertificateThumbprint
 
    $winRmCertificate = Get-AzureCertificate -ServiceName $ServiceName -Thumbprint $winRmCertificateThumbprint -ThumbprintAlgorithm sha1

    $installedCert = Get-Item Cert:\CurrentUser\My\$winRmCertificateThumbprint -ErrorAction SilentlyContinue

    if ($installedCert -eq $null)
    {
        $certBytes = [System.Convert]::FromBase64String($winRmCertificate.Data)
        $x509Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate
        $x509Cert.Import($certBytes)
 
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
        $store.Open("ReadWrite")
        $store.Add($x509Cert)
        $store.Close()
    }
}

<#
.SYNOPSIS
  Creates a Virtual Machine with two data disks.
.DESCRIPTION
  Creates a Virtual Machine (small) configured with two data disks.  After the Virtual Machine is provisioned and running,
  the data disks are then formatted and have drive letters assigned.  User is prompted for credentials to use to provision
  the new Virtual Machine.
#>

# Retrieve with Get-AzureSubscription.
$subscriptionName = "[SUBSCRIPTION NAME]"

# Storage account to store image in.  Retrieve with Get-AzureStorageAccount.
$storageAccountName = "[STORAGE ACCOUNT NAME]"

# Cloud service name to deploy the VMs to.  Use New-AzureService to create if not already created. 
$serviceName = "[SERVICE NAME]"

# The name of the Virtual Machine to create.
$vmName = "[VM NAME]"

# Image name to create the Virtual Machine from.  Use Get-AzureVMImage for list of available images.
$imageName = "bd507d3a70934695bc2128e3e5a255ba__RightImage-Windows-2012-x64-v13.4.12.2"

# Disk size in GB
[Int32]$diskSizeInGB = 16

# Credential to access VMs
[PSCredential]$credential = Get-Credential

# Specify the storage account location to store the newly created VHDs
Set-AzureSubscription -SubscriptionName $subscriptionName -CurrentStorageAccount $storageAccountName

# Select the subscription to use for this script.
Select-AzureSubscription -SubscriptionName $subscriptionName

# Check if hosted service with $ServiceName exists
$existingService = Get-AzureService -ServiceName $ServiceName -ErrorAction SilentlyContinue

if ($existingService -eq $null)
{
    throw "Hosted service '" + $serviceName + "' does not exist."
}

# Configure the new Virtual Machine.
$userName = $credential.GetNetworkCredential().UserName
$password = $credential.GetNetworkCredential().Password
$vmConfig = New-AzureVMConfig -Name $vmName -InstanceSize Small -ImageName $imageName  |
            Add-AzureProvisioningConfig -Windows -AdminUsername $userName -Password $password |
            Add-AzureDataDisk -CreateNew -DiskSizeInGB $diskSizeInGB -DiskLabel "disk_0" -LUN 1 |
            Add-AzureDataDisk -CreateNew -DiskSizeInGB $diskSizeInGB -DiskLabel "disk_1" -LUN 2 

# Create the Virtual Machine and wait for it to boot.
New-AzureVM -ServiceName $serviceName -VMs $vmConfig -WaitForBoot

# Install a remote management certificate onto the Virtual Machine.
Install-WinRmCertificate -serviceName $serviceName -vmName $vmName

# Format data disks and assign drive letters.
$winRmUri = Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName
Invoke-Command -ConnectionUri $winRmUri.ToString() -Credential $credential -ScriptBlock {
    Get-Disk | 
    Where-Object PartitionStyle -eq "RAW" |
    Initialize-Disk -PartitionStyle MBR -PassThru |
    New-Partition -AssignDriveLetter -UseMaximumSize |
    Format-Volume -FileSystem NTFS -Confirm:$false
}


