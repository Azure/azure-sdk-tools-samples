
<#
.SYNOPSIS
    Manage Premium SQL Databases
.DESCRIPTION
    Script will walk you through checking premium quota assigned to your subscription. If you have premium quota allocated you can then set a database as permium.

#>


# Setting up the subscription info and the certificate
# to be used when connecting to the subscription
# 
# This needs to be done once per subscription on each 
# new client machine
# Enter values for thumbprint and subscription ID
$thumbprint = "Enter thumbprint Here"
$myCert = Get-Item cert:\\CurrentUser\My\$thumbprint
$subID = "Enter SUBid Here"
Set-AzureSubscription -SubscriptionName "Example" -SubscriptionId $subID -Certificate $myCert


# Select the active subscription to be used 
# for the rest of the script
#
Select-AzureSubscription -SubscriptionName "Example"
Get-AzureSubscription

# See all servers in the subscription
Get-AzureSqlDatabaseServer


# Select the active subscription to be used 
# for the rest of the script
#
Select-AzureSubscription -SubscriptionName "Example"
Get-AzureSubscription

# See all servers in the subscription
Get-AzureSqlDatabaseServer

# Assign server
$server = Get-AzureSqlDatabaseServer "DemoServer"




######Check if premium quota has been assigned to your server########################### 

# This command will list if you have assigned premium quota. Premium has to be requested via the portal

$Server | Get-AzureSqlDatabaseServerQuota 

Get-AzureSqlDatabaseServerQuota $ctx

$ctx | Get-AzureSqlDatabaseServerQuota

########Set a database to premium########################### 


$servercredential = new-object System.Management.Automation.PSCredential("mylogin", ("Sql@zure"  | ConvertTo-SecureString -asPlainText -Force))
$ctx = $server | New-AzureSqlDatabaseServerContext -Credential $serverCredential

# Get an enabled service objective
$objective = Get-AzureSqlDatabaseServiceObjective -Context $ctx -ServiceObjectiveName "Reserved P1"
$objective


# Set the objective to a database
Set-AzureSqlDatabase -ConnectionContext $ctx -DatabaseName "testdb" -ServiceObjective $objective


$ctx | Get-AzureSqlDatabase -DatabaseName "testdb"


