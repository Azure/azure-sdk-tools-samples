<#
.SYNOPSIS
   This script New-AzureSqlDwIaasVM.ps1 is used deploy SQL IaaS optimized for Data warehousing.
   Additionally it will attach the required number of disks dependingon the selected Instance size.

.NOTES
    File Name: New-AzureSqlDwIaasVM.ps1
    Author: Mostafa Mokhtar

.DESCRIPTION
   This script allows a user to create a Data warehousing optimized VM on Azure running SQL Server 2012 or SQL Server 2014, script will also attach empty disks to the VM to be used for Sql server data and log files.
   Attached disks are 1023GB each, size is not configurable, Azure subscriber will only get build for used capacity.
   Geo replication is not supported.

   New-AzureSqlDwIaasVM.ps1 implements the following:
       * Import Windows Azure module (Needed to use Windows Azure PowerShell cmdlets)
       * Import Azure publish settings (User account info etc.)
       * Create Azure Affinity group
       * Create Azure storage account
       * Set Azure subscription
       * Create New Azure VM with additional empty Azure disks

.EXAMPLE
   .\New-AzureSqlDwIaasVM.ps1  -PublishSettingsFile C:\AzpadXXXX-10-30-2013-credentials.publishsettings -InstanceSize A6  -SqlVersion SQL2012 -AzureAffinityGroup DwAffinityGroup1  -StorageAccountName StorageAccount1 -VMName A6-SQL2012-01 -ServiceName A6-SQL2012  -AdminAccount sa -AdminPassword MySecrectPassword  -Location "East Asia"
   Use locally saved publish settings file to deploy a VM of size A6 running SQL server 2012 DW optimized image, at affinity group named DwAffinityGroup1, using storage account StorageAccount1, VM name is A6-SQL2012-01, service name A6-SQL2012

.EXAMPLE
   .\New-AzureSqlDwIaasVM.ps1 -InstanceSize A7  -SqlVersion SQL2014 -AzureAffinityGroup DwAffinityGroup1  -StorageAccountName StorageAccount1 -VMName A7-SQL2014-01 -ServiceName A7-SQL2014  -AdminAccount sa -AdminPassword MySecrectPassword  -Location "East Asia"
   User will be prompted for the publish settings file, Azure creditenialts are needed to download the publish settings file if the file doesn't exist.
   Deploy a VM of size A7 running SQL server 2014 DW optimized image, at affinity group named DwAffinityGroup1, using storage account StorageAccount1, VM name is A7-SQL2014-01, service name A7-SQL2017

.PARAMETER PublishSettingsFile
   Specifies the full path and filename for the .publishsettings file for the Windows Azure account.
   This file contains settings and an encoded certificate that provides management credentials for the Windows Azure account.
   Security Note: The file downloaded contains an encoded management certificate that serves as the credentials to administer Windows Azure subscriptions and services. Store this file in a secure location or delete it after you use it.

.PARAMETER InstanceSize
   Specifies the size of the virtual machine. For a list of virtual machine sizes, see http://msdn.microsoft.com/library/dn197896.aspx.

.PARAMETER SqlVersion
   Select which SQL Server version will be used, depending on input the latest SQL Server for data warehousing on WS 2012 will be used.
   Either SQL2014 or SQL2012 can be used

.PARAMETER AzureAffinityGroup
   Affinity Group name. A name is assigned to the affinity group at the time of creation.
   Note that names for affinity groups created through the Management Portal are typically GUIDs and that the UI shows its label.

.PARAMETER Location
   The Location parameter specifies the geographical location of the data center where the affinity group will be created.

.PARAMETER StorageAccountName
   Account that provides access to Windows Azure storage services. A storage account is a globally unique resource within the storage system. The account is the parent namespace for the Blob, Queue, and Table services.

.PARAMETER VMName
   Specifies the name of the virtual machine.

.PARAMETER ServiceName
   Specifies the new or existing service name.

.PARAMETER SubscriptionName
   Retrieves the configuration settings for the subscription identified by this name. The Default, Current, and SubscriptionName parameters are mutually exclusive.
   If Azure user has multiple subscriptions this parameter will be required, if there is only one subscription the parameter is not required.

.PARAMETER AdminAccount
   Specifies the name for the user account to create for administrative access to the virtual machine.

.PARAMETER AdminPassword
   Specifies the password of the user account that has permission to add the computer to a domain.

.LINK
   http://go.microsoft.com/fwlink/?LinkId=320440

.LINK
   http://go.microsoft.com/fwlink/?LinkId=320441
