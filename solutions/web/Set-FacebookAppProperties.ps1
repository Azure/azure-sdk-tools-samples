<#
.Synopsis
   Given an Azure web site that implements a Facebook application, set the AppId and AppSecret.
.DESCRIPTION
   Demostrates how the settings of a web site can be set remotely using powershell. Assumes a Facebook
   application that has been deployed, and changes its settings for AppId and AppSecret.
.EXAMPLE
   .\Set-FacebookAppProperties.ps1 -Name myFbApp -AppId <appId> -AppSecret <appSecret>
#>
Param
(
        
    # Name of the web site the Facebook application is deployed to
    [Parameter(Mandatory = $true)]
    [String]
    $Name,

    # Facebook app Id
    [Parameter(Mandatory = $true)]
    [String]
    $AppId,

    # Facebook app secret
    [Parameter(Mandatory = $true)]
    [String]
    $AppSecret
)
# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3

# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"

# Check if Windows Azure Powershell is avaiable
if ((Get-Module Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please make sure to install them from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}

$settings = @{
    "FacebookAppId" = $AppId;
    "FacebookAppSecret" = $AppSecret
    }

Get-AzureWebsite -Name $Name | Set-AzureWebsite -AppSettings $settings
