<#
 * Copyright Microsoft Corporation
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
#>

cls


$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptFolder\SharedComponents\SharedFunctions.ps1"

if((IsAdmin) -eq $false)
{
    Write-Host "Must run elevated."
    return
}

Write-Host "Starting SharePoint 2013 High Availability Installation"

$ad = "$scriptFolder\AD\ProvisionAD.ps1"
$adconfig = "Config\HighlyAvailable\AD-Sample-HA.xml"

$sql = "$scriptFolder\SQL\ProvisionSQL.ps1"
$sqlConfig = "Config\HighlyAvailable\SQL-Sample-HA.xml"

$sp = "$scriptFolder\SharePoint\ProvisionSharePoint.ps1"
$spconfig = "Config\HighlyAvailable\SharePoint-Sample-HA.xml"


Write-Host "Installing Active Directory" 
& $ad -configFilePath $adconfig

Write-Host "Installing SQL Server"
& $sql -configFilePath $sqlConfig

Write-Host "Installing SharePoint Server 2013"
& $sp -configFilePath $spconfig
