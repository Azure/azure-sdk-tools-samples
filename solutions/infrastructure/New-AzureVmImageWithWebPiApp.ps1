<#
.SYNOPSIS
   Create a new VM Image, based on the provided stock image, and the WebPI application.
.DESCRIPTION
   Creates a new VM image, based on the provided stock image name. The stock image name 
   can be retrieved from the ImageName property of the Images returned by Get-AzureVMImage cmdlet.
   The cmdlet also installs the provided WebPi component, and creates a new image for future 
   use, which is added to the subscription's library.
.EXAMPLE
   New-AzureVmImageWithWebPiApp.ps1 `
       -WebPIApplicationName blogengineNET -WebPIApplicationAnswerFile .\BlogengineNet.app `
       -ImageName bengineimage -ImageLabel bengineimagelabel 
.OUTPUTS
   Microsoft.WindowsAzure.Management.ServiceManagement.Model.OSImageContext
#>


param
(
    # The WebPI application ID (Currently supports WebPI applications only).
    [Parameter(Mandatory = $true)]
    [String]
    $WebPIApplicationName,
    
    # The WebPI application answer file full path.
    [Parameter(Mandatory = $true)]
    [String]
    $WebPIApplicationAnswerFile,
    
    # Name of the new image.
    [Parameter(Mandatory = $true)]
    [String]
    $ImageName,
    
    # Label of the new image.
    [Parameter(Mandatory = $true)]
    [String]
    $ImageLabel)


# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3


# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"


