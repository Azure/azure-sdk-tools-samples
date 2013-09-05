<#
.Synopsis
   This scripts take a Package (*.cspkg) and config file (*.cscfg) to create a 
   corporate site on Web Role with Azure SQL application database and Storage 
   Account.
.DESCRIPTION
   This sample script demonstrating how deploy a DotNet corporate site into a
    Cloud Services with SQL Database and Storage Acoount.
    During de process, it will create Storage Account, Azure Sql Database, 
    Cloud Services and change de configuration file (*.cscfg)  of the project.

    At the end of the script it start the browser and shows the site. The sample
    package has a Web site that check the Azure SQL  and Storage connection 
.EXAMPLE
    Use the following to Deploy the project
    $test = & ".\Create-AzureEnterpriseSite.ps1"  `
        -ServiceName "jpggTest"  `
        -ServiceLocation "West US" `
        -sqlAppDatabaseName "myDB" `
        -StartIPAddress "1.0.0.1" `
        -EndIPAddress "255.255.255.255" `
        -ConfigurationFilePath ".\EnterpiseSite\ServiceConfiguration.Cloud.cscfg" `
        -PackageFilePath ".\EnterpiseSite\WebCorpHolaMundo.Azure.cspkg"

.OUTPUTS
   Write in Host the time spended in the script execution
#>
#1. Parameters
Param(
    #Cloud services Name
    [Parameter(Mandatory = $true)]
    [String]$ServiceName,            
    #Cloud Service location 
    [Parameter(Mandatory = $true)]
    [String]$ServiceLocation,     
    #Database application name   
    [Parameter(Mandatory = $true)]
    [String]$sqlAppDatabaseName,     
    #First IP Adress of Ranage of IP's that have access to database. it is use for Firewall rules
    [Parameter(Mandatory = $true)]            
    [String]$StartIPAddress,   
    #Last IP Adress of Ranage of IP's that have access to database. it is use for Firewall rules  
    [Parameter(Mandatory = $true)]                             
    [String]$EndIPAddress,         
    #Path to configuration file (*.cscfg)     
    [Parameter(Mandatory = $true)]                             
    [String]$ConfigurationFilePath,   
    #PackageFilePath:        Path to Package file (*.cspkg)          
    [Parameter(Mandatory = $true)]                             
    [String]$PackageFilePath            
)
<#2.1 CreateCloudService
.Synopsis
This function create a Cloud Services if this Cloud Service don't exists.

.DESCRIPTION
    This function try to obtain the services using $MyServiceName. If we have
    an exception it is mean the Cloud services don’t exist and create it.
.EXAMPLE
    CreateCloudService  "ServiceName" "ServiceLocation"
#> 
Function CreateCloudService 
{
 Param(
    #Cloud services Name
    [Parameter(Mandatory = $true)]
    [String]$MyServiceName,
    #Cloud service Location 
    [Parameter(Mandatory = $true)]
    [String]$MyServiceLocation     
    )

 try
 {
    $CloudService = Get-AzureService -ServiceName $MyServiceName
    Write-Verbose ("cloud service {0} in location {1} exist!" -f $MyServiceName, $MyServiceLocation)
 }
 catch
 { 
   #Create
   Write-Verbose ("[Start] creating cloud service {0} in location {1}" -f $MyServiceName, $MyServiceLocation)
   New-AzureService -ServiceName $MyServiceName -Location $MyServiceLocation
   Write-Verbose ("[Finish] creating cloud service {0} in location {1}" -f $MyServiceName, $MyServiceLocation)
 }
}
<#2.2 CreateStorage
.Synopsis
This function create a Storage Account if it don't exists.

.DESCRIPTION
This function try to obtain the Storage Account using $MyStorageName. If we have
 an exception it is mean the Storage Account don’t exist and create it.

.OUTPUTS
    Storage Account connectionString
.EXAMPLE
   CreateStorage -MyStorageAccountName $StorageAccountName -MyStorageLocation $ServiceLocation 
#>
Function CreateStorage
{
Param (
    #Storage Account  Name
    [Parameter(Mandatory = $true)]
    [String]$MyStorageAccountName,
    #Storage Account   Location 
    [Parameter(Mandatory = $true)]
    [String]$MyStorageLocation 
)
    try
    {
        $myStorageAccount= Get-AzureStorageAccount -StorageAccountName $MyStorageAccountName
        Write-Verbose ("Storage account {0} in location {1} exist" -f $MyStorageAccountName, $MyStorageLocation)
    }
    catch
    {
        # Create a new storage account
        Write-Verbose ("[Start] creating storage account {0} in location {1}" -f $MyStorageAccountName, $MyStorageLocation)
        New-AzureStorageAccount -StorageAccountName $MyStorageAccountName -Location $MyStorageLocation -Verbose
        Write-Verbose ("[Finish] creating storage account {0} in location {1}" -f $MyStorageAccountName, $MyStorageLocation)
    }

    # Get the access key of the storage account
    $key = Get-AzureStorageKey -StorageAccountName $MyStorageAccountName

    # Generate the connection string of the storage account
    $connectionString ="BlobEndpoint=http://{0}.blob.core.windows.net/;" -f $MyStorageAccountName
    $connectionString =$connectionString + "QueueEndpoint=http://{0}.queue.core.windows.net/;" -f $MyStorageAccountName
    $connectionString =$connectionString + "TableEndpoint=http://{0}.table.core.windows.net/;" -f $MyStorageAccountName
    $connectionString =$connectionString + "AccountName={0};AccountKey={1}" -f $MyStorageAccountName, $key.Primary

    Return @{ConnectionString = $connectionString}
}
<#2.3 Update-Cscfg
.Synopsis
    This function update Cloud Services configuration file with the Azure SQL and Storage account information
.DESCRIPTION
    It load XML file and looking for “dbApplication” and “Storage” XML TAG with the current Azure SQL and Storage account.
    It save updated configuration in a temporal file. 
.EXAMPLE
    Update-Cscfg  `
            -MyConfigurationFilePath $ConfigurationFilePath  `
            -MySqlConnStr $sql.AppDatabase.ConnectionString `
            -MyStorageConnStr $Storage.ConnectionString
