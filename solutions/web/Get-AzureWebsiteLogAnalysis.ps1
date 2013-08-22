<#
.SYNOPSIS
    Downloads IIS logs from an Azure Website and searches log for HTTP 400 and above status codes.
.DESCRIPTION
    Downloads IIS logs from the Azure Website.  If Htt logging is not enabled on the website, then it will
    enable logging if the EnableHttpLogging switch is specified.  

    The downloaded logs are unzipped and then fed into LogParser (if installed), querying for any HTTP
    status codes of 400 and higher.  The output of the LogParser query output to the console.
.EXAMPLE
    .\Get-AzureWebsiteLogAnalysis.ps1 -Name "MyWebsite" -OutputDir "c:\users\<MyUserName>\desktop\logs" -EnableHttpLogging
#>

param(
    # Website name from which logs are pulled
    [Parameter(Mandatory = $true)]
    [String]$Name,

    # Directory into which logs are dumped and unzipped
    [Parameter(Mandatory = $true)]
    [String]$OutputDir,

    # Switch to turn on http logging if not already on
    [Parameter(Mandatory = $false)]
    [Switch]$EnableHttpLogging
)

# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3

# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"

# Check if Windows Azure Powershell is avaiable
if ((Get-Module -ListAvailable Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please make sure to install them from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}

<#
.SYNOPSIS
   Gets the log files from the website
.DESCRIPTION
   This function builds a file name for the log file to download, drops it into the specified $Output directory,
   extracts the files from the .Zip, returns the name of the current IIS log file.
.INPUTS
   $Output - the directory to which logs should be downloaded   
.OUTPUTS
   The log files appear in that directory
#>
function Get-LogFiles
{
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $TargetDir)

    # Create a full path for the output log file.
    $fileName = "logfile $(get-date -Format yyyy-MM-dd-HHmm).zip"
    if ($TargetDir.EndsWith('\') -eq $true)
    {
        $fileName = $TargetDir + $fileName
    } else
    {
        $fileName = $TargetDir + '\' + $fileName
    }

    # Download the log file
    Write-Verbose "Downloading log file to '$fileName' ..."
    Save-AzureWebsiteLog -Name $Name -Output $fileName
    Write-Verbose "File successfully downloaded."

    # Unzip the contents
    Write-Verbose "Extracting file contents..."
    (new-object -com shell.application).namespace($TargetDir).CopyHere((new-object -com shell.application).namespace($fileName).Items(),16)
    Write-Verbose "File contents successfully extracted."
}

# Ensure the web site exists and that HttpLogging has been enabled.
$webSite = Get-AzureWebsite $Name -ErrorAction SilentlyContinue
if ($webSite -eq $null)
{
    throw "Website '$Name' does not exist."
}
elseif ($webSite.HttpLoggingEnabled -eq $false)
{
    if ($EnableHttpLogging.IsPresent) 
    {
        Set-AzureWebsite -Name $Name -HttpLoggingEnabled $true
        Write-Output "HttpLoggingEnabled now set on web site '$Name'.  " +
                     "Re-run the script later to retrieve logs."
        return
    }
    else
    {
        throw "Http Logging is not enabled on website $Name, use -EnableHttpLogging."
    }
}

# Ensure the output directory exists
if ((Test-Path $OutputDir) -eq $false)
{
    throw "The directory '$OutputDir' does not exist."
}

# Download all of the logs, unzip and place in the $Output location
Get-LogFiles($OutputDir)

# Define a path to the desired logs directory
$logFileActualPath = "$OutputDir\Logfiles\http\RawLogs"

Write-Verbose "logFileActualPath is $logFileActualPath"

# Fixes the metadata at the head of a log file
$filenames = Get-ChildItem -Path $logFileActualPath -Filter '*.log' -name
$filenames | ForEach-Object {
    $updateFilePath = "$logFileActualPath\$_"
    Write-Verbose "Updating header in file '$updateFilePath'."
    (Get-Content $updateFilePath) | 
        ForEach-Object {$_ -replace "\# date", "#Fields: date"} | Set-Content $updateFilePath
}

# Installation directory for LogParser.
$LogParserLocation = "C:\Program Files (x86)\Log Parser 2.2\LogParser.exe"

# Parse the log file looking for any entries with HTTP status code 400 and higher.
if ((Test-Path $LogParserLocation) -eq $true)
{
    $queryLine = "`"SELECT " 
    $queryLine += "  TO_TIMESTAMP(date,time) AS DateTime, " 
    $queryLine += "  CASE sc-status WHEN 500 " 
    $queryLine += "    THEN `'emerg`' " 
    $queryLine +=  "   ELSE `'err`' END AS MySeverity, " 
    $queryLine += "  s-computername AS MyHostname, " 
    $queryLine += "  cs-uri-stem " 
    $queryLine += "FROM $logFileActualPath`\*.log " 
    $queryLine += "WHERE sc-status >= 400`""

    & $LogParserLocation -i:IISW3C -e:5 $queryLine 
}
else
{
    Write-Verbose "Unable to process log files in directory '$logFileActualPath' because LogParser is not installed."
}