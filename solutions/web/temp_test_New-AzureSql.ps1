Clear-Host
Write-Host "###############################################################################################"
foreach($Server in Get-AzureSqlDatabaseServer)
{

    Remove-AzureSqlDatabaseServer -ServerName $Server.Servername -Force
    Write-Host "Deleting Server: " +  $Server.Servername
}

$ParametersIn = @{

    AppDatabaseName = "appdb";
    SqlDatabaseUserName  = "dbuser";
    Password ="lala@lolo123";
    FirewallRuleName="FirewallRuleName";
    StartIPAddress="1.1.1.1";
    EndIPAddress="255.255.255.255";
    Location = "West US";
}

$strExe =  ".\New-AzureSql.ps1 "

Write-Verbose "Parameters"
foreach ($p in $ParametersIn.Keys)
{
    Write-Host $ParametersIn[$p]
    #Write-Host $p
    #$strExe = $strExe + " -" + $p + "=""""" + $ParametersIn[$p] +""""""
    #$strExe = $strExe + " -" + $p + "=''" + $ParametersIn[$p] +"''"
    $strExe = $strExe + "-" + $p + " """ + $ParametersIn[$p] +""" "

}

Write-Verbose "Comannd"
Write-Host $strExe

#$resultado= invoke-expression $strExe 
#$resultado = Invoke-Expression -Command ".\New-AzureSql.ps1" $ParametersIn
$resultado= Invoke-Expression ".\New-AzureSql.ps1 -Password ""lala@lolo123"" -AppDatabaseName ""appdb"" -SqlDatabaseUserName ""dbuser"" -StartIPAddress ""1.1.1.1"" -EndIPAddress ""255.255.255.255""  -FirewallRuleName ""FirewallRuleName"" -Location ""West US""  "
#$resultado= invoke-expression  "K:\1_Documentos\GitHub\azure-sdk-tools-samples\solutions\web\New-AzureSql.ps1" $ParametersIn
Write-Verbose "Results"
Write-Host "Server name:" + $resultado.Server
Write-Host "Connection String: " + $resultado.AppDatabase.ConnectionString

Write-Host "###############################################################################################"
[string] $ServerName=$resultado.Server
 Remove-AzureSqlDatabaseServer  -ServerName $ServerName -Force 
    Write-Host "Deleting Server: " +  $resultado.Server
