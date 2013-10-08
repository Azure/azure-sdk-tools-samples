# New-HDInsightCluster
## Description ##
Creates a HDInsight cluster configured with one storage account and default metastores. If storage account or container are not specified they are created automatically under the same name as the one provided for cluster. If ClusterSize is not specified it defaults to create small cluster with 2 nodes. User is prompted for credentials to use to provision the cluster.

During the provisioning operation which usually takes around 15 minutes the script monitors status and reports when cluster is transitioning through the provisioning states.

**Note:** This script requires an Azure HDInsight cmdlets to be installed on the machine in addition to Azure PowerShell Tools. Azure HDInsight cmdlets can be installed according to the instructions here: https://hadoopsdk.codeplex.com/wikipage?title=PowerShell%20Cmdlets%20for%20Cluster%20Management

## Scenario ##
You want to provision a Hadoop cluster in default configuration and connected to single storage account.
## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013
- Windows Azure HDInsight PowerShell Oct 2013

## See Also ##
- Set-AzureSubscription