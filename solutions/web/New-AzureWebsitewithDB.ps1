<#
.SYNOPSIS
    Creates a Windows Azure Website and connects to a SQL Azure DB and a storage account.  
.DESCRIPTION 
   This script will create a website, SQl DB and storage account based on the provided 
   websitename, Azure Data center location, storage name and the credential(user id and password)
   provided for Database.
.EXAMPLE
   .\New-AzureWebsitewithDB.ps1 -WebSiteName "WebSiteName" -Location "West US" `
        -StorageAccountName "StorageAccountName" 
#>

param(
    [CmdletBinding( SupportsShouldProcess=$true)]
         
    # The webSite Name you want to create
    [Parameter(Mandatory = $true)] 
    [string]$WebSiteName,
        
    # The Azure Data center Location
    [Parameter(Mandatory = $true)] 
    [string]$Location,
    
    # The Storage account that will be linked to the website
    [Parameter(Mandatory = $true)]
    [String]$StorageAccountName,

    # The application database name that will be created and used by the website in this script
    [String]$AppDatabaseName = "appdb",

    # The database firewall rule
    [String]$FirewallRuleName,

    # Users machine ip range first address 
    [String]$StartIPAddress,

    # Rule name
    [String]$RuleName,

    # End ip address for the range for user machine to access the db
    [String]$EndIPAddress
          
    )

# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3

# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"

# Check if Windows Azure Powershell is avaiable
if ((Get-Module -ListAvailable Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please install from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}
   
<#
.SYNOPSIS
    Creates a storage account from the parameters accountname and Azure Data center location.
.DESCRIPTION
    This function will first check to verify that the storage account exists and 
    if not, then creates a storage account using the storage account name and the 
    datacenter location provided. The verification is done using Get-AzureStorageAccount
    cmdLet.
    `
.EXAMPLE
    $storage = CreateStorageAccount -StorageAccountName "testaccount" -Location "West US"
#>
Function CreateStorageAccount($StorageAccountName,$Location)
{
    
    $storageResult = Get-AzureStorageAccount | Where-Object `
        {$_.StorageAccountName -eq $StorageAccountName }
    
    if($storageResult -eq $null) 
        {
            # Create a new storage account
            New-AzureStorageAccount -StorageAccountName $StorageAccountName -Location $Location 
        }
        else 
        {
            Write-Verbose ("Storage account {0} in location {1} exist" -f $StorageAccountName, $Location)
        }
    
    # Get the access key of the storage account
    $storageAccountKey = Get-AzureStorageKey -StorageAccountName $StorageAccountName
    
    # When call Get-AzureStorageKey both primary and secondary key is 
    #returned but we are only using the primary key.
    $appSettings = @{"StorageAccountName" = $StorageAccountName;`
        "StorageAccountAccessKey" = $storageAccountKey.Primary}

    Return @{AppSettings=$appSettings}
}

<#
.SYNOPSIS
    creates a sql db and set server firewall rule based on the parameters location, 
    name, user id, password
