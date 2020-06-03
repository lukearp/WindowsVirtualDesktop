# BasicAutoscaleRunbookScript-MultiTenant-SpringUpdate.ps1

> Modified version of the Autoscaling script published: https://docs.microsoft.com/en-us/azure/virtual-desktop/virtual-desktop-fall-2019/set-up-scaling-script .  Most basic functionality of the original is working.  Still testing

> This is to Autoscale Hostpools deployed with the Spring Update, and modify scaling behavior to meet my deployment needs.  

> Modules need to be imported to the Azure Automation Account
```
Az.Accounts
Az.Compute
Az.Network
Az.Resources
Az.DesktopVirtualization
```

> Variable Overview
```
$HostpoolName = "Name of WVD Host Pool"
$BeginPeakDateTime = "7:00" # Start of Peak Time on a 24 Hour clock - Example 17:00 = 5:00 PM
$EndPeakDateTime = "17:00" # End of Peak Time on 24 Hour Clock
$TimeZoneId = "Eastern Standard Time" # Time Zone Name.  You can get compatible names using Powershell command 'Get-TimeZone -ListAvailable'
$FullPeakHours = 4 # This gets added to the $BeginPeakDateTime variable to allow you to set a higher minimum number of hosts for a window
$PeakTimeUserBuffer = 4 # This number gets added to Active User Sessions to power on a Buffer host during peak times
$SessionThresholdPerCPU = 1 # Number of users Per Core.  Example: 4 Core Machine, $SessionThresholdPerCPU = 4, 16 Users on a Host is viewed as a full host
$PeakMinimumNoOfRDSH = 4 # Minimum Number of Session hosts durring 'Full Peak'
$MinimumNumberOfRDSH = 1 # This is the absolute minimum of Session Hosts
$LimitSecondsToForceLogOffUser = 120 # Durring off Peak times, if hosts that have active sessions need to be powered down, this is the ammount of time in Sesconds users have to save their work
$LogOffMessageTitle = "Auto Log Off" # Title of pop up screen to users
$LogOffMessageBody = "Your session host is powering down. Please save your work.  Once logged off you can reconnect to an available host." # Message sent to users
$MaintenanceTagName = "Maintenance" # Azure Tag, that if pressent puts Session Host's AllowNewSessions Property to False
$HostPoolResourceGroupName = "" # Resource Group of the Host Pool WVD Object
```