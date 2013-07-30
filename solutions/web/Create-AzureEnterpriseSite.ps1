<#
#Description
This scripts take a Package and config file to create a corporate site with Azure SQL application database and Storage Account

#Prerequisites 
a.	Configuration file  ServiceConfiguration.Cloud.cscfg
b.	Package file WebCorpHolaMundo.Azure.cspkg

#References scripts files
a. ".\New-AzureSql.ps1"

#How to call
$test = & ".\Create-AzureEnterpriseSite.ps1"  `
    -ServiceName "jpggTest"  `
    -ServiceLocation "West US" `
    -sqlAppDatabaseName "myDB" `
    -SqlDatabasePassword "lala@lolo123qwew"  `
    -StartIPAddress "1.0.0.1" `
    -EndIPAddress "255.255.255.255" `
    -SqlDatabaseUserName "dbuser"`
    -cscfgFilePath ".\EnterpiseSite\ServiceConfiguration.Cloud.cscfg" `
    -cspkgFilePath ".\EnterpiseSite\WebCorpHolaMundo.Azure.cspkg"
#>
#1. Parameters
Param(
    [Parameter(Mandatory = $true)]
    [String]$ServiceName,            #Service Name
    [Parameter(Mandatory = $true)]
    [String]$ServiceLocation,        #Service Location
    [Parameter(Mandatory = $true)]
    [String]$sqlAppDatabaseName,     #Database Application Name
    [Parameter(Mandatory = $true)]
    [String]$SqlDatabasePassword,    #Database Password 
    [Parameter(Mandatory = $true)]
    [String]$SqlDatabaseUserName ,   #User Name
    [Parameter(Mandatory = $true)]            
    [String]$StartIPAddress,         #SQL Azure firewall start IP
    [Parameter(Mandatory = $true)]                             
    [String]$EndIPAddress,           #SQL Azure firewall finish IP   
    [Parameter(Mandatory = $true)]                             
    [String]$cscfgFilePath,          #Configuration File   
    [Parameter(Mandatory = $true)]                             
    [String]$cspkgFilePath           #Package File 
)
#----------------------------------------------------------------------------------------------------
#2. functions
#----------------------------------------------------------------------------------------------------
#2.1 CreateCloudServicesIfNecesary
# [TODO] Description.
Function CreateCloudServicesIfNecesary ($ServiceNameToCheck, $ServiceLocationToUse )  
{
    try
    {
        $CloudService = Get-AzureService -ServiceName $ServiceNameToCheck
        Write-Verbose ("cloud service {0} in location {1} exist!" -f $ServiceNameToCheck, $ServiceLocationToUse)
    }
    catch
    { 
        #Create
        Write-Verbose ("[Start] creating cloud service {0} in location {1}" -f $ServiceNameToCheck, $ServiceLocationToUse)
        New-AzureService -ServiceName $ServiceNameToCheck -Location $ServiceLocationToUse
        Write-Verbose ("[Finish] creating cloud service {0} in location {1}" -f $ServiceNameToCheck, $ServiceLocationToUse)
    }
}
#2.2 CreateStorageIfNecesary
#[TODO] Description.
Function CreateStorageIfNecesary($StorageNameToCheck,$StorageLocationToUse)
{
    try
    {
        $myStorageAccount= Get-AzureStorageAccount $StorageNameToCheck
        Write-Verbose ("Storage account {0} in location {1} exist" -f $StorageNameToCheck, $StorageLocationToUse)
    }
    catch
    {
        # Create a new storage account
        Write-Verbose ("[Start] creating storage account {0} in location {1}" -f $StorageNameToCheck, $StorageLocationToUse)
        New-AzureStorageAccount -StorageAccountName $StorageNameToCheck -Location $StorageLocationToUse -Verbose
        Write-Verbose ("[Finish] creating storage account {0} in location {1}" -f $StorageNameToCheck, $StorageLocationToUse)
    }

    # Get the access key of the storage account
    $key = Get-AzureStorageKey -StorageAccountName $StorageNameToCheck

    # Generate the connection string of the storage account
    $connectionString = "BlobEndpoint=http://{0}.blob.core.windows.net/;QueueEndpoint=http://{0}.queue.core.windows.net/;TableEndpoint=http://{0}.table.core.windows.net/;AccountName={0};AccountKey={1}" -f $StorageNameToCheck, $key.Primary

    Return @{AccountName = $StorageNameToCheck; AccessKey = $key.Primary; ConnectionString = $connectionString}
}
#2.3 Update-Cscfg
#
Function Update-Cscfg([String] $SourceCscfgFile, [String]$SqlConnStr, [String] $StorageConnStr)
{
    # Get content of the project source cscfg file
    [Xml]$cscfgXml = Get-Content $SourceCscfgFile
    Foreach ($role in $cscfgXml.ServiceConfiguration.Role)
    {
        Foreach ($setting in $role.ConfigurationSettings.Setting)
        {
            Switch ($setting.name)
            {
                "dbApplication" {$setting.value =$SqlConnStr} #AppDatabase
                "Storage" {$setting.value = $StorageConnStr}  #Storage
            }
        }
    }
    #Save the change
    $file = "{0}\EnterpiseSite\ServiceConfiguration.Ready.cscfg" -f $scriptPath
    $cscfgXml.InnerXml | Out-File -Encoding utf8 $file
    Return $file
}
# 2.4 DeployPackage
# If there is no existing deployment on the cloud service, create a new deployment
# Otherwise, upgrade the deployment using simultaneous mode
# Notice: first time deployment always uses simultaneous mode
Function DeployPackage ($myServiceName,$myscfgFilePath,$mycspkgFilePath)
{
    Try
    {
        Get-AzureDeployment -ServiceName $myServiceName
        Write-Verbose ("[Start] Deploy Service {0}  exist, Will update" -f $myServiceName)
        Set-AzureDeployment -ServiceName $myServiceName -Slot Production -Configuration $myscfgFilePath -Package $mycspkgFilePath -Mode Simultaneous -Upgrade
        Write-Verbose ("[finish] Deploy Service {0}  exist, Will update" -f $myServiceName)
    }
    Catch
    {
        Write-Verbose ("[Start] Deploy Service {0} don't exist, Will create" -f $myServiceName)
        New-AzureDeployment -ServiceName $myServiceName -Slot Production -Configuration $myscfgFilePath -Package $mycspkgFilePath
        Write-Verbose ("[Finish] Deploy Service {0} don't exist, Will create" -f $myServiceName)
    }
    
}
#2.5 Wait intance Ready
#Wait until al instance of Role are ready
function WaitRoleInstanceReady ($myServiceName)
{
    Write-Verbose ("[Start] Waiting for Instance Ready")
    do
    {
        $myDeploy = Get-AzureDeployment -ServiceName $myServiceName  
        foreach ($instancia in $myDeploy.RoleInstanceList)
        {
            $switch=$true
            Write-Verbose ("Instance {0} is in state {1}" -f $instancia.InstanceName, $instancia.InstanceStatus )
            if ($instancia.InstanceStatus -ne "ReadyRole")
            {
                $switch=$false
            }
        }
        if (-Not($switch))
        {
            Write-Verbose ("Waiting Azure Deploy running, it status is {0}" -f $myDeploy.Status)
            Start-Sleep -s 10
        }
        else
        {
            Write-Verbose ("[Finish] Waiting for Instance Ready")
        }
    }
    until ($switch)
}
#----------------------------------------------------------------------------------------------------
#3. Main Script
#----------------------------------------------------------------------------------------------------
# 3.0 Same variables tu use in the Script
$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"
# Get the directory of the current script
$scriptPath = Split-Path -parent $PSCommandPath
# Mark the start time of the script execution
$startTime = Get-Date
# Define the names of storage account, SQL Azure database and SQL Azure database server firewall rule
$ServiceName = $ServiceName.ToLower()
$storageAccountName = "{0}storage" -f $ServiceName
$sqlDatabaseServerFirewallRuleName = "{0}rule" -f $ServiceName

# 3.1 Create a new cloud service?
#creating Windows Azure cloud service environment
Write-Verbose ("[Start] Validating  Windows Azure cloud service environment {0}" -f $ServiceName)
CreateCloudServicesIfNecesary $ServiceName $ServiceLocation

#3.2 Create a new storage account
$storage = CreateStorageIfNecesary -StorageNameToCheck $storageAccountName -StorageLocationToUse $ServiceLocation

#3.3 Create a SQL Azure database server and Application Database
$sql = & "$scriptPath\New-AzureSql.ps1" `
        -Password $SqlDatabasePassword -AppDatabaseName $sqlAppDatabaseName -SqlDatabaseUserName $SqlDatabaseUserName `
        -StartIPAddress $StartIPAddress -EndIPAddress $EndIPAddress -FirewallRuleName $sqlDatabaseServerFirewallRuleName -Location $ServiceLocation

Write-Verbose ("[Finish] creating Windows Azure cloud service environment {0}" -f $ServiceName)

# 3.4 Upgrade configuration  File with the SQL and Storage references
$NewcscfgFilePath = Update-Cscfg  -SourceCscfgFile $cscfgFilePath  -SqlConnStr $sql.AppDatabase.ConnectionString -StorageConnStr $storage.ConnectionString
Write-Verbose ("New Config File {0}" -f $NewcscfgFilePath)

# 3.5 Deploy Package
DeployPackage -myServiceName $ServiceName -myscfgFilePath $NewcscfgFilePath -mycspkgFilePath $cspkgFilePath

# 3.6 Wait Role isntances Ready
WaitRoleInstanceReady $ServiceName

#----------------------------------------------------------------------------------------------------
#4. Output
#----------------------------------------------------------------------------------------------------

#4.1 Mark the finish time of the script execution
#    Output the time consumed in seconds
$finishTime = Get-Date

Write-Host ("Total time used (seconds): {0}" -f ($finishTime - $startTime).TotalSeconds)

#4.2 Launch the Site
Start-Process -FilePath ("http://{0}.cloudapp.net" -f $ServiceName)
