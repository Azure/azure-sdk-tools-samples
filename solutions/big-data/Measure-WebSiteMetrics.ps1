<#
.SYNOPSIS
  This script analyzes Windows Azure Website application logs using transient HDInsight cluster.
.DESCRIPTION
  If azure web site is configured to store application logs in azure blob storage this script can be used to generate performance metrics of 
  the web site based on the following pattern in application log message: "Perf: <perfmetricname> took <number>". The script will calculate for each 
  perf metric found in the logs its average value and CSV formatted table of the metric values for each time-stamp. Processing of the data is performed on 
  the transient HDInsight cluster which is provisioned for the duration of the script execution. The script also creates new storage account to store output
  of the analysis. The output files can be imported into Excel or other graphing tool to build graphic chart of values.

  Note: This script uses AzCopy utility downloadable form here: http://go.microsoft.com/fwlink/?LinkId=287086

.EXAMPLE
  .\Measure-WebSiteMetrics.ps1 -Website "MyWebsiteName" -ApplicationLogStorage "MyWebSiteApplicationLogStorage"

  .\Measure-WebSiteMetrics.ps1 -Website "MyWebsiteName" -ApplicationLogStorage "MyWebSiteApplicationLogStorage"  `
      -Location "North Europe" -ClusterSizeInNodes 4
#>

param (
    # Azure Website name
    [Parameter(Mandatory = $true)]
    [String]$Website,

    # Storage account where application logs are located
    [Parameter(Mandatory = $true)]
    [String]$ApplicationLogStorage,
    
    # Azure region where HDInsight cluster will be created for log processing
    [Parameter(Mandatory = $false)]
    [String]$Location = "East US",
    
    # Number of data nodes that will be provisioned in the cluster
    [Parameter(Mandatory = $false)]
    [Int32]$ClusterSizeInNodes = 2)

function Get-Temppassword() {

    param(
        [int]$length=10)

    $ascii = $null
    $TempPassword = "Pw1"
    for ($a=48;$a –le 122;$a++) {$ascii+=,[char][byte]$a }
    for ($loop=1; $loop –le $length; $loop++) {
        $TempPassword+=($ascii | GET-RANDOM)
    }

    return $TempPassword
}

# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3

# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"

# Check if Windows Azure Powershell is available
if ((Get-Module -ListAvailable Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please make sure to install them from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}

# Check if input storage account exists
$logstore = Get-AzureStorageAccount -StorageAccountName $ApplicationLogStorage -ErrorAction SilentlyContinue
if ($logstore -eq $null)
{
    throw "Storage account '$ApplicationLogStorage' not found in the current subscription."
}

# Create storage account and container
$DefaultStorageAccount = "hdilog$Website".ToLowerInvariant()
    
# Check if account already exists then use it
$storageAccount = Get-AzureStorageAccount -StorageAccountName $DefaultStorageAccount -ErrorAction SilentlyContinue
if ($storageAccount -eq $null) {
    Write-Verbose "Creating new storage account $DefaultStorageAccount to store results of the analysis."
    New-AzureStorageAccount –StorageAccountName $DefaultStorageAccount -Location $Location
    $storageAccount = Get-AzureStorageAccount -StorageAccountName $DefaultStorageAccount
} else {
    Write-Verbose "Using existing storage account $DefaultStorageAccount to store results of the analysis."
}

# Check if container already exists then use it
$storageContext = New-AzureStorageContext –StorageAccountName $DefaultStorageAccount -StorageAccountKey (Get-AzureStorageKey $DefaultStorageAccount).Primary

$DefaultStorageContainer = $DefaultStorageAccount
$storageContainer = Get-AzureStorageContainer -Name $DefaultStorageContainer -Context $storageContext -ErrorAction SilentlyContinue
if ($storageContainer -eq $null) {
    Write-Verbose "Creating new storage container $DefaultStorageContainer to store results of the analysis."
    $storageContainer = New-AzureStorageContainer -Name $DefaultStorageContainer -Context $storageContext
} else {
    Write-Verbose "Using existing storage container $DefaultStorageContainer to store results of the analysis."
}

# Copy application logs to storage account that will be used by HDInsight cluster
Write-Verbose "Copying application logs for processing."
$modulebase = (Get-Module -ListAvailable Azure).ModuleBase
$azcopy = "$modulebase\..\..\AzCopy\AzCopy.exe"
$sourceUri = "http://$ApplicationLogStorage.blob.core.windows.net/wawsapplogblob$Website/$Website"
$sourceKey = (Get-AzureStorageKey $ApplicationLogStorage).Primary
$destUri = "http://$DefaultStorageAccount.blob.core.windows.net/$DefaultStorageContainer/input/$Website"
$destKey = (Get-AzureStorageKey $DefaultStorageAccount).Primary
& $azcopy $sourceUri $destUri /S /Y /SourceKey:$sourceKey /DestKey:$destKey

# Generate password for the cluster.
Write-Verbose "Creating transient HDInsight cluster to process application logs..."
$Cluster = $DefaultStorageAccount
$password = Get-Temppassword
Write-Verbose "Cluster '$Cluster' will be created with generated password '$password'."
$pwd = $password | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("admin",$pwd)

# Provision HDInsight cluster
New-AzureHDInsightCluster -Name $Cluster -Location $Location `
        -DefaultStorageAccountName ($storageAccount.StorageAccountName + ".blob.core.windows.net") `
        -DefaultStorageAccountKey (Get-AzureStorageKey $DefaultStorageAccount).Primary `
        -DefaultStorageContainerName $DefaultStorageContainer `
        -Credential $credential `
        -ClusterSizeInNodes $ClusterSizeInNodes
