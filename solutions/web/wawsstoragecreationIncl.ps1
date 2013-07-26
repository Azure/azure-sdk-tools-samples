<#
.SYNOPSIS
    Creates scheduled tasks to Manage Windows Azure Websites
.DESCRIPTION
    Operations TBD
    Load your publishSettings (Maybe set default if it has more than one)
    Check if the website already exists 
    Create the website 
    Run the website

    `
.EXAMPLE
    WAzure_Websites.ps1 -defaultsuscription "MySubscrName" -websitename "WebSiteName" -storageName ""
#>


param(
         
    # The webSite Name you want to create.
    [Parameter(Mandatory = $true)] 
    [string]$websitename,

    # The WebSiteLocation. 
    [Parameter(Mandatory = $true)] 
    [string]$websitelocation,

    [Parameter(Mandatory = $true)]
    [String]$storageName
    )



# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3


# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
#$VerbosePreference = "Continue" 


Write-Verbose ("Some Verifications... ")


# Check if Windows Azure Powershell is avaiable
if ((Get-Module Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please make sure to install them from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}

if($defaultsubscription -ne $null)
{
    #  Set the default suscription you will work with
    Set-AzureSubscription -DefaultSubscription "GuadaAzure01"
}



#Check if the Website exists 
if((Get-AzureWebsite -Name $websitename) -ne $null){ 
    Write-Information "Error the site already exist, Maybe  you want to Update it"
    exit
}


#Start Creation 
Write-Verbose ("Starting Website {0} Create process" -f $websitename)
$website = New-AzureWebsite -Name $websitename -Location $websitelocation -Verbose

#Show Website 
#Write-Verbose ("Run the website!" -f $websitename)
#Show-AzureWebsite $websitename

# Create a new storage account
Write-Verbose ("[Start] creating storage account {0} in location {1}" -f $storageName, $websitelocation)

#We will need to add verification to see if the storage account already exist, similar to the Website 

New-AzureStorageAccount -StorageAccountName $storageName -Location $websitelocation -Verbose
Write-Verbose ("[Finish] creating storage account {0} in location {1}" -f $storageName, $websitelocation)


# Get the access key of the storage account
$key = Get-AzureStorageKey -StorageAccountName $storageName


# Generate the connection string of the storage account
$connectionString = "BlobEndpoint=http://{0}.blob.core.windows.net/;QueueEndpoint=http://{0}.queue.core.windows.net/;TableEndpoint=http://{0}.table.core.windows.net/;AccountName={0};AccountKey={1}" -f $Name, $key.Primary


Return @{AccountName = $storageName; AccessKey = $key.Primary; ConnectionString = $connectionString}
