
<#
.SYNOPSIS
    Creates a SQL server and database with firewall rule
.DESCRIPTION
    Creates a SQL Server with firewall rule in a sub region. Then create a database on the newly created server.

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

#Example
#$thumbprint = "0000000000000000000000000000000000000000"
#$myCert = Get-Item Cert:\CurrentUser\My\$thumbprint
#$subId = "00000000-0000-0000-0000-000000000000"

# Select the active subscription to be used 
# for the rest of the script
#
Select-AzureSubscription -SubscriptionName "Example"
Get-AzureSubscription

# See all servers in the subscription
Get-AzureSqlDatabaseServer

# Create a new server in West US region, and check the servers again
$serverLogin = "mylogin"
$serverPassword = "Sql@zure"
$server = New-AzureSqlDatabaseServer -AdministratorLogin $serverLogin -AdministratorLoginPassword $serverPassword -Location "West US"
Get-AzureSqlDatabaseServer

# Get just newly created server
$server | Get-AzureSqlDatabaseServer

# Get all firewall rules in all servers in subscription
Get-AzureSqlDatabaseServer | Get-AzureSqlDatabaseServerFirewallRule


# Add a new firewall rule : This rule opens all IPs to the server and is just an example - not recommended
$server | New-AzureSqlDatabaseServerFirewallRule -RuleName AllOpen -StartIPAddress 0.0.0.0 -EndIPAddress 255.255.255.255

# Check the firewall rules again
Get-AzureSqlDatabaseServer | Get-AzureSqlDatabaseServerFirewallRule

# To create a database on the server
# Connect to the server using Sql Authentication
#
$servercredential = new-object System.Management.Automation.PSCredential("mylogin", ("Sql@zure"  | ConvertTo-SecureString -asPlainText -Force))
$ctx = $server | New-AzureSqlDatabaseServerContext -Credential $serverCredential

# List databases
#
Get-AzureSqlDatabase $ctx

# Create a new database
#
$db = New-AzureSqlDatabase $ctx -DatabaseName Demo
Get-AzureSqlDatabase $ctx

# Instead of creating a SQL Authentication context it is possible to also directly pipe in the server object. 
#This will use your certificate authentication to create the SQL SB
#
$server | New-AzureSqlDatabase –DatabaseName “example”