.OUTPUTS
   file Path to temp configuration file updated
#>
Function Update-Cscfg 
{
Param (
    #Path to configuration file (*.cscfg)
    [Parameter(Mandatory = $true)]
    [String]$MyConfigurationFilePath,
    #Azure SQL connection string 
    [Parameter(Mandatory = $true)]
    [String]$MySqlConnStr ,
    #Storage Account connection String 
    [Parameter(Mandatory = $true)]
    [String]$MyStorageConnStr 
)
    # Get content of the project source cscfg file
    [Xml]$cscfgXml = Get-Content $MyConfigurationFilePath
    Foreach ($role in $cscfgXml.ServiceConfiguration.Role)
    {
        Foreach ($setting in $role.ConfigurationSettings.Setting)
        {
            Switch ($setting.name)
            {
                "dbApplication" {$setting.value =$MySqlConnStr} #AppDatabase
                "Storage" {$setting.value = $MyStorageConnStr}  #Storage
            }
        }
    }
    #Save the change
    $file = "{0}\EnterpiseSite\ServiceConfiguration.Ready.cscfg" -f $ScriptPath
    $cscfgXml.InnerXml | Out-File -Encoding utf8 $file
    Return $file
}
<# 2.4 DeployPackage
.Synopsis
    It deploy service’s  package with his configuration to a Cloud Services 
.DESCRIPTION
    it function try to obtain the Services deployments by name. If exists this deploy is update. In other case,
     it create a Deploy and does the upload.
.EXAMPLE
   DeployPackage -MyServiceName $ServiceName -MyConfigurationFilePath $NewcscfgFilePath -MyPackageFilePath $PackageFilePath         
