<#
.SYNOPSIS
  Creates 2 storage accounts for a cloud service
.DESCRIPTION
  Creates 2 storage accounts, 1 for data, 1 for diagnostics, with a name that matches a given cloud service. Storage 
  accounts are placed in the specified location or affinity group.

  If the affinity group does not exist, the script will create it, optionally prompting the user for the location
  in which to place the group. If an account the script is trying to create already exists, an informational 
  message will be displayed and progress will continue. 
.EXAMPLE
  New-Cloud-Service-Storage-Accounts.ps1 -CloudServiceName "MyCloudServiceName" -AffinityGroup "MyAffinityGroup"

#>
function New-Cloud-Service-Storage-Accounts
{
    Param(

      # Cloud service name for which we're creating storage accounts
      [Parameter(Mandatory=$true)]
      [String]$CloudServiceName,

      # affinity group storage account will be associated with
      [Parameter(ParameterSetName='ParameterSetAffinityGroup')]
      [String]$AffinityGroup,

      # location/sub-region storage account will be associated with
      [Parameter(ParameterSetName='ParameterSetLocation')]
      [String]$Location,

      #storage account description (optional)
      [String]$Description = "modified via powershell",

      # storage account label (optional)
      [string]$Label                                             
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
        Adds a new affinity group if it does not exist.
    .DESCRIPTION
       Looks up the current subscription's (as set by Set-AzureSubscription cmdlet) affinity groups and 
       creates a new affinity group if it does not exist.
    .EXAMPLE
       New-AzureAffinityGroupIfNotExists -AffinityGroupNme newAffinityGroup -Locstion "West US"
    #>
    function New-AzureAffinityGroupIfNotExists
    {
        param
        (
            # Name of the affinity group
            [Parameter(Mandatory = $true)]
            [String]
            $AffinityGroupName,
        
            # Location where the affinity group will be pointing to
            [Parameter(Mandatory = $true)]
            [String]
            $Location)    

        $affinityGroup = Get-AzureAffinityGroup -Name $AffinityGroupName -ErrorAction SilentlyContinue
        if ($affinityGroup -eq $null)
        {
            New-AzureAffinityGroup -Name $AffinityGroupName -Location $Location -Label $AffinityGroupName `
                -ErrorVariable lastError -ErrorAction SilentlyContinue | Out-Null
            if (!($?))
            {
                throw "Cannot create the affinity group $AffinityGroupName on $Location"
            }
            Write-Verbose "Created affinity group $AffinityGroupName"
        }
        else
        {
            if ($affinityGroup.Location -ne $Location)
            {
                Write-Warning "Affinity group with name $AffinityGroupName already exists but in location 
                    $affinityGroup.Location, not in $Location"
            }
        }
    }

    <#
    .SYNOPSIS
        Creates a storage account
    .DESCRIPTION
       Creates a storage account in the specified affinity group or location if it 
       doesn't already exist.
    .EXAMPLE
       Create-Storage-Account -StorageAccountName "MyStorageAccountName" -LocationType "Location" -Location "West US"
    #>
    function Create-Storage-Account
    {
        param(
            # name of storage account to be created
            [Parameter(Mandatory = $true)]
            [String]$StorageAccountName,

            # either "Location" or "Affinity Group"
            [Parameter(Mandatory = $true)]
            [String]$LocationType,

            # The location or affinity group where the storage account is to be created        
            [Parameter(Mandatory = $true)]
            [String]$Location,

            # optional storage account description name        
            [String]$Description,

            # optional label to be used on the storage account        
            [String]$Label
        )

        # Get the directory of the current script
        $scriptPath = Split-Path -parent $PSCommandPath

        # Create a new cloud service
        Write-Verbose ("[Start] creating data storage account '{0}' in {1} '{2}'" `
          -f $StorageAccountName, $LocationType, $Location)

        $storageAccount = Get-AzureStorageAccount -StorageAccountName $StorageAccountName `
          -ErrorAction SilentlyContinue
        # public string ServiceName { get; set; }
        # public StorageServiceKeys StorageServiceKeys { get; set; }
        if ($storageAccount -eq $null)
        {
            # Create a new storage account
            If ($LocationType -eq "Location")    # if affinity group was provided
            {
                New-AzureStorageAccount -StorageAccountName $StorageAccountName `
                  -Location $Location -Description $Description `
                    -ErrorVariable lastError -ErrorAction SilentlyContinue | Out-Null
                if (!($?))
                {
                    throw "Cannot create the storage account '{0}' in affinity group '{1}'" -f $StorageAccountName, $Location
                }
            }
            else
            {
                New-AzureStorageAccount -StorageAccountName $StorageAccountName `
                  -AffinityGroup $Location -Description $Description `
                  -ErrorVariable lastError -ErrorAction SilentlyContinue | Out-Null
                if (!($?))
                {
                    throw "Cannot create the storage account '{0}' at location '{1}'" -f $StorageAccountName, $Location
                }
            }
        }
        else
        {
            Write-Verbose ("[Warning] storage account '{0}' already exists" -f $StorageAccountName)
        }

        Write-Verbose ("[Finish] creating data storage account '{0}' in {1} '{2}'" `
          -f $StorageAccountName, $LocationType, $Location)

        $storageAccountKeys = Get-AzureStorageKey -StorageAccountName $StorageAccountName
        Return @{
            storageAccountKeys = $storageAccountKeys; `
        }
    }

    $VerbosePreference = "Continue"
    $ErrorActionPreference = "Stop"

    # Mark the start time of the script execution
    $startTime = Get-Date

    Write-Verbose ("[Start] creating storage accounts for cloud service {0}" -f $CloudServiceName)

    # Define the names of storage accounts
    $CloudServiceName = $CloudServiceName.ToLower()
    $StorageAccountName = "{0}storage" -f $CloudServiceName

    # Define verbiage text
    $LocationType = "Location"
    If ($AffinityGroup)    # if affinity group was provided, set location type text and location variable
    {
        $LocationType = "Affinity Group"
        $Location = $AffinityGroup
        New-AzureAffinityGroupIfNotExists -AffinityGroupName $AffinityGroup
    }

    # Create stoage account for data
    $StorageAccountName = "{0}data" -f $CloudServiceName
    $dataStorageKeys = Create-Storage-Account -StorageAccountName $StorageAccountName `
      -LocationType $LocationType -Location $Location -Description $Description -Label $Label

    # Create stoage account for diagnostics
    $StorageAccountName = "{0}diag" -f $CloudServiceName
    $diagStorageKeys = Create-Storage-Account -StorageAccountName $StorageAccountName `
      -LocationType $LocationType -Location $Location -Description $Description

    Write-Verbose ("[Finish] creating Windows Azure cloud service storage accounts")

    # retrieve storage account information return as variables so we can use it. 

    # Mark the finish time of the script execution
    $finishTime = Get-Date
    # Output the time consumed in seconds
    Write-Output ("Total time used (seconds): {0}" -f ($finishTime - $startTime).TotalSeconds)

    Return @{
        # need to return storage names and keys as hash table
        dataStorageKeys = $dataStorageKeys; `
        diagStorageKeys = $diagStorageKeys; `
    }

}