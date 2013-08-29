<#
.SYNOPSIS
    creates a sql db and set server firewall rule based on the parameters location, 
    name, user id, password
.DESCRIPTION
   This function creates a database server, sets up server firewall rules and then 
   creates a Database. It uses New-AzureSqlDatabaseServer cmdlet to create the server, 
   New-AzureSqlDatabaseServerFirewallRule to create the firewall rule, 
   New-AzureSqlDatabase cmdlet to create the database. 
 
    `
.EXAMPLE
    $db = CreateDatabase -Location "West US" -AppDatabaseName "AppDatabaseName"
     -UserName "UserName" -Password "Password" -RuleName "RuleName" 
     -FirewallRuleName "FirewallRuleName" -StartIPAddress "0.0.0.0" -EndIPAddress "0.0.0.0"
#>


function CreateDatabase($Location,$AppDatabaseName, $Credential, $ClientIP)
{
    # Create Database Server
    Write-Verbose "Creating SQL Azure Database Server."
    $databaseServer = New-AzureSqlDatabaseServer -AdministratorLogin $Credential.UserName `
        -AdministratorLoginPassword $Credential.GetNetworkCredential().Password -Location $Location
    Write-Verbose ("SQL Azure Database Server '" + $databaseServer.ServerName + "' created.")
    
    # Apply Firewall Rules
    $clientFirewallRuleName = "ClientIPAddress_" + [DateTime]::UtcNow
    Write-Verbose "Creating client firewall rule '$clientFirewallRuleName'."
    New-AzureSqlDatabaseServerFirewallRule -ServerName $databaseServer.ServerName `
        -RuleName $clientFirewallRuleName -StartIpAddress $ClientIP -EndIpAddress $ClientIP | Out-Null  


    $azureFirewallRuleName = "AzureServices"
    Write-Verbose "Creating Azure Services firewall rule '$azureFirewallRuleName'."
    New-AzureSqlDatabaseServerFirewallRule -ServerName $databaseServer.ServerName `
        -RuleName $azureFirewallRuleName -StartIpAddress "0.0.0.0" -EndIpAddress "0.0.0.0"
    
    # Create Database
    $serverName = $databaseServer.ServerName
    $context = New-AzureSqlDatabaseServerContext -ServerName $serverName -Credential $Credential
    Write-Verbose "Creating database '$AppDatabaseName' in database server $serverName."
    New-AzureSqlDatabase -DatabaseName $AppDatabaseName -Context $context
   
    return $serverName;
}
