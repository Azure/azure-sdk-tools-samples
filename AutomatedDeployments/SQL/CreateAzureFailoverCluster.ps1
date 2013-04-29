
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

#########################################################################################################
#
# Powershell script to create a cluster in Azure environment
# It must be run on a machine which is going to become a node in the cluster
#
# Syntax:
#
#     .\CreateAzureFailoverCluster.ps1 -ClusterName "ClusterName" -ClusterNode "Node1","Node2",... [-Force]
#   
#
# Example 1     
#     Running this command on Machine1 or Machine2 will create cluster "MyCluster"
#
#     .\CreateAzureFailoverCluster.ps1 -ClusterName "MyCluster" -ClusterNodes "Machine1", "Machine2" 
#
#
#
# Example 2
#     Running this command on Machine1 or Machine2 will create cluster "MyCluster", erasing any previous cluster state that was on the nodes
#
#     .\CreateAzureFailoverCluster.ps1 -ClusterName "MyCluster" -ClusterNodes "Machine1", "Machine2" -Force
#    
#
#  Summary of the script:
#     1. Create a 1 node cluster on local node
#     2. Set cluster IP address to static IP 169.254.1.1
#     3. Online the "Cluster Name" so that it will create an entry in active directory 
#     4. Offline the "Cluster Name"
#     5. Delete the fake "Cluster IP"
#     6. Add the other nodes to the cluster
#
#
#########################################################################################################




param(
   [Parameter(Mandatory=$true)]
   $ClusterName,
   [Parameter(Mandatory=$true)]
   $ClusterNodes,
   [Parameter(Mandatory=$false)]
   [Switch]$Force)


Import-Module ServerManager

$OsBuildNumber = [System.Environment]::OSVersion.Version.Build

if ($OsBuildNumber -lt 7600)
{
  Write-Error "Not support on Windows Visa or lower"
  exit 1
}
elseif ($OsBuildNumber -lt 9200)
{
  Write-Output "Windows Server 2008 R2 detected" 
  $ClusterFeature = Get-WindowsFeature "Failover-Clustering"
  $ClusterTools = Get-WindowsFeature "RSAT-Clustering"
  if ($ClusterFeature.Installed -eq $false -or $ClusterFeature.Installed -eq $false)
  {
    Write-Output "Needed cluster features were not found on the machine. Please run the following command to install them:"
    Write-Output "Add-WindowsFeature 'Failover-Clustering', 'RSAT-Clustering'"
    exit 1
  }
  
}
else 
{
  Write-Output "Windows Server 2012 or above detected"

  $ClusterFeature = Get-WindowsFeature "Failover-Clustering"
  $ClusterPowerShellTools = Get-WindowsFeature "RSAT-Clustering-PowerShell"
  $ClusterCmdTools = Get-WindowsFeature "RSAT-Clustering-CmdInterface"

  if ($ClusterFeature.Installed -eq $false -or $ClusterPowerShellTools.Installed -eq $false -or $ClusterCmdTools.Installed -eq $false)
  {
    Write-Output "Needed cluster features were not found on the machine. Please run the following command to install them:"
    Write-Output "Add-WindowsFeature 'Failover-Clustering', 'RSAT-Clustering-PowerShell', 'RSAT-Clustering-CmdInterface'"
    exit 1
  }

}



Import-Module FailoverClusters

$LocalMachineName = $env:computername
$LocalNodePresent = $false

# The below line will make sure that the script is running on one of the specified cluster nodes
# The Spplit(".") is needed, because user might specify machines using their fully qualified domain name, but we only care about the machine name in the below verification
@($ClusterNodes) | Foreach-Object { 
                       if ([string]::Compare(($_).Split(".")[0], $LocalMachineName, $true) -eq 0) { 
                             $LocalNodePresent = $true } }


if ($LocalNodePresent -eq $false)
{
  Write-Error "Local machine where this script is running, must be one of the cluster nodes"
  exit 1
}

if ($Force)
{
  Write-Output "Forcing cleanup of the specified nodes"

  @($ClusterNodes) | Foreach-Object { Clear-ClusterNode "$_" -Force } 

}
else
{

  Write-Output "Making sure that there is no cluster currently running on the current node"

  $CurrentCluster = $null
  # In case there is no cluster presetn, we don't want to show an ugly error message, so we eat it out by redirecting
  # the error output to null
  $CurrentCluster = Get-Cluster 2> $null


  if ($CurrentCluster -ne $null)
  {
    Write-Error "There is an existing cluster on this machine. Please remove any existing cluster settings from the current machine before running this script"
    exit 1
  }

}


Write-Output "Trying to create a one node cluster on the current machine"

Sleep 5

New-Cluster -Name $ClusterName -NoStorage -Node $LocalMachineName

Write-Output "Verify that cluster is present after creation"

$CurrentCluster = $null
$CurrentCluster = Get-Cluster

if ($CurrentCluster -eq $null)
{
  Write-Error "Cluster does not exist"
  exit 1
}



Write-Output "Bring offline the cluster name resource"
Sleep 5
Stop-ClusterResource "Cluster Name"

Write-Output "Get all IP addresses associated with cluster group"
$AllClusterGroupIPs = Get-Cluster | Get-ClusterGroup | Get-ClusterResource | Where-Object {$_.ResourceType.Name -eq "IP Address" -or $_.ResourceType.Name -eq "IPv6 Tunnel Address" -or $_.ResourceType.Name -eq "IPv6 Address"}

$NumberOfIPs = @($AllClusterGroupIPs).Count
Write-Output "Found $NumberOfIPs IP addresses"

Write-Output "Bringing all IPs offline"
Sleep 5
$AllClusterGroupIPs | Stop-ClusterResource

Write-Output "Get the first IPv4 resource"
$AllIPv4Resources = Get-Cluster | Get-ClusterGroup | Get-ClusterResource | Where-Object {$_.ResourceType.Name -eq "IP Address"}
$FirstIPv4Resource = @($AllIPv4Resources)[0];

Write-Output "Removing all IPs except one IPv4 resource"
Sleep 5
$AllClusterGroupIPs | Where-Object {$_.Name -ne $FirstIPv4Resource.Name} | Remove-ClusterResource -Force

$NameOfIPv4Resource = $FirstIPv4Resource.Name

Write-Output "Setting the cluster IP address to a link local address"
Sleep 5
cluster res $NameOfIPv4Resource /priv enabledhcp=0 overrideaddressmatch=1 address=169.254.1.1 subnetmask=255.255.0.0

$ClusterNameResource = Get-ClusterResource "Cluster Name"

$ClusterNameResource | Start-ClusterResource -Wait 60

if ((Get-ClusterResource "Cluster Name").State -ne "Online")
{
  Write-Error "There was an error onlining the cluster name resource"
  exit 1
}


Write-Output "Stopping the cluster IP address"
Sleep 5
$FirstIPv4Resource | Stop-ClusterResource
$ClusterNameResource | Stop-ClusterResource

Write-Output "Removing the cluster IP address"
Sleep 5
$FirstIPv4Resource  | Remove-ClusterResource -Force


Write-Output "Adding other nodes to the cluster" 
@($ClusterNodes) | Foreach-Object { 
                       if ([string]::Compare(($_).Split(".")[0],$LocalMachineName, $true) -ne 0) { 
                             Add-ClusterNode "$_" } }

Write-Output "Cluster creation finished !"
exit 0 
























