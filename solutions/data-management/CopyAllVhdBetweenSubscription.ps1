<#
.Synopsis
   This scripts find all Disk in defult Azure Storage Account and copies all disk to other Account.
   
.DESCRIPTION
    This script set environment variables and a Storage context of target Storage in other subscriptions.
    Next, look all Disk, and one by one, copies disk’s blob and create a Disk in the destination subscriptions
    To does Copy and Create Disk, the script change Default storage subscription and default subscription.
    When it are finished it return it default values.

    The destination Storage Account must exist, the container could it creat on the fly by the script.
 
.EXAMPLE
    Use the following copy all Disk
    $test = & $scriptPath `
    -DestSubName "Azpad144UOO9523" `
    -DestContainer 'copiedvhds’ `
    -DestStorageAcc "jpggazpad14" `
    -DestStorageKey "XXXXXXXXX==" 

.OUTPUTS
   Write in Host the time spended in the script execution
#>
Param 
(
    #Destination Subscription Name
    [Parameter(Mandatory = $true)]
    [String]$DestSubName,
    #Destination Storage Container name 
    [Parameter(Mandatory = $true)]
    [String]$DestContainer,
    #Destination Storage Account name 
    [Parameter(Mandatory = $true)]
    [String]$DestStorageAcc,
    #Destination Storage Account Key 
    [Parameter(Mandatory = $true)]
    [String]$DestStorageKey
)
<#
.Synopsis
   This function  return Disk's Storgae Account and container.

.DESCRIPTION
    This function  return Disk's Storgae Account and container.
     
.EXAMPLE
    $InfoStorageDisk =  getStorageInfo -MyDisk "DISCOUNO"

.OUTPUTS
   Hastable with Storage Account Name  and Container name
#>
function GetStorageInfo
{
param 
    (#Disk object
    [Parameter(Mandatory = $true)]
    $MyDisk
    )
    #Obtain Container
    [string] $aPath=$MyDisk.MediaLink.AbsolutePath
    [string] $MyContainer=$aPath.Substring(1,$aPath.IndexOf("/",2)-1)
    #obtain Storage Account
    [string] $MyHost= $MyDisk.MediaLink.Host
    [string] $MyStorageAccount=$MyHost.Substring(0,$MyHost.IndexOf("."))
    
    Return  @{StorageAccount=$MyStorageAccount;Container=$MyContainer;}
}

Function CreateContainer
{
Param
(
    #Storage Context
    [Parameter(Mandatory = $true)]
    $MyStorageContext,
    #Storage Container Name
    [Parameter(Mandatory = $true)]
    $MyContainer
)
    try
    {
        Get-AzureStorageContainer -Name $MyContainer -Context $MyStorageContext
        Write-Verbose ("Container {0} Exist!" -f $MyContainer)
    }
    catch
    {
        Write-Verbose ("Container {0} Not Exist! Strat Creating ....." -f $MyContainer)
        New-AzureStorageContainer -Name $MyContainer -Context $MyStorageContext
        Write-Verbose ("Container {0} Not Exist! Finish Creating ....." -f $MyContainer)
    }
}
#1. Setup enviroment
cls
$ErrorActionPreference = "Stop"
$CurrentAzureSub=Get-AzureSubscription -Current
$CurrentStorage= $CurrentAzureSub.CurrentStorageAccount
$DestUri = "http://{0}.blob.core.windows.net/{1}/{2}"
$StartTime = Get-Date

#1.1 Destination context
$DestContext = New-AzureStorageContext –StorageAccountName $DestStorageAcc  -StorageAccountKey $DestStorageKey
#1.2 Create Containes if it is not exist
CreateContainer -MyContainer $DestContainer -MyStorageContext $DestContext

#2. Loop of each Disk in my currento Storage Account
foreach ($_Disk in Get-AzureDisk)
{
    #2.1 
    $src = $_Disk.MediaLink
    $fileName = $_Disk.DiskName + '.vhd'

    $InfoStorageDisk =  GetStorageInfo -MyDisk $_Disk
    Write-Host ("Storage Account: {0} ,  container {1} and file {2}" -f $InfoStorageDisk.StorageAccount,$InfoStorageDisk.Container,$fileName)
 
    #2.2 Set Temp Storage Account in the Defult Subscription, to change Container's ACL
    Set-AzureSubscription -SubscriptionName $CurrentAzureSub.SubscriptionName -CurrentStorageAccount $InfoStorageDisk.StorageAccount
    #2.3 Get current container ACL   
    $CurrentContainerAcl=Get-AzureStorageContainerAcl -Name $InfoStorageDisk.Container 
    Write-Verbose $CurrentContainerAcl.Permission.PublicAccess
    #2.4 Set Container ACL to Blob, to read this content form copy porcess
    Set-AzureStorageContainerAcl -Name $InfoStorageDisk.Container -Permission Blob
    #2.5 Copy Blob
    Start-CopyAzureStorageBlob -SrcUri $src -destContainer $DestContainer  -destblob $fileName –destContext $DestContext
    #2.6 Create Disk in the Destination Account
    $MyMediaLocation=($DestUri -f $DestStorageAcc, $DestContainer,$fileName )
    if ($_Disk.Label -eq $null)
    {
       $_Disk.Label="Not Info" 
    }
    #2.6.1 Change DefaultSubscription to Create a Disk
    Set-AzureSubscription -DefaultSubscription $DestSubName 
    if ($_Disk.OS -eq $null)
    {
        Add-AzureDisk -DiskName $_Disk.DiskName -MediaLocation $MyMediaLocation -Label $_Disk.Label  
    }
    else
    {
         Add-AzureDisk -DiskName $_Disk.DiskName -MediaLocation $MyMediaLocation -Label $_Disk.Label -OS $_Disk.OS
    }
    #2.6.2 Return default subscription
    Set-AzureSubscription -DefaultSubscription $CurrentAzureSub.SubscriptionName
    
    #2.x Return Container ACL to original
    Set-AzureStorageContainerAcl -Name $InfoStorageDisk.Container -Permission $CurrentContainerAcl.PublicAccess
 
   
}

#3. Set original subscription's Storage account 
Set-AzureSubscription -SubscriptionName $CurrentAzureSub.SubscriptionName -CurrentStorageAccount $CurrentStorage

#4 Mark the finish time of the script execution
#    Output the time consumed in seconds
$finishTime = Get-Date

Write-Host ("Total time used (seconds): {0}" -f ($finishTime - $StartTime).TotalSeconds)