.DESCRIPTION
   This function creates a database server, sets up server firewall rules and then 
   creates a Database. It uses New-AzureSqlDatabaseServer cmdlet to create the server, 
   New-AzureSqlDatabaseServerFirewallRule to create the firewall rule, 
   New-AzureSqlDatabase cmdlet to create the database. 
 
    `
.EXAMPLE
    $db = CreateDatabase -Location "West US" -AppDatabaseName "AppDatabaseName"
     -UserName "UserName" -Password "Password" -RuleName "RuleName" 
     -FirewallRuleName "FirewallRuleName" -StartIPAddress "0.0.0.0" -EndIPAddress "0.0.0.0"
#>

Function CreateDatabase($Location,$AppDatabaseName, $UserName, $Password,`
                         $RuleName, $FirewallRuleName, $StartIPAddress, $EndIPAddress)
{
    Write-Verbose ("[Start] creating SQL Azure database server")
    $databaseServer = New-AzureSqlDatabaseServer -AdministratorLogin $UserName `
        -AdministratorLoginPassword $Password -Location $Location
    Write-Verbose ("[Finish] creating SQL Azure database server")

    
    # Setting server firewall rule
    Write-Verbose ("[Start] creating firewall rule")
    New-AzureSqlDatabaseServerFirewallRule -ServerName $databaseServer.ServerName `
        -RuleName "AllowUserIP" -StartIpAddress $StartIPAddress -EndIpAddress $EndIPAddress
    New-AzureSqlDatabaseServerFirewallRule -ServerName $databaseServer.ServerName `
        -RuleName "AllowAllAzureIP" -StartIpAddress "0.0.0.0" -EndIpAddress "0.0.0.0"  
    Write-Verbose ("[Finish] created firewall rule")
    

    # Create a database context which includes the server name and credential
    $credential = New-PSCredentialFromPlainText -UserName $UserName -Password $Password
    $context = New-AzureSqlDatabaseServerContext -ServerName $databaseServer.ServerName`
         -Credential $credential
    

    # Use the database context to create app database
    Write-Verbose ("[Start] creating database {0} in database server {1}" `
        -f $AppDatabaseName, $databaseServer.ServerName)
    New-AzureSqlDatabase -DatabaseName $AppDatabaseName -Context $context 
    Write-Verbose ("[Finish] creating database {0} in database server {1}" `
        -f $AppDatabaseName, $databaseServer.ServerName)
    
    $appDatabaseConnectionString = Get-SQLAzureDatabaseConnectionString -DatabaseServerName `
        $databaseServer.ServerName -DatabaseName $AppDatabaseName -UserName `
        $UserName -Password $Password
    
    
    Return @{ `
        Server = $databaseServer.ServerName; UserName = $UserName; Password = $Password; `
        AppDatabase = @{Name = $AppDatabaseName; AppDatabaseConnectionString = $appDatabaseConnectionString};         
        } 
    }

 <#
.SYNOPSIS
    Detect IP address for user machine
.DESCRIPTION
   This functions retrieves users machine IP range for setting SQLDB server firewall rule.
    `
.EXAMPLE
    $ipRange = Detect-IPAddress
#>
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
 <#
.SYNOPSIS
    Detect IP address for user machine
.DESCRIPTION
   This functions retrieves users machine IP range for setting SQLDB server firewall rule.
.EXAMPLE
    $ipRange = Detect-IPAddress
#>
Function Get-SQLAzureDatabaseConnectionString
{
    Param(
        [String]$DatabaseServerName,
        [String]$DatabaseName,
        [String]$UserName,
        [String]$Password
        )
                
    Return "Server=tcp:{0}.database.windows.net,1433;Database={1};
            User ID={2}@{0};Password={3};Trusted_Connection=False;Encrypt=True;Connection Timeout=30;" -f
            $DatabaseServerName, $DatabaseName, $UserName, $Password
}

# Detect IP range for SQL Azure whitelisting if the IP range is not specified
If (-not ($StartIPAddress -and $EndIPAddress))
{
    $ipRange = Detect-IPAddress
    $StartIPAddress = $ipRange.StartIPAddress
    $EndIPAddress = $ipRange.EndIPAddress
}

# 1 - Create the website 
#Check if the Website exists 
$result = Get-AzureWebsite | Where-Object {$_.Name -eq $WebSiteName }

if    ($result -eq $null) 
{   
    Write-Verbose "creating website" 
}
else 
{
    throw "Website already exists, please try a different website name"
}

# Get credentials from user to use to configure the new Virtual Machine
$credential = Get-Credential

# Configure the new Virtual Machine.
$UserName = $credential.GetNetworkCredential().UserName
$Password = $credential.GetNetworkCredential().Password

#Start Creation 
Write-Verbose ("Starting Website {0} Create process" -f $WebSiteName)
$website = New-AzureWebsite -Name $WebSiteName -Location $Location 

# 2 - Create the storage account
$storage = CreateStorageAccount -StorageAccountName $StorageAccountName -Location $Location

# 3 - Create the SQL DB
$db = CreateDatabase -Location $Location -AppDatabaseName $AppDatabaseName `
    -UserName $UserName -Password $Password -RuleName $RuleName `
    -FirewallRuleName $FirewallRuleName  -StartIPAddress $StartIPAddress `
    -EndIPAddress $EndIPAddress  

# 4 - Link the website to the storage account and SQLDB
#Set-AzureWebsite -Name $WebSiteName -AppSettings $storage.AppSettings -ConnectionStrings $db.AppDatabaseConnectionString