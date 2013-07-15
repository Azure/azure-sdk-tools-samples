<#
.SYNOPSIS
  Creates a Virtual Machine with two data disks.
.DESCRIPTION
  Creates a Virtual Machine (small) configured with two data disks.  After the Virtual Machine is provisioned and running,
  the data disks are then formatted and have drive letters assigned.  User is prompted for credentials to use to provision
  the new Virtual Machine.

  Note: This script requires an Azure Storage Account to run.  Storage account can be specified by setting the 
  subscription configuration.  For example:
    Set-AzureSubscription -SubscriptionName "MySubscription" -CurrentStorageAccount "MyStorageAccount"
.EXAMPLE
  Add-DataDisksToVM.ps1 -ServiceName "MyServiceName" -VMName "MyVM" -Location "West US" -NumberOfDisks 2 -DiskSizeInGB 16
#>

param(
    # Cloud service name to deploy the VMs to
    [Parameter(Mandatory = $true, ParameterSetName = "ExistingService")]
    [Parameter(ParameterSetName="CreateNewService")]
    [String]$ServiceName,

    # Name of the Virtual Machine to create
    [Parameter(Mandatory = $true, ParameterSetName = "ExistingService")]
    [Parameter(ParameterSetName="CreateNewService")]
    [String]$VMName,

    # Location
    [Parameter(Mandatory = $true)]
    [Parameter(ParameterSetName="CreateNewService")]
    [String]$Location,
        
    # Disk size in GB
    [Parameter(Mandatory = $true, ParameterSetName = "ExistingService")]
    [Parameter(ParameterSetName="CreateNewService")]
    [Int32]$DiskSizeInGB,

    # Number of data disks to add to each virtual machine
    [Parameter(Mandatory = $true, ParameterSetName = "ExistingService")]
    [Parameter(ParameterSetName="CreateNewService")]
    [Int32]$NumberOfDisks
)


<#
.SYNOPSIS
   Installs a WinRm certificate to the local store
.DESCRIPTION
   Gets the WinRM certificate from the Virtual Machine in the Service Name specified, and 
   installs it on the Current User's personal store.
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

# Image name to create the Virtual Machine from.  Use Get-AzureVMImage for list of available images.
$imageName = "bd507d3a70934695bc2128e3e5a255ba__RightImage-Windows-2012-x64-v13.4.12.2"

# Check if hosted service with $ServiceName exists
$existingService = Get-AzureService -ServiceName $ServiceName -ErrorAction SilentlyContinue

if ($PSCmdlet.ParameterSetName -eq "ExistingService")
{
    if ($existingService -eq $null)
    {
        throw "Hosted service with name $ServiceName doesn't exist"
    }
}
else
{
    if ($existingService -ne $null)
    {
        throw "Hosted service with name $ServiceName already exists"
    }
 
    New-AzureService -ServiceName $ServiceName -Location $Location
}

# Get credentials from user to use to configure the new Virtual Machine
$credential = Get-Credential

# Configure the new Virtual Machine.
$userName = $credential.GetNetworkCredential().UserName
$password = $credential.GetNetworkCredential().Password
$vmConfig = New-AzureVMConfig -Name $VMName -InstanceSize Small -ImageName $imageName  |
            Add-AzureProvisioningConfig -Windows -AdminUsername $userName -Password $password |
            Add-AzureDataDisk -CreateNew -DiskSizeInGB $DiskSizeInGB -DiskLabel "disk_0" -LUN 1 |
            Add-AzureDataDisk -CreateNew -DiskSizeInGB $DiskSizeInGB -DiskLabel "disk_1" -LUN 2 

# Create the Virtual Machine and wait for it to boot.
New-AzureVM -ServiceName $ServiceName -VMs $vmConfig -WaitForBoot

# Install a remote management certificate from the Virtual Machine.
Install-WinRmCertificate -serviceName $ServiceName -vmName $VMName

# Format data disks and assign drive letters.
$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName
Invoke-Command -ConnectionUri $winRmUri.ToString() -Credential $credential -ScriptBlock {
    Get-Disk | 
    Where-Object PartitionStyle -eq "RAW" |
    Initialize-Disk -PartitionStyle MBR -PassThru |
    New-Partition -AssignDriveLetter -UseMaximumSize |
    Format-Volume -FileSystem NTFS -Confirm:$false
}