#>
Function DeployPackage 
{
Param(
    #Cloud Services name
    [Parameter(Mandatory = $true)]
    [String]$MyServiceName,
    #Path to configuration file (*.cscfg)
    [Parameter(Mandatory = $true)]
    [String]$MyConfigurationFilePath,
    #Path to package file (*.cspkg)
    [Parameter(Mandatory = $true)]
    [String]$MyPackageFilePath
)
    Try
    {
        Get-AzureDeployment -ServiceName $MyServiceName
        Write-Verbose ("[Start] Deploy Service {0}  exist, Will update" -f $MyServiceName)
        Set-AzureDeployment `
            -ServiceName $MyServiceName `
            -Slot Production `
            -Configuration $MyConfigurationFilePath `
            -Package $MyPackageFilePath `
            -Mode Simultaneous -Upgrade
        Write-Verbose ("[finish] Deploy Service {0}  exist, Will update" -f $MyServiceName)
    }
    Catch
    {
        Write-Verbose ("[Start] Deploy Service {0} don't exist, Will create" -f $MyServiceName)
        New-AzureDeployment -ServiceName $MyServiceName -Slot Production -Configuration $MyConfigurationFilePath -Package $MyPackageFilePath
        Write-Verbose ("[Finish] Deploy Service {0} don't exist, Will create" -f $MyServiceName)
    }
    
}
<#2.5 WaitRoleInstanceReady
.Synopsis
    it wait all role instance are ready
.DESCRIPTION
    Wait until al instance of Role are ready
.EXAMPLE
  WaitRoleInstanceReady $ServiceName
#>
function WaitRoleInstanceReady 
{
Param(
    #Cloud Services name
    [Parameter(Mandatory = $true)]
    [String]$MyServiceName
)
    Write-Verbose ("[Start] Waiting for Instance Ready")
    do
    {
        $MyDeploy = Get-AzureDeployment -ServiceName $MyServiceName  
        foreach ($Instancia in $MyDeploy.RoleInstanceList)
        {
            $switch=$true
            Write-Verbose ("Instance {0} is in state {1}" -f $Instancia.InstanceName, $Instancia.InstanceStatus )
            if ($Instancia.InstanceStatus -ne "ReadyRole")
            {
                $switch=$false
            }
        }
        if (-Not($switch))
        {
            Write-Verbose ("Waiting Azure Deploy running, it status is {0}" -f $MyDeploy.Status)
            Start-Sleep -s 10
        }
        else
        {
            Write-Verbose ("[Finish] Waiting for Instance Ready")
        }
    }
    until ($switch)
}


<#2.6 Detect-IPAddress
.Synopsis
    Get the IP Range needed to be whitelisted for SQL Azure
.OUTPUTS
    Client IP Address
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
<#2.7 Get-SQLAzureDatabaseConnectionString
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
<#2.8 CreateAzureSqlDB
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



# 3.0 Same variables tu use in the Script
$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"
# Get the directory of the current script
$ScriptPath = Split-Path -parent $PSCommandPath
# Mark the start time of the script execution
$StartTime = Get-Date
# Define the names of storage account, SQL Azure database and SQL Azure database server firewall rule
$ServiceName = $ServiceName.ToLower()
$StorageAccountName = "{0}storage" -f $ServiceName
$SqlDatabaseServerFirewallRuleName = "{0}rule" -f $ServiceName

# 3.1 Create a new cloud service?
#creating Windows Azure cloud service environment
Write-Verbose ("[Start] Validating  Windows Azure cloud service environment {0}" -f $ServiceName)
CreateCloudService  $ServiceName $ServiceLocation

#3.2 Create a new storage account
$Storage = CreateStorage -MyStorageAccountName $StorageAccountName -MyStorageLocation $ServiceLocation

#3.3 Create a SQL Azure database server and Application Database
[string] $SqlConn = CreateAzureSqlDB `
        -AppDatabaseName $sqlAppDatabaseName `
        -StartIPAddress $StartIPAddress `
        -EndIPAddress $EndIPAddress -FirewallRuleName $SqlDatabaseServerFirewallRuleName `
        -Location $ServiceLocation

Write-Verbose ("[Finish] creating Windows Azure cloud service environment {0}" -f $ServiceName)

# 3.4 Upgrade configuration  File with the SQL and Storage references
$NewcscfgFilePath = Update-Cscfg  `
            -MyConfigurationFilePath $ConfigurationFilePath  `
            -MySqlConnStr $SqlConn `
            -MyStorageConnStr $Storage.ConnectionString
Write-Verbose ("New Config File {0}" -f $NewcscfgFilePath)

# 3.5 Deploy Package
DeployPackage -MyServiceName $ServiceName -MyConfigurationFilePath $NewcscfgFilePath -MyPackageFilePath $PackageFilePath

#3.5.1 Delete temporal configFile
Remove-Item $NewcscfgFilePath

# 3.6 Wait Role isntances Ready
WaitRoleInstanceReady $ServiceName


#4.1 Mark the finish time of the script execution
#    Output the time consumed in seconds
$finishTime = Get-Date

Write-Host ("Total time used (seconds): {0}" -f ($finishTime - $StartTime).TotalSeconds)

#4.2 Launch the Site
Start-Process -FilePath ("http://{0}.cloudapp.net" -f $ServiceName)
