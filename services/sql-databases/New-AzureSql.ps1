<#
.Synopsis
   This script create Azure SQl Database
.DESCRIPTION
   
.EXAMPLE     How to Run this script
    .\New-AzureSql.ps1 "            -AppDatabaseName "XXXXXX" 
            -StartIPAddress "XXXXXX" 
            -EndIPAddress "XXXXXX" 
            -Location "XXXXXX 
            -FirewallRuleName ""XXXX"
    
.OUTPUTS
     Database connection string
#>

Param(
    #Application database name
    [Parameter(Mandatory = $true)]
    [String]$AppDatabaseName,   
    [Parameter(Mandatory = $true)]
    [String]$FirewallRuleName ,            
    #SFirst IP Adress of Ranage of IP's that have access to database. it is use for Firewall rules
    [Parameter(Mandatory = $true)]
    [String]$StartIPAddress,               
    #Last IP Adress of Ranage of IP's that have access to database. it is use for Firewall rules
    [Parameter(Mandatory = $true)]
    [String]$EndIPAddress,       
    #Database Server Location          
    [Parameter(Mandatory = $true)]
    [String]$Location                      
)

<#
.Synopsis
    Get the IP Range needed to be whitelisted for SQL Azure
.OUTPUTS
    Client IP Adress
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
.Synopsis
    3. Generate connection string of a given SQL Azure database
.EXAMPLE
    Get-SQLAzureDatabaseConnectionString -DatabaseServerName $databaseServer.ServerName -DatabaseName $AppDatabaseName -SqlDatabaseUserName $SqlDatabaseUserName  -Password $Password
.OUTPUT
    Connection String
#>
Function Get-SQLAzureDatabaseConnectionString
{
    Param(
        #Database Server Name
        [String]$DatabaseServerName,
        #Database name
        [String]$DatabaseName,
        #Database User Name
        [String]$SqlDatabaseUserName ,
        #Database User Password
        [String]$Password
    )

    Return "Server=tcp:{0}.database.windows.net,1433;Database={1};User ID={2}@{0};Password={3};Trusted_Connection=False;Encrypt=True;Connection Timeout=30;" -f
        $DatabaseServerName, $DatabaseName, $SqlDatabaseUserName , $Password
}
<#
.Synopsis
    This script create Azure SQl Server and Database
.EXAMPLE     How to Run this script
    .\New-AzureSql.ps1 "            -AppDatabaseName "XXXXXX" 
            -StartIPAddress "XXXXXX" 
            -EndIPAddress "XXXXXX" 
            -Location "XXXXXX 
            -FirewallRuleName ""XXXX"
    
.OUTPUTS
    Database connection string in a hastable
#>

Function CreateAzureSqlDB
{
Param(
    #Application database name
    [Parameter(Mandatory = $true)]
    [String]$AppDatabaseName,   
    #Database server firewall rule name
    [Parameter(Mandatory = $true)]
    [String]$FirewallRuleName ,            
    #First IP Adress of Ranage of IP's that have access to database. it is use for Firewall rules
    [Parameter(Mandatory = $true)]
    [String]$StartIPAddress,               
    #Last IP Adress of Ranage of IP's that have access to database. it is use for Firewall rules
    [Parameter(Mandatory = $true)]
    [String]$EndIPAddress,       
    #Database Server Location          
    [Parameter(Mandatory = $true)]
    [String]$Location                      
)

#a. Detect IP range for SQL Azure whitelisting if the IP range is not specified
If (-not ($StartIPAddress -and $EndIPAddress))
{
    $ipRange = Detect-IPAddress
    $StartIPAddress = $ipRange.StartIPAddress
    $EndIPAddress = $ipRange.EndIPAddress
}

#b. Prompt a Credential
$credential = Get-Credential
#c Create Server
Write-Verbose ("[Start] creating SQL Azure database server in location {0} with username {1} and password {2}" -f $Location, $credential.UserName , $credential.GetNetworkCredential().Password)
$databaseServer = New-AzureSqlDatabaseServer -AdministratorLogin $credential.UserName  -AdministratorLoginPassword $credential.GetNetworkCredential().Password -Location $Location
Write-Verbose ("[Finish] creating SQL Azure database server {3} in location {0} with username {1} and password {2}" -f $Location, $credential.UserName , $credential.GetNetworkCredential().Password, $databaseServer.ServerName)

#C. Create a SQL Azure database server firewall rule for the IP address of the machine in which this script will run
# This will also whitelist all the Azure IP so that the website can access the database server
Write-Verbose ("[Start] creating firewall rule {0} in database server {1} for IP addresses {2} - {3}" -f $RuleName, $databaseServer.ServerName, $StartIPAddress, $EndIPAddress)
New-AzureSqlDatabaseServerFirewallRule -ServerName $databaseServer.ServerName -RuleName $FirewallRuleName -StartIpAddress $StartIPAddress -EndIpAddress $EndIPAddress -Verbose
New-AzureSqlDatabaseServerFirewallRule -ServerName $databaseServer.ServerName -RuleName "AllowAllAzureIP" -StartIpAddress "0.0.0.0" -EndIpAddress "0.0.0.0" -Verbose
Write-Verbose ("[Finish] creating firewall rule {0} in database server {1} for IP addresses {2} - {3}" -f $FirewallRuleName, $databaseServer.ServerName, $StartIPAddress, $EndIPAddress)

#d. Create a database context which includes the server name and credential
$context = New-AzureSqlDatabaseServerContext -ServerName $databaseServer.ServerName -Credential $credential 

# e. Use the database context to create app database
Write-Verbose ("[Start] creating database {0} in database server {1}" -f $AppDatabaseName, $databaseServer.ServerName)
New-AzureSqlDatabase -DatabaseName $AppDatabaseName -Context $context -Verbose
Write-Verbose ("[Finish] creating database {0} in database server {1}" -f $AppDatabaseName, $databaseServer.ServerName)

#f. Generate the ConnectionString
[string] $appDatabaseConnectionString = Get-SQLAzureDatabaseConnectionString -DatabaseServerName $databaseServer.ServerName -DatabaseName $AppDatabaseName -SqlDatabaseUserName $credential.UserName  -Password $credential.GetNetworkCredential().Password

#g.Return Database connection string
   Return @{ConnectionString = $appDatabaseConnectionString;}
}

#1. Main Script
$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"
#Create Azure Sql Server and Database
$appDbConnectionString= CreateAzureSqlDB -AppDatabaseName $AppDatabaseName  -FirewallRuleName $FirewallRuleName -StartIPAddress $StartIPAddress -EndIPAddress $EndIPAddress -Location $Location 
#return ConnectionString
Return  $appDbConnectionString.ConnectionString