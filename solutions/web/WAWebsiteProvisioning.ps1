<#
.SYNOPSIS
    Creates scheduled tasks to Manage Windows Azure Websites
.DESCRIPTION
    1 - Create the website 
    2 - Create the storage account 
    3 - Create the SQL DB
    4 - Link the website to the storage account and SQLDB 
    `
.EXAMPLE
    WAWebsiteProvisioning.ps1 -WebSiteName "WebSiteName" -WebsiteLocation "Location" -storageName "" 
    This example creates a web site with a linked storage account and SQL Database 
#>

#==============================================================================================
# Parameters
#==============================================================================================
param(
    [CmdletBinding( SupportsShouldProcess=$true)]
         
    # The webSite Name you want to create

    [Parameter(Mandatory = $true)] 
    [string]$WebSiteName,
    

    # The Location. 
    [Parameter(Mandatory = $true)] 
    [string]$Location,
    

    # The StorageAccountName
    [Parameter(Mandatory = $true)]
    [String]$StorageName,
      
   
    # SQL DB params
    [String]$AppDatabaseName = "appdb",
    [String]$UserName = "dbuser",
    [String]$Password = "!Testpasswrord1",
    [String]$FirewallRuleName,
    [String]$StartIPAddress,
    [String]$RuleName,
    [String]$EndIPAddress
          
    )


#==============================================================================================
# Functions
#==============================================================================================

#Create the Storage If Needed 
Function CreateStorage($StorageName,$Location)
{
    try
    {
        $myStorageAccount= Get-AzureStorageAccount $StorageName
        Write-Verbose ("Storage account {0} in location {1} exist" -f $StorageName, $Location)
    }
    catch
    {
        # Create a new storage account
        New-AzureStorageAccount -StorageAccountName $StorageName -Location $Location 
     }

    # Get the access key of the storage account
    $key = Get-AzureStorageKey -StorageAccountName $StorageName

    # Generate the connection string of the storage account
    $connectionString = "BlobEndpoint=http://{0}.blob.core.windows.net/;QueueEndpoint=http://{0}.queue.core.windows.net/;TableEndpoint=http://{0}.table.core.windows.net/;AccountName={0};AccountKey={1}" -f $StorageName, $key.Primary
    
    $appSettings = @{"StorageAccountName" = $storageName;"StorageAccountAccessKey" = $key.Primary}

    Return @{AccountName = $StorageName; AppSettings=$appSettings; AccessKey = $key.Primary; ConnectionString = $connectionString}
}

#Create the DB If Needed
Function CreateDB ($Location,$AppDatabaseName, $UserName, $Password, $RuleName, $FirewallRuleName, $StartIPAddress, $EndIPAddress )
{
    Write-Verbose ("[Start] creating SQL Azure database server in location {0} with username {1} and password {2}" -f $Location, $UserName, $Password)
    $databaseServer = New-AzureSqlDatabaseServer -AdministratorLogin $UserName -AdministratorLoginPassword $Password -Location $Location
    Write-Verbose ("[Finish] creating SQL Azure database server in location {0} with username {1} and password {2}" -f $Location, $UserName, $Password)


    # Setting server firewall rule
    Write-Verbose ("[Start] creating firewall rule {0} in database server {1}" -f $RuleName, $databaseServer.ServerName)
    New-AzureSqlDatabaseServerFirewallRule -ServerName $databaseServer.ServerName -RuleName "AllowAllAzureIP" -StartIpAddress $StartIPAddress -EndIpAddress $EndIPAddress 
    Write-Verbose ("[Finish] created firewall rule {0} in database server {1}" -f $FirewallRuleName, $databaseServer.ServerName)


    # Create a database context which includes the server name and credential
    # These are all local operations. No API call to Windows Azure
    $credential = New-PSCredentialFromPlainText -UserName $UserName -Password $Password
    $context = New-AzureSqlDatabaseServerContext -ServerName $databaseServer.ServerName -Credential $credential


    # Use the database context to create app database
    Write-Verbose ("[Start] creating database {0} in database server {1}" -f $AppDatabaseName, $databaseServer.ServerName)
    New-AzureSqlDatabase -DatabaseName $AppDatabaseName -Context $context 
    Write-Verbose ("[Finish] creating database {0} in database server {1}" -f $AppDatabaseName, $databaseServer.ServerName)

    $appDatabaseConnectionString = Get-SQLAzureDatabaseConnectionString -DatabaseServerName $databaseServer.ServerName -DatabaseName $AppDatabaseName -UserName $UserName -Password $Password
    

    Return @{ `
        Server = $databaseServer.ServerName; UserName = $UserName; Password = $Password; `
        AppDatabase = @{Name = $AppDatabaseName; AppDatabaseConnectionString = $appDatabaseConnectionString};         
        } 
    }


# Get the IP Range needed to be whitelisted for SQL Azure
Function Detect-IPAddress

{
    $ipregex = "(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
    $text = Invoke-RestMethod 'http://www.whatismyip.com/api/wimi.php'
    $result = $null


    If($text -match $ipregex)
    {
        $ipaddress = $matches[0]
        $ipparts = $ipaddress.Split('.')
        $ipparts[3] = 0
        $startip = [string]::Join('.',$ipparts)
        $ipparts[3] = 255
        $endip = [string]::Join('.',$ipparts)


        $result = @{StartIPAddress = $startip; EndIPAddress = $endip}
    }


    Return $result
}

# Create connection string
Function Get-SQLAzureDatabaseConnectionString
{
    Param(
        [String]$DatabaseServerName,
        [String]$DatabaseName,
        [String]$UserName,
        [String]$Password
        )


    Return "Server=tcp:{0}.database.windows.net,1433;Database={1};User ID={2}@{0};Password={3};Trusted_Connection=False;Encrypt=True;Connection Timeout=30;" -f
        $DatabaseServerName, $DatabaseName, $UserName, $Password
}

# The PS Credential object will be used to create a database context, which will be used to create database.
Function New-PSCredentialFromPlainText
{
    Param(
        [String]$UserName,
        [String]$Password
        )

    $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force

    Return New-Object System.Management.Automation.PSCredential($UserName, $securePassword)
}

#==============================================================================================
# Main Script 
#==============================================================================================
Set-StrictMode -Version 3
$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"


# Detect IP range for SQL Azure whitelisting if the IP range is not specified
If (-not ($StartIPAddress -and $EndIPAddress))
{
    $ipRange = Detect-IPAddress
    $StartIPAddress = $ipRange.StartIPAddress
    $EndIPAddress = $ipRange.EndIPAddress
}


# Mark the start time of the script execution
$startTime = Get-Date

# Check if Windows Azure Powershell is avaiable
if ((Get-Module Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please make sure to install them from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}


# 1 - Create the website 
#Check if the Website exists 
$result = Get-AzureWebsite | Where-Object {$_.Name -eq $WebSiteName }

if($result -eq $null) {Write-Verbose "creating website" }
else 
{
    #exit
    throw "Error the site already exist, Maybe  you want to Update it"
}

#Start Creation 
Write-Verbose ("Starting Website {0} Create process" -f $WebSiteName)
$website = New-AzureWebsite -Name $WebSiteName -Location $Location 


# 2 - Create the storage account
$storage = CreateStorage -StorageName $StorageName -Location $Location


# 3 - Create the SQL DB
$db = CreateDB -Location $Location -AppDatabaseName $AppDatabaseName -UserName $UserName -Password $Password -RuleName $RuleName -FirewallRuleName $FirewallRuleName  -StartIPAddress $StartIPAddress -EndIPAddress $EndIPAddress  

# 4 - Link the website to the storage account and SQLDB
#Set-AzureWebsite -Name $WebSiteName -AppSettings $storage.AppSettings -ConnectionStrings $db.AppDatabaseConnectionString


# Output the time consumed in seconds
$finishTime = Get-Date
Write-Verbose ("Total time used (seconds): {0}" -f ($finishTime - $startTime).TotalSeconds)