# Check if Windows Azure Powershell is avaiable
if ((Get-Module -ListAvailable Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please make sure to install them from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}


<#
.SYNOPSIS
  Returns the latest image for a given image family name filter.
.DESCRIPTION
  Will return the latest image based on a filter match on the ImageFamilyName and
  PublisedDate of the image.  The more specific the filter, the more control you have
  over the object returned.
.EXAMPLE
  The following example will return the latest SQL Server image.  It could be SQL Server
  2014, 2012 or 2008
    
    Get-LatestImage -ImageFamilyNameFilter "*SQL Server*"


  The following example will return the latest SQL Server 2014 image. This function will
  also only select the image from images published by Microsoft.  
   
    Get-LatestImage -ImageFamilyNameFilter "*SQL Server 2014*" -OnlyMicrosoftImages


  The following example will return $null because Microsoft doesn't publish Ubuntu images.
   
    Get-LatestImage -ImageFamilyNameFilter "*Ubuntu*" -OnlyMicrosoftImages
#>
function Get-LatestImage
{
    param
    (
        # A filter for selecting the image family.
        # For example, "Windows Server 2012*", "*2012 Datacenter*", "*SQL*, "Sharepoint*"
        [Parameter(Mandatory = $true)]
        [String]
        $ImageFamilyNameFilter,


        # A switch to indicate whether or not to select the latest image where the publisher is Microsoft.
        # If this switch is not specified, then images from all possible publishers are considered.
        [Parameter(Mandatory = $false)]
        [switch]
        $OnlyMicrosoftImages
    )


    # Get a list of all available images.
    $imageList = Get-AzureVMImage


    if ($OnlyMicrosoftImages.IsPresent)
    {
        $imageList = $imageList |
                         Where-Object { `
                             ($_.PublisherName -ilike "Microsoft*" -and `
                              $_.ImageFamily -ilike $ImageFamilyNameFilter ) }
    }
    else
    {
        $imageList = $imageList |
                         Where-Object { `
                             ($_.ImageFamily -ilike $ImageFamilyNameFilter ) } 
    }


    $imageList = $imageList | 
                     Sort-Object -Unique -Descending -Property ImageFamily |
                     Sort-Object -Descending -Property PublishedDate


    $imageList | Select-Object -First(1)
}


# Get an image to provision virtual machines from.
$imageFamilyNameFilter = "Windows Server 2012 Datacenter"
$image = Get-LatestImage -ImageFamilyNameFilter $imageFamilyNameFilter -OnlyMicrosoftImages
if ($image -eq $null)
{
    throw "Unable to find an image for $imageFamilyNameFilter to provision Virtual Machine."
}


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
   None
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
  Sends a file to a remote session.
.EXAMPLE
  $remoteSession = New-PSSession -ConnectionUri $remoteWinRmUri.AbsoluteUri -Credential $credential
  Send-File -Source "c:\temp\myappdata.xml" -Destination "c:\temp\myappdata.xml" $remoteSession
#>
function Send-File
{
    param (
        
        # The path on the local computer
        [Parameter(Mandatory = $true)]
        $Source,
        
        # The target path on the remote computer
        [Parameter(Mandatory = $true)]
        $Destination,
        
        # The session that represents the remote computer
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session)
    
    $remoteScript = 
    {
        param ($destination, $bytes)
        
        # Convert the destination path to a full filesystem path (to support relative paths)
        $destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($destination)
        
        # Write the content to the new file
        $file = [IO.File]::Open($destination, "OpenOrCreate")
        $null = $file.Seek(0, "End")
        $null = $file.Write($bytes, 0, $bytes.Length)
        $file.Close()
    }
    
    # Get the source file, and then start reading its content
    $sourceFile = Get-Item $Source
    
    # Delete the previously-existing file if it exists
    Invoke-Command -Session $Session {
        if (Test-Path $args[0])
        {
            Remove-Item $args[0]
        }
        
        $destinationDirectory = Split-Path -LiteralPath $args[0]
        if (!(Test-Path $destinationDirectory))
        {
            New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
        }
    } -ArgumentList $Destination
    
    # Now break it into chunks to stream
    Write-Progress -Activity "Sending $Source" -Status "Preparing file"
    $streamSize = 1MB
    $position = 0
    $rawBytes = New-Object byte[] $streamSize
    $file = [IO.File]::OpenRead($sourceFile.FullName)
    while (($read = $file.Read($rawBytes, 0, $streamSize)) -gt 0)
    {
        Write-Progress -Activity "Writing $Destination" `
        -Status "Sending file" `
        -PercentComplete ($position / $sourceFile.Length * 100)
        
        # Ensure that our array is the same size as what we read
        
        # from disk
        if ($read -ne $rawBytes.Length)
        {
            [Array]::Resize( [ref] $rawBytes, $read)
        }
        
        # And send that array to the remote system
        Invoke-Command -Session $session $remoteScript `
        -ArgumentList $destination, $rawBytes
        
        # Ensure that our array is the same size as what we read
        
        # from disk
        if ($rawBytes.Length -ne $streamSize)
        {
            [Array]::Resize( [ref] $rawBytes, $streamSize)
        }
        [GC]::Collect()
        $position += $read
    }
    
    $file.Close()
    
    # Show the result
    Invoke-Command -Session $Session { Get-Item $args[0] } -ArgumentList $Destination
}


# Create a random temporary subdomain name to deploy the VM to.
$serviceName = [System.Guid]::NewGuid()
$hostName = "temphost"
Write-Verbose "Prompt user for admininstrator credentials to use when provisioning the virtual machine(s)."
$credential = Get-Credential
Write-Verbose "Administrator credentials captured.  Use these credentials to login to the virtual machine(s) when the script is complete."

# Determine the target location from the current storage account on the subscription.
$subscription = Get-AzureSubscription -Current
$currentStorageAccountName = $subscription.CurrentStorageAccount
if ($currentStorageAccountName -eq "")
{
    throw "Please set the current storage account on the default subscription with Set-AzureSubscription -SubscriptionName `
    <defaultSubscriptionName> -CurrentStorageAccount <CurrentStorageAccountForTheSubscription>"    
}

$currentStorageAccount = Get-AzureStorageAccount -StorageAccountName $currentStorageAccountName
Write-Progress -Activity "Creating VM Image" -Status "Received storage account details" -PercentComplete 1
$targetLocation = $currentStorageAccount.Location


# Deploy the VM
$existingVm = Get-AzureVM -ServiceName $serviceName -Name $HostName -ErrorAction SilentlyContinue
Write-Progress -Activity "Creating VM Image" -Status "Checked an existing VM" -PercentComplete 2
if ($existingVm -ne $null)
{
    throw "A VM with name $HostName exists on $serviceName"
}


Write-Progress -Activity "Creating VM Image" -Status "Creating the temporary VM." -PercentComplete 3


$vms = @()


$vms += New-AzureVMConfig -Name $hostName -InstanceSize Small -ImageName $image.ImageName | 
            Add-AzureProvisioningConfig -Windows -AdminUsername  $credential.GetNetworkCredential().username `
            -Password $credential.GetNetworkCredential().password


New-AzureVM -ServiceName $serviceName -Location $targetLocation -VMs $vms -WaitForBoot | Out-Null


Write-Progress -Activity "Creating VM Image" -Status "Created the temporary VM deployment" -PercentComplete 50


if ($?)
{
    Write-Verbose "Created the VMs and the cloud service $serviceName"
}


# prepare to run the remote execution


# Get the RemotePS/WinRM Uri to connect to
$winRmUri = Get-AzureWinRMUri -ServiceName $serviceName -Name $hostName


Install-WinRmCertificate $serviceName $hostName
Write-Progress -Activity "Creating VM Image" `
    -Status "Configured WinRM access. Now will start copying the script and answer files to the VM." `
    -PercentComplete 55


$remoteScriptsDirectory = "c:\Scripts"
$remoteScriptFileName = "RemoteScripts.ps1"


# Copy the required files to the remote server
$remoteSession = New-PSSession -ConnectionUri $winRmUri.AbsoluteUri -Credential $credential
$sourcePath = "$PSScriptRoot\$remoteScriptFileName"
$remoteScriptFilePath = "$remoteScriptsDirectory\$remoteScriptFileName"
Send-File $sourcePath $remoteScriptFilePath $remoteSession


$answerFileName = Split-Path -Leaf $WebPIApplicationAnswerFile
$answerFilePath = "$remoteScriptsDirectory\$answerFileName"
Send-File $WebPIApplicationAnswerFile $answerFilePath $remoteSession
Remove-PSSession -InstanceId $remoteSession.InstanceId


Write-Progress -Activity "Creating VM Image" -Status "Copied the files to VM. Now will start runnign the remote script." -PercentComplete 65


# Run the install script for the WebPI application
$runInstallScript = 
{
    param ([String]$WebPiApplication, [String]$scriptFilePath, [String] $AnswerFilePath)
    
    # Usual recommendation is not to set the execution policy to a potentially less restrictive setting then what
    
    # may have been already set, such as AllSigned. However, in this sample, we know we are creating this VM from
    
    # scratch and we know the initial setting.
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
    
    # Install .NET 3.5 seperately, as it fails through WebPI dependencies install
    Import-Module ServerManager
    Add-Windowsfeature -Name NET-Framework-Features | Out-Null
    Add-Windowsfeature -Name Web-Asp-Net45 | Out-Null
    
    . $scriptFilePath
    
    Install-WebPiApplication -ApplicationId $WebPiApplication -AnswerFile $AnswerFilePath
    
    # Run sysprep to generalize the VM
    $sysprepCmd = "$env:windir\System32\Sysprep\sysprep.exe"
    $sysprepArgs = "/quiet /generalize /oobe /shutdown"
    Start-Process -FilePath $sysprepCmd -ArgumentList $sysprepArgs -PassThru | Wait-Process
}
$argumentList = @(
    $WebPIApplicationName, 
    $remoteScriptFilePath, 
    $answerFilePath)


Invoke-Command -ConnectionUri $winRmUri.ToString() -Credential $credential `
    -ScriptBlock $runInstallScript -ArgumentList $argumentList


Write-Progress -Activity "Creating VM Image" -Status "Install WebPI component complete" -PercentComplete 95


$pollTimeout = 15
do
{
    Write-Verbose "Waiting for $pollTimeout seconds before checking the VM status."
    Start-Sleep -Seconds $pollTimeout
    $vm = Get-AzureVM -ServiceName $serviceName -Name $hostName
} 
until ($vm.PowerState -eq "Stopped")


Save-AzureVMImage -ServiceName $serviceName -Name $hostName `
    -NewImageName $ImageName -NewImageLabel $ImageLabel | Out-Null
Write-Progress -Activity "Creating VM Image" -Status "Operation complete" -PercentComplete 100 -Completed


# Cleanup
Remove-AzureService -ServiceName $serviceName -Force | Out-Null     


Get-AzureVMImage -ImageName $ImageName   