Write-Verbose "Transient cluster successfully created."

# Run jobs
Write-Verbose "Starting analysis..."
$PigQuery = "LOGS = LOAD '/input/$Website/*/*/*/*/*.applicationLog.csv' USING PigStorage(',') AS (logdate, level, applicationName, instanceId, eventTickCount, eventId, pid, tid, message);" +
            "FILTEREDLOGS = FILTER LOGS by logdate neq 'date';" +
            "PERF = foreach FILTEREDLOGS generate logdate, applicationName, REGEX_EXTRACT(message, 'Perf\\: (.+) took (\\d+) .+', 1) as method, (double)REGEX_EXTRACT(message, 'Perf\\: (.+) took (\\d+) .+', 2) as latency;" +
            "GROUPED = GROUP PERF by method;" +
            "STATS = foreach GROUPED generate group as method, AVG(PERF.latency) as avg_latency;" +
            "ORDEREDSTATS = ORDER STATS BY avg_latency DESC;" +
            "rmf /output " +
            "STORE PERF INTO '/output/appperf.csv';" +
            "STORE ORDEREDSTATS INTO '/output/appperf-avg.csv';"
New-AzureHDInsightPigJobDefinition -Query $PigQuery `
| Start-AzureHDInsightJob $Cluster `
| Wait-AzureHDInsightJob -WaitTimeoutInSeconds 3600 `
| Get-AzureHDInsightJobOutput -StandardError
Write-Verbose "Analysis successfully completed."

Write-Verbose "Retrieving averages of the web site performance markers..."
New-AzureHDInsightPigJobDefinition -Query "ORDEREDSTATS = LOAD '/output/appperf-avg.csv'; DUMP ORDEREDSTATS;" `
| Start-AzureHDInsightJob $Cluster `
| Wait-AzureHDInsightJob -WaitTimeoutInSeconds 3600 `
| Get-AzureHDInsightJobOutput -StandardOutput

# The data is processed now we can drop cluster
Write-Verbose "Dropping transient cluster..."
Remove-AzureHDInsightCluster $Cluster
Write-Verbose "Transient cluster successfully dropped."

Write-Verbose "Processing of '$Website' application logs successfully completed."
$output = "http://$DefaultStorageAccount.blob.core.windows.net/$DefaultStorageContainer/output"
Write-Verbose "Output files are located in '$output'."
