cls

foreach($Server in Get-AzureSqlDatabaseServer)
{

    Remove-AzureSqlDatabaseServer -ServerName $Server.Servername -Force
    Write-Host "Deleting Server: " +  $Server.Servername
}

$scriptPath = "{0}\Create-AzureEnterpriseSite.ps1" -f (Split-Path -parent $PSCommandPath)
Write-Host $scriptPath

$test = & $scriptPath `
    -ServiceName "jpggTest"  `
    -ServiceLocation "West US" `
    -sqlAppDatabaseName "myDB" `
    -SqlDatabasePassword "lala@lolo123qwew"  `
    -StartIPAddress "1.0.0.1" `
    -EndIPAddress "255.255.255.255" `
    -SqlDatabaseUserName "dbuser"`
    -ConfigurationFilePath "K:\1_Documentos\GitHub\azure-sdk-tools-samples\solutions\web\EnterpiseSite\ServiceConfiguration.Cloud.cscfg" `
    -PackageFilePath "K:\1_Documentos\GitHub\azure-sdk-tools-samples\solutions\web\EnterpiseSite\WebCorpHolaMundo.Azure.cspkg"

<#
Write-Host $test.SqlServer
Write-Host $test.storage.AccountName

$borrar=Read-Host "Borrar todo?"
if ($borrar -eq "y")
{
    #borrar todo
    Remove-AzureSqlDatabaseServer -ServerName $test.SqlServer -Force
    Write-Host "Deleting Server: " +  $test.SqlServer
}
else
{
    $borrar=Read-Host "Borrar SQL?"
    if ($borrar -eq "y")
{
    #borrar todo
    Remove-AzureSqlDatabaseServer -ServerName $test.SqlServer -Force
    Write-Host "Deleting Server: " +  $test.SqlServer
}
}
#>