#>

################################################################################
# Read User Parameters
################################################################################
param
    (
    [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $PublishSettingsFile,
    [Parameter(Position=1, Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateSet("ExtraSmall","Small","Medium","Large","ExtraLarge","A5","A6","A7")]
    [string] $InstanceSize,
    [Parameter(Position=2, Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateSet("SQL2014","SQL2012")]
    [String] $SqlVersion,
    [Parameter(Position=3, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $AzureAffinityGroup,
    [Parameter(Position=4, Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateSet("East Asia","Southeast Asia","North Europe","West Europe","Central US","East US 2")]
    [string] $Location,
    [Parameter(Position=5, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $StorageAccountName,
    [Parameter(Position=6, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $VMName,
    [Parameter(Position=7, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $ServiceName,
    [Parameter(Position=8, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $SubscriptionName,
    [Parameter(Position=9, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $AdminAccount,
    [Parameter(Position=10, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $AdminPassword
    )

######################################################################
# Name : Write-LogInfo
#
# Purpose:
#   Print detailed logging information to $DetailLogFile
#
# Returns:
#
# Notes:
#
# .SYNOPSIS
#    Print detailed info to the log file
#
# .NOTES
#
# .DESCRIPTION
#
# .EXAMPLE
#    Write-LogInfo -FunctionName Validate-AzurePublishSettingsFile -Message "Start importing azure publish settings"
#
# .PARAMETER $FunctionName
#     Name of function
#
# .PARAMETER $Message
#     Message to be printed out
#
Function Write-LogInfo(
    [Parameter(Position=0, Mandatory=$True, ValueFromPipeline=$false)]
    [string] $FunctionName,
    [Parameter(Position=1, Mandatory=$false, ValueFromPipeline=$false)]
    [string] $Message,
    [Parameter(Position=2, Mandatory=$false, ValueFromPipeline=$false)]
    $MultiLineMessage,
    [Parameter(Position=3, Mandatory=$False, ValueFromPipeline=$false)]
    [string] $ForegroundColor="Gray",
    [Parameter(Position=4, Mandatory=$False, ValueFromPipeline=$false)]
    [switch] $WriteToScreen=$true)
{

    if(($Message -ne $null) -and ($Message.length -gt 0 ))
    {
        if ($WriteToScreen)
        {
            Write-Host "$(Get-Date -Format "MM/dd/yyy HH:mm:ss") $FunctionName : $Message  " -ForegroundColor $ForegroundColor
        }
    }

    if(($MultiLineMessage -ne $null) -and  ($MultiLineMessage.count -gt 0))
    {
        foreach ($MessageLine in $MultiLineMessage)
        {
            Write-Host "$(Get-Date -Format "MM/dd/yyy HH:mm:ss")  : $FunctionName : $MessageLine  " -ForegroundColor $ForegroundColor
        }
    }
}

######################################################################
# Name : Get-VmConfiguration
#
# Purpose:
#   Parses the XML Config file used for configuring DW IAAS VMs
#
# Returns:
#   [hashtable] $XmlConfigObject
#
# Notes:
#
# .SYNOPSIS
#    Parse DwIaasConfig.xml
#
# .NOTES
#
# .DESCRIPTION
#
# .EXAMPLE
#    Get-VmConfiguration -InstanceSize A7 -XmlConfig $XmlConfig
#
# .PARAMETER XmlConfig
#     Path to XML file
#
Function Get-VmConfiguration (
    [Parameter(Position=0, Mandatory=$false, ValueFromPipeline=$false)]
    [string] $InstanceSize,
    [Parameter(Position=1, Mandatory=$false, ValueFromPipeline=$false)]
    [string] $XmlDwConfigFile)
{
    if (!(Test-Path $XmlDwConfigFile -ErrorAction SilentlyContinue))
    {
        Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  "$XmlConfig doesn't exist"
        throw "$XmlConfig doesn't exist"
        return $null
    }

    [xml] $XmlConfig = gc $XmlDwConfigFile -ErrorAction Stop
    [string] $DwConfigRootNodeString = "DwIaasConfig"
    [string] $DwConfigVmConfigNodeString = "VMConfig"
    [string] $DwConfigVmConfigGeneralNodeString = "VMConfigGeneral"
    [string] $XStoreStorageRootNodeString = "XStoreStorage"
    [hashtable] $XmlConfigObject = @{}

    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  "    Current system configuration"
    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  "    VM Size : $InstanceSize"

    [System.Xml.XmlElement] $DwIaasConfigGeneral = $XmlConfig.$DwConfigRootNodeString.$DwConfigVmConfigGeneralNodeString
    [System.Xml.XmlElement] $VmConfig = $XmlConfig.$DwConfigRootNodeString.$DwConfigVmConfigNodeString |Where-Object -Property NumberOfCores -eq $LogicalProcessorCount |Where-Object -Property ServerMemoryGB -EQ $TotalVisibleMemorySize
    [System.Xml.XmlElement] $VmConfig = $XmlConfig.$DwConfigRootNodeString.$DwConfigVmConfigNodeString |Where-Object -Property ID -eq $InstanceSize

    if($VmConfig -eq $null)
    {

        Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  "    Matching VM wasn't found in $XmlDwConfigFile" -foreground yellow

        # This is to support VMs greater than A7 so that configuring doesn't fail on HPC machines etc..
        # Logic below will only work if the "un-supported" VM is bigger than an A7 in terms of CPU and RAM
        [System.Xml.XmlElement] $A7VmConfig = $XmlConfig.$DwConfigRootNodeString.$DwConfigVmConfigNodeString |Where-Object -Property Id -eq "A7"

        # This means A7 configuration wasn't found in the XML
        if($A7VmConfig -eq $null)
        {
            throw "Azure VM size with TotalVisibleMemorySize = $TotalVisibleMemorySize and LogicalProcessorCount = $LogicalProcessorCount is not supported or doesn't exist in $XmlDwConfigFile; VM ID A7 wasn't found as well"
            return $null
        }

        # The VM must be bigger in terms of CPU and memory to use the A7 configuration
        # This logic is added to support A8 or A9 without code changes
        if(($LogicalProcessorCount -gt $A7VmConfig.NumberOfCores) -and ($TotalVisibleMemorySize -gt $A7VmConfig.ServerMemoryGB))
        {
            $VmConfig = $A7VmConfig
        }
        else
        {
            Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  "    Azure VM size with TotalVisibleMemorySize = $TotalVisibleMemorySize and LogicalProcessorCount = $LogicalProcessorCount is not supported or doesn't exist in $XmlDwConfigFile" -foreground red
            Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  "    No match found!"

            # Need to populate an array so that the error message prints nicely
            [array] $SupportedConfigurations = @()
            foreach ( $IaasVmConfiguration in $XmlConfig.$DwConfigRootNodeString.$DwConfigVmConfigNodeString)
            {
                [string] $ConfigDetail = "Id = `""+$IaasVmConfiguration.Id.ToString()+"`" " + "NumberOfCores = `""+$IaasVmConfiguration.NumberOfCores.ToString()+"`" " +"ServerMemoryGB = `""+$IaasVmConfiguration.ServerMemoryGB +"`" " + "NumberOfDataDisks = `""+$IaasVmConfiguration.NumberOfDataDisks +"`" " + "NumberOfLogDisks = `""+$IaasVmConfiguration.NumberOfLogDisks+"`""
                $SupportedConfigurations +=$ConfigDetail
            }

            Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -MultiLineMessage $SupportedConfigurations
            throw "Azure VM size with TotalVisibleMemorySize = $TotalVisibleMemorySize and LogicalProcessorCount = $LogicalProcessorCount is not supported or doesn't exist in $XmlDwConfigFile"
            return $null
        }
    }

    # Get the meta data for the VM :
    #   Id                : A7
    #   NumberOfCores     : 8
    #   ServerMemoryGB    : 56
    #   NumberOfDataDisks : 8
    #   NumberOfLogDisks : 1
    foreach( $VmAttribute in  $VmConfig.Attributes)
    {
         $XmlConfigObject.Add($VmAttribute.Name,$VmAttribute.Value)
    }

    # Get the Xstore storage configuration :
    #   DiskSizeGB
    #   HostCachePreferance
    foreach( $StorageAttribute in  $DwIaasConfigGeneral.$XStoreStorageRootNodeString.Attributes)
    {
         $XmlConfigObject.Add($StorageAttribute.Name,$StorageAttribute.Value)
    }

    $NumberOfDataDisks = $XmlConfigObject.NumberOfDataDisks
    $NumberOfLogDisks = $XmlConfigObject.NumberOfLogDisks

    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  "    NumberOfDataDisks   : $NumberOfDataDisks"
    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  "    NumberOfLogDisks    : $NumberOfLogDisks"

    return $XmlConfigObject
}

######################################################################
# Name : Validate-WindowsAzureModule
#
# Purpose:
#   Import Windows azure PowerShell module
#
# Returns:
#
# Notes:
#
# .SYNOPSIS
#    Import Windows Azure PowerShell module to create and configure Azure VMs
#
# .NOTES
#
# .DESCRIPTION
#
# .EXAMPLE
#    Validate-WindowsAzureModule -WindowsAzurePsModulePath $WindowsAzurePsModulePath
#
# .PARAMETER $WindowsAzurePsModulePath
#     Path of Azure.psd1
#
Function Validate-WindowsAzureModule (
    [Parameter(Position=0, Mandatory=$True, ValueFromPipeline=$false)]
    [string] $WindowsAzurePsModulePath)
{
    if (Test-Path $WindowsAzurePsModulePath -ErrorAction SilentlyContinue)
    {
        Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Importing Windows Azure PowerShell module from $WindowsAzurePsModulePath" -ForegroundColor "Gray"
        Import-Module  $WindowsAzurePsModulePath -ErrorAction Stop
    }
    else
    {
        throw "$WindowsAzurePsModulePath not found, please install from http://www.windowsazure.com/en-us/downloads"
    }
}

######################################################################
# Name : Validate-AzurePublishSettingsFile
#
# Purpose:
#   Wrapper for Import-AzurePublishSettingsFile
#
# Returns:
#
# Notes:
#
# .SYNOPSIS
#    Print function begin & End
#
# .NOTES
#
# .DESCRIPTION
#
# .EXAMPLE
#    Validate-AzurePublishSettingsFile -PublishSettingsFile "C:\Work\XXXXXXXXXXXXXXXXXXXXXXX-credentials.publishsettings
#
# .PARAMETER $FunctionName
#     Name of function
#
# .PARAMETER $Message
#     Message to be printed out
#
Function Validate-AzurePublishSettingsFile (
    [Parameter(Position=0, Mandatory=$false, ValueFromPipeline=$false)]
    [string] $PublishSettingsFile)
{
    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Start Validate Azure Publish Settings File"

    Import-AzurePublishSettingsFile -PublishSettingsFile $PublishSettingsFile -ErrorAction Stop

    if($?)
    {
        Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Success" -ForegroundColor "Green"
    }

    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " End Validate Azure Publish Settings File"
}

######################################################################
# Name : Validate-AzureAffinityGroup
#
# Purpose:
#   Wrapper for New-AzureAffinityGroup
#
# Returns:
#
# Notes:
#
# .SYNOPSIS
#    Create affinity group
#
# .NOTES
#
# .DESCRIPTION
#
# .EXAMPLE
#    Validate-AzureAffinityGroup -AzureAffinityGroup $AzureAffinityGroup -Location $Location
#
# .PARAMETER $AzureAffinityGroup
#     Name of affinity group
#
#
Function Validate-AzureAffinityGroup (
    [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $AzureAffinityGroup,
    [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $Location,
    [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $ServiceName)
{

    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Start Validate Azure Affinity Group"
    [bool] $UseCurrentAzureService = $false

    # Check if there exists and affinity group for the current service use it
    #
    if((Get-AzureService -ServiceName $ServiceName  -ErrorAction silentlycontinue).AffinityGroup)
    {
        $UseCurrentAzureService = $true
        $ServiceAffinityGroup = (Get-AzureService -ServiceName $ServiceName  -ErrorAction silentlycontinue).AffinityGroup
        if($ServiceAffinityGroup -eq $AzureAffinityGroup)
        {
            Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Will use affinity group $ServiceAffinityGroup which already exists as part of AzureService : $ServiceName" -ForegroundColor Green
            return $UseCurrentAzureService
        }
        else
        {
            throw "The Azure Service is running on Affinity group $AzureServiceAffinityGroup which is different that provided affinity group $AzureAffinityGroup.
            Please do one of the following:
                1) To create a new Azure service don't use an already existing ServiceName
                2) To use an existing Azure service and the affinity group used by the service"
            exit 1
        }
    }

    if(Get-AzureAffinityGroup -Name $AzureAffinityGroup -ErrorAction silentlycontinue )
    {
        # If the affinity group already exists and has a location other than the current one then throw
        if( (Get-AzureAffinityGroup -Name $AzureAffinityGroup).Location -ne $Location)
        {
            $AffinityGroupLocation = (Get-AzureAffinityGroup -Name $AzureAffinityGroup).Location
            throw "Affinity group $AzureAffinityGroup already exists and is in location $AffinityGroupLocation, which is different that requested location $Location!
             Please remove current affinity group or use the same location"
            exit 1
        }

        # If there is no location provided but an affinity group is provided get the location from the affinity group
        if (( $AzureAffinityGroup -ne $null) -and ($AzureAffinityGroup.length -gt 0))
        {
            if ((($Location -eq $null) -or ($Location.Length -eq 0)) -and (Get-AzureAffinityGroup -Name $AzureAffinityGroup -ErrorAction silentlycontinue ))
            {
                $Location = (Get-AzureAffinityGroup -Name $AzureAffinityGroup).Location
            }
        }

        Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Affinity group $AzureAffinityGroup already exists and will be used" -ForegroundColor "Green"
        $UseCurrentAzureService = $false
    }
    else
    {
        Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Affinity group $AzureAffinityGroup at $Location doesn't exists, will create new one" -ForegroundColor "Green"
        New-AzureAffinityGroup -Name $AzureAffinityGroup -Location $Location -Description "$AzureAffinityGroup`-$Location" > $null

        if($?)
        {
            Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Success" -ForegroundColor "Green"
        }
        else
        {
            Write-Error "Azure Affinity group $AzureAffinityGroup creation failed $error[0]"
            Write-Error $error[0]
        }
    }

    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Start Validate Azure Affinity Group"

    return $UseCurrentAzureService
}

######################################################################
# Name : Validate-AzureStorageAccount
#
# Purpose:
#   Wrapper for New-AzureStorageAccount & Get-AzureStorageAccount
#
# Returns:
#
# Notes:
#
# .SYNOPSIS
#    Create storage account
#
# .NOTES
#
# .DESCRIPTION
#
# .EXAMPLE
#    Validate-AzureStorageAccount -StorageAccountName $StorageAccountName -Location $Location
#
# .PARAMETER $AzureAffinityGroup
#     Name of affinity group
#
#
Function Validate-AzureStorageAccount (
    [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $StorageAccountName,
    [Parameter(Position=1, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $Location,
    [Parameter(Position=2, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $AzureAffinityGroup)
{
    # Storage accounts only support lower case strings
    #
    $StorageAccountName = $StorageAccountName.Tolower()

    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Start Validate Azure Storage Account"

    if(Get-AzureStorageAccount -StorageAccountName $StorageAccountName -ErrorAction silentlycontinue )
    {
        $CurrentStorageAccountLocation = (Get-AzureStorageAccount -StorageAccountName $StorageAccountName).Location
        $GeoReplicationEnabled = (Get-AzureStorageAccount -StorageAccountName $StorageAccountName).GeoReplicationEnabled

        # If the storage account already exists and has a location other than the provided one then throw
        if (($CurrentStorageAccountLocation -ne $null) -and ($CurrentStorageAccountLocation -ne $Location))
        {
            $StorageAccountLocation = (Get-AzureStorageAccount -StorageAccountName $StorageAccountName).Location
            throw "Storage account $StorageAccountName already exists and is in location $StorageAccountLocation, which is different from requested location $Location!
             Please remove current storage account or use a different one"
            exit 1
        }

        if ($GeoReplicationEnabled)
        {
            # SQL DW IAAS doesn't support Geo replication as the data is stripped across multiple Azure data disks
             throw "Storage account $StorageAccountName has geo replication enabled, please disable Geo replication or use a different storage account
             To disable Geo replication execute : Set-AzureStorageAccount -StorageAccountName $StorageAccountName -GeoReplicationEnabled `$false"
            exit 1
        }

        Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Storage account $StorageAccountName already exists and will be used" -ForegroundColor "Green"
    }
    else
    {
        Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Storage account $StorageAccountName doesn't exists, will create new one" -ForegroundColor "Green"
        if(Get-AzureAffinityGroup -Name $AzureAffinityGroup -ErrorAction silentlycontinue)
        {
            New-AzureStorageAccount -StorageAccountName  $StorageAccountName -AffinityGroup $AzureAffinityGroup -Description "$StorageAccountName`-$AzureAffinityGroup"
        }
        else
        {
            New-AzureStorageAccount -StorageAccountName  $StorageAccountName -Location $Location -Description "$StorageAccountName`-$Location"
        }

        if($?)
        {
            Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Disabling Geo replication for storage account  : $StorageAccountName" -ForegroundColor "Green"
            Set-AzureStorageAccount -StorageAccountName $StorageAccountName -GeoReplicationEnabled $false
            Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Success " -ForegroundColor "Green"
        }
        else
        {
            Write-Error "Storage account $StorageAccountName creation failed $error[0]"
            Write-Error $error[0]
        }
    }

    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " End Validate Azure Storage Account"
}

######################################################################
# Name : Validate-AzureSubscription
#
# Purpose:
#   Wrapper for Get-AzureSubscription, Set-AzureSubscription & Select-AzureSubscription
#
# Returns:
#   updated $SubscriptionName if the provided one was not valid
#
# Notes:
#
# .SYNOPSIS
#    Validates the azure subscription provided
#
# .NOTES
#
# .DESCRIPTION
#
# .EXAMPLE
#    Validate-AzureSubscription -SubscriptionName $SubscriptionName
#
# .PARAMETER $SubscriptionName
#     Name of Azure subscription
#
Function Validate-AzureSubscription (
    [Parameter(Position=0, Mandatory=$false, ValueFromPipeline=$false)]
    [string] $SubscriptionName)
{
    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Start Validate Azure Subscription"

    # Verify the azure subscription name
    #
    if (($SubscriptionName -eq $null) -or ($SubscriptionName.length -eq 0) -or ((Get-AzureSubscription -SubscriptionName $SubscriptionName -ErrorAction SilentlyContinue) -eq $null))
    {
        throw "Subscription Name `"$SubscriptionName`" is invalid"
    }

    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Subscription name: $SubscriptionName"

    Select-AzureSubscription -SubscriptionName $SubscriptionName

    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " End Validate Azure Subscription"

    return $SubscriptionName
}

######################################################################
# Name : Validate-ImageAndInstanceSizeLocations
#
# Purpose:
#   Checks if the requested VM instance size & image are available in selected  location
#
# Returns:
#   Throws exception if the location is not valid
#
# Notes:
#
# .SYNOPSIS
#    Validates the azure subscription provided
#
# .NOTES
#
# .DESCRIPTION
#
# .EXAMPLE
#    Validate-AzureSubscription -SubscriptionName $SubscriptionName
#
# .PARAMETER $SubscriptionName
#     Name of Azure subscription
#
Function Validate-ImageAndInstanceSizeLocations (
    [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $ImageName,
    [Parameter(Position=1, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $Location,
    [Parameter(Position=2, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $InstanceSize)
{

    # Check if the location is valid
    if ( (Get-AzureVMImage -ImageName $ImageName).Location.Contains($Location) -eq $false)
    {
        $SupportedLocations = (Get-AzureVMImage -ImageName $ImageName).Location
        throw "Image $ImageName is not supported in $Location, please use one from : $SupportedLocations"
        exit 1
    }

    # If this is a high-memory VM make sure the selected location supports it
    if($HighMemoryVMs.Contains($InstanceSize))
    {
         if ((Get-AzureLocation|Where-Object -Property  Name -eq $Location).AvailableServices.Contains("HighMemory") -eq $false)
         {
            $SupportedServicesAtLocation = (Get-AzureLocation|Where-Object -Property  Name -eq $Location).AvailableServices
            throw "VM InstanceSize $InstanceSize is not supported in $Location, current available services at location : $SupportedServicesAtLocation"
            exit 1
         }
    }
}

######################################################################
# Name : New-AzureVmWrapper
#
# Purpose:
#   Wrapper for New-AzureVm
#
# Returns:
#
# Notes:
#
# .SYNOPSIS
#    Create Azure VM for IAAS
#
# .NOTES
#
# .DESCRIPTION
#
# .EXAMPLE
#    New-AzureVmWrapper -VMName $VMName -A7 -ImageName $ImageName  -Location $Location -AzureAffinityGroup $AzureAffinityGroup -ServiceName $ServiceName -AdminAccount $AdminAccount -AdminPassword $AdminPassword -SubscriptionName $SubscriptionName
#
# .PARAMETER $AzureAffinityGroup
#     TBD
#
#
Function New-AzureVmWrapper (
     [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $VMName,
    [Parameter(Position=1, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $InstanceSize,
    [Parameter(Position=2, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $ImageName,
    [Parameter(Position=3, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $Location,
    [Parameter(Position=4, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $AzureAffinityGroup,
    [Parameter(Position=5, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $ServiceName,
    [Parameter(Position=6, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $AdminAccount,
    [Parameter(Position=7, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $AdminPassword,
    [Parameter(Position=8, Mandatory=$true, ValueFromPipeline=$false)]
    [string] $SubscriptionName,
    [Parameter(Position=9, Mandatory=$true, ValueFromPipeline=$false)]
    [hashtable] $XmlConfigObject,
    [Parameter(Position=10, Mandatory=$true, ValueFromPipeline=$false)]
    [bool] $UseCurrentAzureService)

{
    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Start New Azure Vm Wrapper"

    if(Get-AzureVM -Name $VMname -ServiceName $ServiceName -ErrorAction SilentlyContinue)
    {
       Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " VM $VMname on Service $ServiceName already exists and will be used" -ForegroundColor "Green"
       return
    }

    Write-Debug $SubscriptionName

    Set-AzureSubscription -SubscriptionName $SubscriptionName -CurrentStorageAccount $StorageAccountName
    Select-AzureSubscription -SubscriptionName $SubscriptionName

    $DwIAASVM = New-AzureVMConfig -Name $VMname -ImageName $imageName -InstanceSize $InstanceSize -ErrorAction Stop |
    Add-AzureProvisioningConfig -Windows -AdminUsername $AdminAccount -Password $AdminPassword -ErrorAction Stop

    [int] $NumberOfDisksToAttach = [int] $XmlConfigObject.NumberOfDataDisks + [int] $XmlConfigObject.NumberOfLogDisks


    for ([int] $DiskNum = 1 ; $DiskNum -le [int] $XmlConfigObject.NumberOfDataDisks  ; $DiskNum ++)
    {
        $LunNumber = $DiskNum + 1
        $DiskLabel = ([string] $XmlConfigObject.DataDiskMountPrefix).Trim() + $DiskNum
        $DwIAASVM | Add-AzureDataDisk  -CreateNew -DiskSizeInGB $XmlConfigObject.DiskSizeGB -DiskLabel $DiskLabel -LUN $LunNumber -HostCaching $XmlConfigObject.HostCachePreferance > $null
    }

    for ([int] $LogDiskNum = 1 ; $LogDiskNum -le [int] $XmlConfigObject.NumberOfLogDisks  ; $LogDiskNum ++)
    {
        # Using $DiskNum and not $LogDiskNum is intentional and not a type
        $LunNumber = $DiskNum + 1
        $DiskLabel = ([string] $XmlConfigObject.LogDiskMountPrefix).Trim() + $LunNumber
        $DwIAASVM| Add-AzureDataDisk  -CreateNew -DiskSizeInGB $XmlConfigObject.DiskSizeGB -DiskLabel $DiskLabel -LUN $LunNumber -HostCaching $XmlConfigObject.HostCachePreferance  > $null
        $DiskNum++
    }

    # If this is an already existing service no need to specify the affinity group
    # specifying the affinity group implies that a new azure service will be created
    if ($UseCurrentAzureService -eq $true)
    {
        New-AzureVM -ServiceName $ServiceName -VMs $DwIAASVM  -WaitForBoot
    }
    else
    {
        New-AzureVM -ServiceName $ServiceName –VMs $DwIAASVM -AffinityGroup $AzureAffinityGroup -WaitForBoot
    }

    Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " End create Azure VM"
}

################################################################################################
#
#.SYNOPSIS
#  Returns the latest image for a given image family name filter.
#.DESCRIPTION
#  Will return the latest image based on a filter match on the ImageFamilyName and
#  PublisedDate of the image.  The more specific the filter, the more control you have
#  over the object returned.
#.EXAMPLE
#  The following example will return the latest SQL Server image.  It could be SQL Server
#  2014, 2012 or 2008
#
#    Get-LatestImage -LabelNameFilter "2012"
#
#  The following example will return the latest SQL Server 2014 image. This function will
#  also only select the image from images published by Microsoft.
#
#    Get-LatestImage -LabelNameFilter "2014"
#
#  The following example will return $null because Microsoft doesn't publish Ubuntu images.
#
#    Get-LatestImage -LabelNameFilter "*Ubuntu*"
################################################################################################
function Get-LatestImage
    (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$false)]
        [ValidateSet("2014","2012")]
        [String] $LabelNameFilter)
{

    [string] $DwIaasIMageLabelPrefix = "SQL Server"
    [string] $DwIaasIMageLabelSuffix = "for data warehousing on WS 2012"

    # Get a list of all available images.
    $imageList = Get-AzureVMImage

    $imageList = $imageList |Where-Object { ($_.PublisherName -ilike "Microsoft*" -and $_.Label -ilike "$DwIaasIMageLabelPrefix*$LabelNameFilter*$DwIaasIMageLabelSuffix" ) }

    $imageList = $imageList | Sort-Object -Unique -Descending -Property ImageFamily |Sort-Object -Descending -Property PublishedDate

    [string] $ImageName = ($imageList | Select-Object -First(1)).ImageName

    if(($ImageName -eq $null) -or ($ImageName.length -eq 0))
    {
        throw "No matching images found, search pattern used $DwIaasIMageLabelPrefix*$LabelNameFilter*$DwIaasIMageLabelSuffix*"
        exit 1
    }

    return $ImageName
}

######################################################################
# Main Script
######################################################################

[string] $WindowsAzurePsModulePath = Join-Path "${Env:ProgramFiles(x86)}" "Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1"
[string] $XmlDwConfigFile = Join-Path  (split-path $MyInvocation.MyCommand.Path) "New-AzureSqlDwIaasVM_DwIaasConfigGeneral.xml"
[string] $StorageAccountName = $StorageAccountName.ToLower()

######################################################################################
# The high memory VMs, this might change in the future.
# Used to programatically validate that the selected location supports high memory VMs
######################################################################################
[string] $HighMemoryVMs=("A7","A6")

###########################################################################
# Create the Transcript file which records this  Windows PowerShell session
# Incase anything is missed or we encouter un-expected failures
###########################################################################
[string] $TranscriptFileName = "New-AzureSqlDwIaasVM-" + (Get-Date -Format "MMddyyyHHmmss")+".txt"
[string] $TranscriptLogFile = Join-Path  (split-path $MyInvocation.MyCommand.Path) $TranscriptFileName

try {Stop-Transcript >  $null}
catch {Write-Debug "There was no Transcript running" }
Start-Transcript $TranscriptLogFile -Append


try
{
    ############################################
    # Import the Windows Azure PowerShell Module
    ############################################
    Validate-WindowsAzureModule    -WindowsAzurePsModulePath   $WindowsAzurePsModulePath

    ################################################
    # Import the Windows Azure Publish settings file
    ################################################
    Validate-AzurePublishSettingsFile  -PublishSettingsFile    $PublishSettingsFile

    #############################
    # Always get the latest image
    #############################
    switch ($SqlVersion)
    {
        "SQL2014"
        {
            $ImageName = Get-LatestImage -LabelNameFilter 2014
        }

        "SQL2012"
        {
            $ImageName = Get-LatestImage -LabelNameFilter 2012
        }
        default
        {
            # We will never end up here since $SqlVersion enforces the version to be either 2012 or 2014
        }
    }

    #######################################################################################
    #  Checks if the requested VM instance size & image are available in selected  location
    #######################################################################################
    Validate-ImageAndInstanceSizeLocations -ImageName $ImageName -Location $Location -InstanceSize $InstanceSize

    #######################################
    # Verify and set the azure subscription
    #######################################
    $SubscriptionName = Validate-AzureSubscription -SubscriptionName $SubscriptionName

    #######################
    # Create affinity group
    #######################
    $UseCurrentAzureService = Validate-AzureAffinityGroup -AzureAffinityGroup $AzureAffinityGroup -Location $Location  -ServiceName $ServiceName

    ########################
    # Create storage account
    ########################
    Validate-AzureStorageAccount -StorageAccountName $StorageAccountName -Location $Location -AzureAffinityGroup $AzureAffinityGroup

    #########################################################################
    # Based on instance size get the number of disks to be attached to the VM
    #########################################################################
    [hashtable] $XmlConfigObject = Get-VmConfiguration -InstanceSize $InstanceSize -XmlDwConfigFile $XmlDwConfigFile

    ###########
    # Create VM
    ###########
    New-AzureVmWrapper -VMName $VMName  -InstanceSize $InstanceSize -ImageName $ImageName -Location $Location -AzureAffinityGroup $AzureAffinityGroup -ServiceName $ServiceName -AdminAccount $AdminAccount -AdminPassword $AdminPassword -SubscriptionName $SubscriptionName -XmlConfigObject:$XmlConfigObject -UseCurrentAzureService:$UseCurrentAzureService
}
catch
{
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Failed item    : $FailedItem"  -ForegroundColor "Red"
        Write-LogInfo -FunctionName $MyInvocation.MyCommand.Name -Message  " Error Message  : $ErrorMessage"  -ForegroundColor "Red"
        if ( $Error[0].Exception.InnerException -ne $null)
        {
            $sr = new-object System.IO.StreamReader($Error[0].Exception.InnerException.Response.GetResponseStream())
            $txt = $sr.ReadToEnd()
            $txt
            $sr.Close()
        }

        # rethrow the exception
        throw $_.Exception;
}
Finally
{
    ####################################
    # Stop the Transcript for the script
    ####################################
    try     {   Stop-Transcript > $null}
    catch   {   Write-Debug "There was no Transcript running" }
}
