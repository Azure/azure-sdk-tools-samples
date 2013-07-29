<#
#0. Description
Web site over cloud Services with Azure SQl Database  and Blob Storage.
Pre-Req
a. publishing settings for your Windows Azure account
b. Use Default Storage
References files
a. ".\New-AzureSql.ps1"
b. ".\cloud-service-environment.template"
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
    [String]$EndIPAddress            #SQL Azure firewall finish IP   
)
#----------------------------------------------------------------------------------------------------
#2. functions
#----------------------------------------------------------------------------------------------------
#2.1 CreateCloudServicesIfNecesary
# [TODO] Description.
Function CreateCloudServicesIfNecesary ($ServiceNameToCheck, $ServiceLocationToUse )  
{
    $ExistService=$false

    ForEach ($serviceX in Get-AzureService)
    {
         Write-Verbose("Service Name {0}" -f $serviceX.ServiceName)
        if ($serviceX.ServiceName -eq $ServiceNameToCheck)
        {
             $ExistService=$true
             break
        }
    }
    if (-Not ($ExistService))
    {
        #Create
        Write-Verbose ("[Start] creating cloud service {0} in location {1}" -f $ServiceNameToCheck, $ServiceLocationToUse)
        New-AzureService -ServiceName $ServiceNameToCheck -Location $ServiceLocationToUse
        Write-Verbose ("[Finish] creating cloud service {0} in location {1}" -f $ServiceNameToCheck, $ServiceLocationToUse)
        
    }
    else
    {
        #Cloud Services Exist
         Write-Verbose ("cloud service {0} in location {1} exist!" -f $ServiceNameToCheck, $ServiceLocationToUse)
    }
}
#2.2 CreateStorageIfNecesary
#[TODO] Description.
Function CreateStorageIfNecesary($StorageNameToCheck,$StorageLocationToUse)
{
    $ExistService=$false
    foreach ($storageX in Get-AzureStorageAccount)
    {
        if ($storageX.StorageAccountName -eq $StorageNameToCheck)
        {
            $ExistService=$true
             break
        }
    }

    if (-Not ($ExistService))
    {
        # Create a new storage account
        Write-Verbose ("[Start] creating storage account {0} in location {1}" -f $StorageNameToCheck, $StorageLocationToUse)
        New-AzureStorageAccount -StorageAccountName $StorageNameToCheck -Location $StorageLocationToUse -Verbose
        Write-Verbose ("[Finish] creating storage account {0} in location {1}" -f $StorageNameToCheck, $StorageLocationToUse)
    }
    else
    {
         Write-Verbose ("Storage account {0} in location {1} exist!" -f $StorageNameToCheck, $StorageLocationToUse)
    }

    # Get the access key of the storage account
    $key = Get-AzureStorageKey -StorageAccountName $StorageNameToCheck

    # Generate the connection string of the storage account
    $connectionString = "BlobEndpoint=http://{0}.blob.core.windows.net/;QueueEndpoint=http://{0}.queue.core.windows.net/;TableEndpoint=http://{0}.table.core.windows.net/;AccountName={0};AccountKey={1}" -f $StorageNameToCheck, $key.Primary

    Return @{AccountName = $StorageNameToCheck; AccessKey = $key.Primary; ConnectionString = $connectionString}
}
#2.3 Generate-EnvironmentXml
#Generate environment xml file, which will be used by the deploy script later.
Function Generate-EnvironmentXml
{
    Param(
        [String]$EnvironmentName,
        [String]$CloudServiceName,
        [Object]$Storage,
        [Object]$Sql
    )

    [String]$template = Get-Content ("{0}\cloud-service-environment.template" -f $scriptPath)
    

    $xml = $template -f $EnvironmentName, $CloudServiceName, `
                        $Storage.AccountName, $Storage.AccessKey, $Storage.ConnectionString, `
                        ([String]$Sql.Server).Trim(), $Sql.UserName, $Sql.Password, `
                        $Sql.AppDatabase.Name, $Sql.AppDatabase.ConnectionString
    
    $xml | Out-File -Encoding utf8 ("{0}\cloud-service-environment.xml" -f $scriptPath)
}

#----------------------------------------------------------------------------------------------------
#3. Main Script
#----------------------------------------------------------------------------------------------------
$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"
# Get the directory of the current script
$scriptPath = Split-Path -parent $PSCommandPath
# Mark the start time of the script execution
$startTime = Get-Date

#creating Windows Azure cloud service environment
Write-Verbose ("[Start] Validating  Windows Azure cloud service environment {0}" -f $ServiceName)
# Define the names of storage account, SQL Azure database and SQL Azure database server firewall rule
$ServiceName = $ServiceName.ToLower()
$storageAccountName = "{0}storage" -f $ServiceName
$sqlDatabaseServerFirewallRuleName = "{0}rule" -f $ServiceName


# 3.1 Create a new cloud service?
CreateCloudServicesIfNecesary $ServiceName $ServiceLocation

#3.2 Create a new storage account
$storage = CreateStorageIfNecesary -StorageNameToCheck $storageAccountName -StorageLocationToUse $ServiceLocation

#3.3 Create a SQL Azure database server and Application Database
$sql = & "$scriptPath\New-AzureSql.ps1" `
        -Password $SqlDatabasePassword -AppDatabaseName $sqlAppDatabaseName -SqlDatabaseUserName $SqlDatabaseUserName `
        -StartIPAddress $StartIPAddress -EndIPAddress $EndIPAddress -FirewallRuleName $sqlDatabaseServerFirewallRuleName -Location $ServiceLocation

#3.4 Set the default storage account of the subscription
# This storage account will be used when deploying the cloud service cspkg
$AzureSubscription = Get-AzureSubscription -Current 
Set-AzureSubscription -SubscriptionName $AzureSubscription.SubscriptionName -CurrentStorageAccount $storage.AccountName

Write-Verbose ("[Finish] creating Windows Azure cloud service environment {0}" -f $ServiceName)

#3.5 Write the environment info to an xml file so that the deploy script can consume
Write-Verbose "[Begin] writing environment info to cloud-service-environment.xml"
Generate-EnvironmentXml -EnvironmentName $ServiceName -CloudServiceName $ServiceName -Storage $storage -Sql $sql
Write-Verbose ("{0}\cloud-service-environment.xml" -f $scriptPath)
Write-Verbose "[Finish] writing environment info to cloud-service-environment.xml"

#3.6 Upload project
[TODO]

#----------------------------------------------------------------------------------------------------
#4. Output
#----------------------------------------------------------------------------------------------------
#4.1 Mark the finish time of the script execution
#    Output the time consumed in seconds
$finishTime = Get-Date
Write-Host ("Total time used (seconds): {0}" -f ($finishTime - $startTime).TotalSeconds)

Return @{SqlServer= ([String]$Sql.Server).Trim(); Storage=$storage}