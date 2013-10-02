# Automated Deployment of SQL Server DW IaaS with Windows Azure PowerShell

##  About the Script
This script **New-AzureSqlDwIaasVM.ps1** is used to deploy a SQL Server Data Warehouse in Windows Azure Virtual Machines (VM) with empty Azure disks attached to the VM automatically.

The script is specifically designed for quickly spinning up a starting infrastructure for *Data Warehousing* workloads in Windows Azure. 

## Description
This script allows a user to create a *Data Warehousing* optimized VM on Azure running SQL Server 2012 or SQL Server 2014, script will also attach empty disks to the VM to be used for Sql server data and log files.

Attached disks are 1023GB each, size is not configurable, Azure subscriber will only get billed for used capacity. 
**New-AzureSqlDwIaasVM.ps1** implements the following: 
*	Import Windows Azure module (Needed to use Windows Azure PowerShell cmdlets) 
*	Import Azure publish settings (User account info etc.) 
*	Create Azure affinity group 
*	Create Azure storage account
*	Set Azure subscription 
*	Create New Azure VM with additional empty Azure disks

For more details on SQL Server DW IaaS (also known as *SQL Server Data Warehouse in Windows Azure Virtual Machines*), please check:
* http://go.microsoft.com/fwlink/?LinkId=320440
* http://go.microsoft.com/fwlink/?LinkId=320441


## Release and Support Status
The scripts are provided as samples and are not officially supported by Windows Azure support. We are very interested in feedback so please report issues through the GitHub repo.

## Configuring your environment.

