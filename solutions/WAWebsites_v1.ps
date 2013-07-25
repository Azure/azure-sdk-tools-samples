<#
.SYNOPSIS
    Creates scheduled tasks to Manage Windows Azure Websites
.DESCRIPTION
    Operations TBD
    Load your publishSettings (Maybe set default if it has more than one)
    Check if the website already exists 
    Create the website 
    Run the website


.EXAMPLE
    WAzure_Websites.ps1 -defaultsuscription "MySubscrName" -websitename "WebSiteName" 
#>



param(
    # The name of the Subscription to Use. 
    [Parameter(Mandatory = $true)] 
    [string]$defaultsubscription,

    
    # The webSite Name you want to create.
    [Parameter(Mandatory = $true)] 
    [string]$websitename,

     # The WebSiteLocation. 
    [Parameter(Mandatory = $true)] 
    [string]$websitelocation
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

#  Set the default suscription you will work with
Set-AzureSubscription -SubscriptionName $defaultsubscription



#Check if the Website exists 
if((Get-AzureWebsite -Name $websitename) -ne $null){ 
    echo "Error the site already exist, Maybe  you want to Update it"
    exit
 }

#Start Creation 
Write-Verbose ("Starting Website {0} Create process" -f $websitename)
$website = New-AzureWebsite -Name $websitename -Location $websitelocation -Verbose


#Show Website 
Write-Verbose ("Run the website!" -f $websitename)
Show-AzureWebsite $websitename
