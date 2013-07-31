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

    at the end of the script it start the browser and shows the site. The sample
    package has a Web site that check the Azure SQL  and Storage connection 
   
   This scritp use ".\New-AzureSql.ps1" to crear Azure SQL Database
.EXAMPLE
    Use the following to Deploy the project
    $test = & ".\Create-AzureEnterpriseSite.ps1"  `
        -ServiceName "jpggTest"  `
        -ServiceLocation "West US" `
        -sqlAppDatabaseName "myDB" `
        -SqlDatabasePassword "lala@lolo123qwew"  `
        -StartIPAddress "1.0.0.1" `
        -EndIPAddress "255.255.255.255" `
        -SqlDatabaseUserName "dbuser"`
        -ConfigurationFilePath ".\EnterpiseSite\ServiceConfiguration.Cloud.cscfg" `
        -PackageFilePath ".\EnterpiseSite\WebCorpHolaMundo.Azure.cspkg"
.INPUTS
   Parameters
   $ServiceName:            Cloud services Name
   $ServiceLocation:        Cloud Service location 
   $sqlAppDatabaseName:     Database application name
   $SqlDatabasePassword:    User database Password
   $SqlDatabaseUserName:    User database Name
   $StartIPAddress:         First IP Adress of Ranage of IP's that have access 
                            to database. it is use for Firewall rules
   $EndIPAddress:           Last IP Adress of Ranage of IP's that have access 
                            to database. it is use for Firewall rules
   $ConfigurationFilePath:  Path to configuration file (*.cscfg)
   $PackageFilePath:        Path to Package file (*.cspkg)
.OUTPUTS
   Write in Host the time spended in the script execution
#>
#1. Parameters
Param(
    [Parameter(Mandatory = $true)]
    [String]$ServiceName,            
    [Parameter(Mandatory = $true)]
    [String]$ServiceLocation,        
    [Parameter(Mandatory = $true)]
    [String]$sqlAppDatabaseName,     
    [Parameter(Mandatory = $true)]
    [String]$SqlDatabasePassword,    
    [Parameter(Mandatory = $true)]
    [String]$SqlDatabaseUserName ,   
    [Parameter(Mandatory = $true)]            
    [String]$StartIPAddress,         
    [Parameter(Mandatory = $true)]                             
    [String]$EndIPAddress,              
    [Parameter(Mandatory = $true)]                             
    [String]$ConfigurationFilePath,             
    [Parameter(Mandatory = $true)]                             
    [String]$PackageFilePath            
)
<#2.1 CreateCloudService
.Synopsis
This function create a Cloud Services if this Cloud Service don't exists.

.DESCRIPTION
This function try to obtain the services using $MyServiceName. If we have
 an exception it is mean the Cloud services don’t exist and create it.

.INPUTS
    $MyServiceName:      Cloud services Name
    $MyServiceLocation:  Cloud service Location 

.OUTPUTS
   none
#> 
Function CreateCloudService ($MyServiceName, $MyServiceLocation )  
{
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

.INPUTS
    $MyStorageName:      Storage Account Name
    $MyStorageLocation:  Storage Account Location 

.OUTPUTS
   Hastable
        MyStorageAccountName:      Storage Account Name
        AccessKey:        Storage primary Accesskey
        ConnectionString: Storage connection string
#>
Function CreateStorage($MyStorageAccountName,$MyStorageLocation)
{
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

    Return @{AccountName = $MyStorageName; AccessKey = $key.Primary; ConnectionString = $connectionString}
}
<#2.3 Update-Cscfg
.Synopsis
    This function update Cloud Services configuration file with the Azure SQL and Storage account information
.DESCRIPTION
    It load XML file and looking for “dbApplication” and “Storage” XML TAG with the current Azure SQL and Storage account.
    It save updated configuration in a temporal file. 
.INPUTS
    MyConfigurationFilePath: Path to configuration file (*.cscfg)
    MySqlConnStr:            Azure SQL connection string
    MyStorageConnStr:        Storage Account connection String
.OUTPUTS
   file:                     Path to temp configuration file updated
#>
Function Update-Cscfg([String] $MyConfigurationFilePath, [String]$MySqlConnStr, [String] $MyStorageConnStr)
{
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
.INPUTS
    MyServiceName:            Cloud Services name
    MyConfigurationFilePath:  Path to configuration file (*.cscfg)
    MyPackageFilePath:        Path to package file (*.cspkg)
.OUTPUTS
#>
Function DeployPackage ($MyServiceName,$MyConfigurationFilePath,$MyPackageFilePath)
{
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
.INPUTS
    MyServiceName:            Cloud Services name
.OUTPUTS
    none
#>
function WaitRoleInstanceReady ($MyServiceName)
{
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
CreateCloudService $ServiceName $ServiceLocation

#3.2 Create a new storage account
$Storage = CreateStorage -MyStorageAccountName $StorageAccountName -MyStorageLocation $ServiceLocation

#3.3 Create a SQL Azure database server and Application Database
$sql = & "$ScriptPath\New-AzureSql.ps1" `
        -Password $SqlDatabasePassword -AppDatabaseName $sqlAppDatabaseName `
        -SqlDatabaseUserName $SqlDatabaseUserName -StartIPAddress $StartIPAddress `
        -EndIPAddress $EndIPAddress -FirewallRuleName $SqlDatabaseServerFirewallRuleName `
        -Location $ServiceLocation

Write-Verbose ("[Finish] creating Windows Azure cloud service environment {0}" -f $ServiceName)

# 3.4 Upgrade configuration  File with the SQL and Storage references
$NewcscfgFilePath = Update-Cscfg  `
            -MyConfigurationFilePath $ConfigurationFilePath  `
            -MySqlConnStr $sql.AppDatabase.ConnectionString `
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