Step 1: [Download the Latest Windows Azure PowerShell Cmdlets](http://go.microsoft.com/?linkid=9811175&clcid=0x409)

Step 2: [Download the zip file containing all of the PowerShell Sample Scripts] (https://github.com/WindowsAzure/azure-sdk-tools-samples/archive/master.zip)

Step 3: Launch PowerShell or PowerShell_ISE elevated 

Step 4: [Prepare your PowerShell Environment for Windows Azure] (http://msdn.microsoft.com/en-us/library/windowsazure/jj554332.aspx)

Step 5: Enable the ByPass PowerShell execution policy by running `Set-ExecutionPolicy ByPass`. This will allow the downloaded scripts to run without individually prompting you.

Step 6: Ensure your subscription has enough cores to create the VMs. Instance sizes for a VM can be specified as input parameters to **New-AzureSqlDwIaasVM.ps1**. Your subscription quota information can be obtained by calling Get-AzureSubscription -ExtendedDetails.
 
# Using the New-AzureSqlDwIaasVM.ps1 file to deploy a Data warehouse optimized VM.
The script **New-AzureSqlDwIaasVM.ps1** will provision an Azure VM running SQL Server Data warehouse optimized image and empty Azure disks to be used by SQL Server data and log files.
**New-AzureSqlDwIaasVM.ps1** script takes several parameters that allow you to customize the environment. 

1.	`-PublishSettingsFile` - Required

   Specifies the full path and filename for the **.publishsettings** file for the Windows Azure account.
This file contains settings and an encoded certificate that provides management credentials for the Windows Azure account. 

    *Security Note: The file downloaded contains an encoded management certificate that serves as the credentials to administer Windows Azure subscriptions and services. Store this file in a secure location or delete it after you use it.*

2.	`-InstanceSize` - Required

   Specifies the size of the virtual machine. For a list of virtual machine sizes, see http://msdn.microsoft.com/library/dn197896.aspx.

3.	`-SQL14` - Required

   This is a switch, the latest SQL Server 2014 for data warehousing on WS 2014 image will be used
Either `-SQL14` or `-SQL12` can be used

3.	`-SQL12` - Required

   This is a switch, the latest SQL Server 2012 for data warehousing on WS 2012 image will be used
Either `-SQL14` or `-SQL12` can be used

4.	`-AzureAffinityGroup` - Required

   A name is assigned to the affinity group at the time of creation.
Note that names for affinity groups created through the Management Portal are typically GUIDs and that the UI shows its label.

   If the Azure Service already exists the AzureAffinityGroup is not needed.

5.	`-Location` - Required

   The Location parameter specifies the geographical location of the data center where the affinity group will be created.

   If the Azure Service already exists the AzureAffinityGroup is not needed.

6.	`-StorageAccountName` - Required

   Account that provides access to Windows Azure storage services. A storage account is a globally unique resource within the storage system. The account is the parent namespace for the Blob, Queue, and Table services.

7.	`-VMName` - Required

   Specifies the name of the virtual machine.

8.	`-ServiceName` - Required

   Specifies the new or existing service name.

9.	`-SubscriptionName` - Required

   Retrieves the configuration settings for the subscription identified by this name. The Default, Current, and SubscriptionName parameters are mutually exclusive.

   If Azure user has multiple subscriptions this parameter will be required, if there is only one subscription the parameter is not required.

10.	`-AdminAccount` - Required

   Specifies the name for the user account to create for administrative access to the virtual machine.

11.	`-AdminPassword` - Required

   Specifies the password of the user account that has permission to add the computer to a domain.

12.	`-PublicPort` - Optional 

   Specifies the public port that the endpoint will use.

13.	`-LocalPort` - Optional 

   Specifies the local (private) port that will be used for the endpoint. Applications within the virtual machine listen to this port to service input requests over the endpoint.


Ensure your subscription is correctly set by running:
<br />`Get-AzureSubscription -Current`

Ensure you have enough cores available in your subscription:
<br />`Get-AzureSubscription -ExtendedDetails`

Ensure your machine will not power off during the deployment. 
Open the master **New-AzureSqlDwIaasVM.ps1** in PowerShell_ISE or your favorite editor and set desired parameters.

Note: It is recommended to either use ISE or another PS Execution environment with a large console history as the scripts can output a lot of information and unless the console buffer is made much bigger output useful for troubleshooting could be list. 
### Notes on Deploying to a Data warehouse optimized VM using New-AzureSqlDwIaasVM.ps1:
**New-AzureSqlDwIaasVM.ps1** will create a VM with empty Azure data disks attached to the VM, the number of disks or disk size is not configurable, manual modification will results in un-wanted behavior.
The table below highlights the number of disks that will get attached:

| Instance Size | Number of Data disks|Number of Log disks| Number of shared Data & Log disks|Total Number of disks|
| ------------- |:-------------------:|------------------:|---------------------------------:|--------------------:|
| A7            | 8                   | 1                 | X                                | 9                   |
| A6            | 4                   | 1                 | X                                | 5                   |
| A5            | 2                   | 1                 | X                                | 3                   |
| ExtraLarge    | 8                   | 1                 | X                                | 9                   |
| Large         | 4                   | 1                 | X                                | 5                   |
| Medium        | 2                   | 1                 | X                                | 3                   |
| Small         | X                   | X                 | 1                                | 1                   |
| ExtraSmall    | X                   | X                 | 1                                | 1                   |


Apart from attaching the disks the scripts will do the following:
*	Check that the Windows Azure SDK is installed and import the PowerShell Azure module.
*	Check if the Azure publish settings file exits in provided path and import it , if it doesn’t exist open default browser, signs into Windows Azure account, and automatically download a **.publishsettings** file that contains information and a certificate for the Windows Azure subscription.
*	Validate that the requested image and instance size exist in select location.
*	Prompt the user to select an azure subscription if there exists multiple ones and user didn’t explicitly select one.
*	Create a new affinity group for the provided affinity group name and validate the location if it already exists.
*	Create a new storage account for the provided storage account name and validate the location if it already exists.
*	Create a new Azure VM using either SQL 2012 or SQL 2014 Data warehousing optimized images with azure empty disks attached.
