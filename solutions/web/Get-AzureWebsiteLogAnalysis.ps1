<#
.SYNOPSIS
    Downloads logs from an Azure Website, pipes requested log into log analysis tooling via extensions.
.DESCRIPTION
    Several logs in an Azure Website can be switched on for download at a later time.  They can be switched on
    either through the portal or PowerShell cmdlets.  Downloading the logs brings a zip file with several directories
    embedded.  Via this script, these directories are extracted to a local directory.  One of the logs can be 
    specified on the command line.  This log will be piped through to a log analysis tool of the user's choosing.
    Examples in this script use Log Parser: http://www.iis.net/downloads/community/2010/04/log-parser-22.  

    Note: This script assumes that Get-AzureSubscription returns a valid subscription and that the workstation has
    the required management certificate relationship with that subscription.  It also assumes that the output
    directory exists.

    Note: This script depends on the June 2013 drop of the Windows Azure PowerShell cmdlets:
        Save-AzureWebsiteLog

.EXAMPLE
    Get-AzureWebsiteLogAnalysis.ps1 -Name 'MyWebsite' -Output 'c:\users\desktop\myname\logs' -Path http -SetSwitches
#>

# parameters
param(
    # Website name from which logs are pulled
    [Parameter(Mandatory = $true)]
    [String]$Name,

    # Directory into which logs are dumped and unzipped
    [Parameter(Mandatory = $true)]
    [String]$Output,

    # Type of log to look at - http is default
    [Parameter(Mandatory = $false)]
    [String]$Path,

    # Switch whether to turn on logging if not already on
    [Parameter(Mandatory = $false)]
    [Switch]$SetSwitches
)

Write-Verbose "Entering"

# constants
$LogParserLocation = "C:\Program Files (x86)\Log Parser 2.2\LogParser.exe"

Write-Verbose "Checking log path"

# ensure the path variable is set
if ($Path -eq $null -or $Path -eq '')
{
    $Path = 'http' 
}
$Path = $Path.ToLower()

<#
.SYNOPSIS
   Evaluates input parameters
.DESCRIPTION
   Checks that the things specified in the input parameter list make sense, exist, etc.
.INPUTS
   The input parameters of this script   
.OUTPUTS
   none
#>
function Test-Parameters()
{
    # ensure the web site exists
    $webSite = Get-AzureWebsite $Name -ErrorAction SilentlyContinue
    if ($webSite -eq $null)
    {
        throw "Website does not exist."
    }

    # ensure the output directory exists
    $outputDirectoryExists = Test-Path $Output
    if ($outputDirectoryExists -eq $false)
    {
        throw "The output directory does not exist."
    }

    return $true
}

function Test-RequestedService()
<#
.SYNOPSIS
   Evaluates the intent of the user
.DESCRIPTION
   If HTTP log analysis is requested, but HTTP logging isn't switched on, can't proceed, for example.
.INPUTS
   Output of Get-AzureWebsite
   $Name input parameter
   $Path input parameter   
.OUTPUTS
   Http logging status of the named website
#>
{
    $webSite = Get-AzureWebsite -Name $Name
    if ($Path -eq 'http')
    {
        return $webSite.HttpLoggingEnabled
    }
    <# Uncomment this block if you want to add DetailedErrors analysis to this script.  
    else if ($Path -eq 'DetailedErrors')
    ...
    #>
    return $false
}

function Get-LogFiles()
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
{
    Write-Verbose "Get-LogFile"

    # build file name for the output log file
    $fileName = "logfile $(get-date -Format yyyy-MM-dd-HHmm).zip"
    if ($Output.EndsWith('\') -eq $true)
    {
        $fileName = $Output + $fileName
    } else
    {
        $fileName = $Output + '\' + $fileName
    }

    Write-Verbose "Filename for downloaded zip is $fileName"

    # get the log file
    Save-AzureWebsiteLog -Name $Name -Output $fileName

    Write-Verbose "File has been downloaded and saved."

    # unzip the contents
    (new-object -com shell.application).namespace($Output).CopyHere((new-object -com shell.application).namespace($fileName).Items(),16)

    Write-Verbose "File contents have been unzipped."

}

function Format-HttpHeader($LogFileFullPath)
<#
.SYNOPSIS
   Fixes the metadata at the head of a log file
.DESCRIPTION
   For LogParser to work correctly, it requires the #Fields metadata at the head of the file.  This function
   fixes the existing metadata to the correct format.
.INPUTS
   Fully qualified path name of the log file to fix  
.OUTPUTS
   The file is both input and output.
#>{
    (Get-Content $LogFileFullPath) | ForEach-Object {$_ -replace "\# date", "#Fields: date"} | Set-Content $LogFileFullPath
}

# Execution starts here
$returnValue = Test-Parameters
if ($returnValue -ne $true)
{
    Write-Verbose "Parameter check failed."
    return
}

if ($VerbosePreference -eq "Continue")
{
    Write-Verbose "Website name is $Name"
    Write-Verbose "Output directory name is $Output"
    Write-Verbose "Log path taken is $Path"
    Write-Verbose "SetSwitches is $SetSwitches"
}

$returnValue = Test-RequestedService
if ($returnValue -eq $false)
{
    if ($SetSwitches -eq $true)
    {
        Set-AzureWebsite -Name $Name -HttpLoggingEnabled $true
        Write-Output "HttpLoggingEnabled on web site $Name"
        return  <# exit the script here - since you just enabled logging, there aren't any logs yet #>
    }
    else
    {
        throw "Http Logging is not enabled on website $Name, use -SetSwitches."
    }
}

# download all of the logs, unzip and place in the $Output location
Get-LogFiles

# define a pointer to the desired logs directory
if ($Path -eq 'http')
{
    $logFileActualPath = "$Output\Logfiles\http\RawLogs"
}
<#
else if ($Path -eq 'DetailedErrors')
...
#>

Write-Verbose "logFileActualPath is $logFileActualPath"

# fix file format error in http
if ($Path -eq 'http')
{
    $filenames = Get-ChildItem -Path $logFileActualPath -Filter '*.log' -name

    Write-Verbose "File names are $filenames"

    $filenames | ForEach-Object {Format-HttpHeader("$logFileActualPath\$_")}
}

# start up the Log Parser
if ((Test-Path $LogParserLocation) -eq $true)
{
    if ($Path -eq 'http')
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

        $commandLine = "LogParser  -i:IISW3C -e:5 $queryLine "
        Write-Verbose $("Running command: " + $commandLine);

        $rnd = $(([string](Get-Random -Minimum 10000 -Maximum 99999999)) + ".cmd");
        $commandFilePath = $(Join-Path -Path $env:TEMP -ChildPath $rnd);
        echo $commandLine | Out-File -FilePath $commandFilePath -Encoding ascii;

        & cmd.exe /c $commandFilePath
    }
    <#
    else if ($Path -eq 'DetailedErrors')
    ...
    #>
}
