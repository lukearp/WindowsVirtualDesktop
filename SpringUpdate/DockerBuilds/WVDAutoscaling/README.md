# Docker container to manage Host Pool Autoscaling
> Clone repo, browse to /SpringUpdate/DockerBuilds/WVDAutoscaling and run:
```
docker build -t "NameOfContainer" .
```
> Environmental Variables Required to Run
```
base64={PFX in Base64 format}
certPass={PFX Password}
thumbprint={Public Cert Thumbprint that is uploaded to Azure AD Application}
HostpoolName={Name of Hostpool}
HostPoolResourceGroupName={Resource Group for WVD Host Pool}
BeginPeakDateTime={Time to start scaling up - Ex: 7:00 = 7 AM}
EndPeakDateTime={Time to start scaling down - Ex: 17:00 = 5 PM}
TimeZoneId={Time Zone ID - Ex: America/New_York = EST}
FullPeakHours={Number of hours past Peak time with an increased minimum of hosts}
PeakTimeUserBuffer={Number added to total sessions to keep hosts powered on durring Peak}
SessionThresholdPerCPU={Number of users per CPU Core}
PeakMinimumNoOfRDSH={Minimum number of hosts durring FullPeakHours}
MinimumNumberOfRDSH={Minimum outside of FullPeak}
LimitSecondsToForceLogOffUser={Number of seconds before a users is forced to log off durring scale down}
LogOffMessageTitle="Auto Log Off"
LogOffMessageBody="Your session host is powering down. Please save your work.  Once logged off you can reconnect to an available host."
MaintenanceTagName={Azure Tag Key that keeps the Session Host in Drain Mode}
WVDApplicationId={AAD App ID that has Contributor rights to the WVD Host Pool}
WVDTenantId={AAD App Tenant ID that has Contributor rights to the WVD Host Pool}
WVDSubscriptionId={Azure Subscription Id that has the WVD Host Pool}
AzApplicationId={AAD App ID that has rights to the WVD Session Hosts to Power On and Power Off}
AzTenantId={AAD App Tenant ID that has rights to the WVD Session Hosts to Power On and Power Off}
AzSubscriptionId={Azure Subscription Id that has the WVD Session Hosts running}
```

> Can run in ACI instance, App Service, AKS, or anything else that runs docker.  The Entry Point of the container runs the scaling script based in the ENV values. 

> If you build localy in you can kick off a run with:
* docker run -d --env-file .\ENV.txt wvdautoscale
    * In this example I tagged my build wvdautoscale and I had a file with all my ENV Variables populated called ENV.txt
