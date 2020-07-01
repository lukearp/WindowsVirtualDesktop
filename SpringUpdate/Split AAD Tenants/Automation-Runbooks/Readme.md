# Autoscaling for Azure Automation Accounts

## Requirements
1. Azure Automation Account with following modules
    * Az.Accounts
    * Az.Compute
    * OMSIngestionAPI
    * Az.DesktopVirtualization
2. A Service Principal in AAD Tenant to manage Azure VM Resources and a Service Principal to manage Azure WVD Resources needs to be created
    * These service prinicipas then need to have a Public Certificate associated
    * The PFX needs to be uploaded to the Azure Automation Account
    * Automation Connections need to be created referencing the two service principals and Certificate Thumbprints
3. A Azure Automation Runbook with the contents of Official-BasicScale-SpringUpdate-Multisession.ps1 saved and published
4. A Webhook associated to the Automation Runbook
3. A Logic app needs to be deployed with a Recurrence Trigger
    * HTTP Post will be the step with JSON body

## Logic App

> Configure a logic app instance for every hostpool you are wanting to Autoscale.  You can use the same Runbook webhook.

> Example Body for Logic App
```
{
  "BeginPeakTime": "09:00",
  "ConnectionAssetName": "AzureRunAsConnection",
  "EndPeakTime": "18:00",
  "HostPoolName": "Spring",
  "LimitSecondsToForceLogOffUser": 120,
  "LogAnalyticsPrimaryKey": "#####==",
  "LogAnalyticsWorkspaceId": "1984e8fa-####-####-####-###########",
  "LogOffMessageBody": "Autoscaling event has started.  Save your work and log back into the service",
  "LogOffMessageTitle": "Host Pool Scaling Event",
  "MaintenanceTagName": "Maintenance",
  "MinimumNumberOfRDSH": 2,
  "ResourceGroupName": "rg_wvd_spring",
  "SessionThresholdPerCPU": 2,
  "TimeZoneId": "Eastern Standard Time",
  "WVDConnectionAssetName": "WVDConnection"
}
```

## Parameter Overview
> BeginPeakTime             Time that Peak time starts.  User 24 hour clock Ex: 09:00 = 9am 14:00 = 2pm
> EndPeakTime               Time that Peak time ends.  User 24 hour clock Ex: 09:00 = 9am 14:00 = 2pm
> TimeZoneId                Time zone your sessions hosts are supporting. Ex: "Eastern Standard Time"
> ConnectionAssetName       Automation Connection name tied to AAD Service Principal for managing Azure VMs
> WVDConnectionAssetName    Automation Connection name tied to AAD Service Principal for managing Azure WVD Resources
> HostPoolName              WVD Host pool name
> ResourceGroupName         Azure resource group name that has the WVD Host Pool object
> LogAnalyticsWorkspaceId   Log analytics workspace for Automation logging (Optional)
> LogAnalyticsWorkspaceId   Workspace Key (Optional)
> MinimumNumberOfRDSH       Minimum number of running hosts in WVD Host pool
> SessionThresholdPerCPU    Number of active user sessions per session host core
> LogOffMessageTitle        Title of message window that will appear to active users on hosts that are scaling down
> LogOffMessageBody         Contents of message window

## Feature Enhancements
> This script is based on the Offical scaling script: https://github.com/nakranimohit0/azure-docs/blob/yammer_private_preview_wvd_scaling/articles/virtual-desktop/set-up-scaling-script.md

> Added was the ability to support a deployment that required the Azure VMs to be managed by one AAD Tenant, and the WVD Objects be managed by another.  

> Future added features
* Set days for Peek hours
* Set startup peek minimum hosts that are not based on curent connections
* Set concurrent user buffer to ensure there is a availble host for new users logging into the system