$HostpoolName = ""
$BeginPeakDateTime = ""
$EndPeakDateTime = ""
$TimeZoneId = "Eastern Standard Time"
$FullPeakHours = 4
$PeakTimeUserBuffer = 4
$SessionThresholdPerCPU = 1 #int
$PeakMinimumNoOfRDSH = 4
$MinimumNumberOfRDSH = 1 #int
$LimitSecondsToForceLogOffUser = 120 #int
$LogOffMessageTitle = "Auto Log Off"
$LogOffMessageBody = "Your session host is powering down. Please save your work.  Once logged off you can reconnect to an available host."
$MaintenanceTagName = ""
$HostPoolResourceGroupName = "" 

$WVDConnection = Get-AutomationConnection -Name 'WVDConnection'
$Connection = Get-AutomationConnection -Name $ConnectionAssetName

#Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
#Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
# Setting ErrorActionPreference to stop script execution when error occurs
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#Function to convert from UTC to Local time
function Convert-UTCtoLocalTime {
    $timezoneInfo = Get-TimeZone -Id $TimeZoneId    
    $inputDateTime = Get-Date -Date (Get-Date).ToUniversalTime() -f s
    $time = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($inputDateTime, "UTC", $timezoneInfo.StandardName)
    
    return Get-Date -Date $time -Format "HH:mm"
}
# With workspace
   
    function Login-ToAzureForSessionHosts
    {
        param($Connection)
        try{
            Disconnect-AzAccount
            Clear-AzContext -Force
        }
        catch {

        }
        $AZAuthentication = Connect-AzAccount -ApplicationId $Connection.ApplicationId -TenantId $Connection.TenantId -CertificateThumbprint $Connection.CertificateThumbprint -ServicePrincipal -SubscriptionId $Connection.SubscriptionId
        if ($AZAuthentication -eq $null) {
            Write-Output "Failed to authenticate Azure: $($_.exception.message)"
            exit
        }
        else {
            $AzObj = $AZAuthentication
            Write-Output "Authenticating as service principal for Azure. Result: `n$AzObj"
        }
    }

    function Login-ToAzureForWorkspace
    {
        param($WVDConnection)
        try{
            Disconnect-AzAccount
            Clear-AzContext -Force
        }
        catch {

        }
        $AZAuthentication = Connect-AzAccount -ApplicationId $WVDConnection.ApplicationId -TenantId $WVDConnection.TenantId -CertificateThumbprint $WVDConnection.CertificateThumbprint -ServicePrincipal -SubscriptionId $WVDConnection.SubscriptionId
        if ($AZAuthentication -eq $null) {
            Write-Output "Failed to authenticate Azure: $($_.exception.message)"
            exit
        }
        else {
            $AzObj = $AZAuthentication
            Write-Output "Authenticating as service principal for Azure. Result: `n$AzObj"
        }
    }

    #Function to Check if the session host is allowing new connections      

$functions = {
    function Login-ToAzureForSessionHosts
    {
        param($Connection)
        try{
            Disconnect-AzAccount
            Clear-AzContext -Force
        }
        catch {

        }
        $AZAuthentication = Connect-AzAccount -ApplicationId $Connection.ApplicationId -TenantId $Connection.TenantId -CertificateThumbprint $Connection.CertificateThumbprint -ServicePrincipal -SubscriptionId $Connection.SubscriptionId
        if ($AZAuthentication -eq $null) {
            Write-Output "Failed to authenticate Azure: $($_.exception.message)"
            exit
        }
        else {
            $AzObj = $AZAuthentication
            Write-Output "Authenticating as service principal for Azure. Result: `n$AzObj"
        }
    }

    function Login-ToAzureForWorkspace
    {
        param($WVDConnection)
        try{
            Disconnect-AzAccount
            Clear-AzContext -Force
        }
        catch {

        }
        $AZAuthentication = Connect-AzAccount -ApplicationId $WVDConnection.ApplicationId -TenantId $WVDConnection.TenantId -CertificateThumbprint $WVDConnection.CertificateThumbprint -ServicePrincipal -SubscriptionId $WVDConnection.SubscriptionId
        if ($AZAuthentication -eq $null) {
            Write-Output "Failed to authenticate Azure: $($_.exception.message)"
            exit
        }
        else {
            $AzObj = $AZAuthentication
            Write-Output "Authenticating as service principal for Azure. Result: `n$AzObj"
        }
    }

    #Function to Check if the session host is allowing new connections    
    function Set-SessionHostPowerState
    {
        param(
            [string]$SessionHostName,
            [string]$HostpoolName,
            [string]$HostPoolResourceGroupName,
            [switch]$powerDown,
            [object]$Connection,
            [object]$WVDConnection
        )
        Write-Output "Running Set-SessionHostPowerState"
        $status = ""
        $login = Login-ToAzureForSessionHosts -Connection $Connection
        $VMName = $SessionHostName.Split("/")[1].Split(".")[0]
        $sessionVm = Get-AzVM | ?{$_.Name -eq $VMName}
        $cores = (Get-AzVMSize -Location $sessionVm.Location | ?{$_.Name -eq $sessionVm.HardwareProfile.VmSize}).NumberOfCores
        if($powerDown -eq $true)
        {
            Write-Output "Stoping VM: $($VMName)"
            $vm = Stop-AzVM -Name $sessionVm.Name -ResourceGroupName $sessionVm.ResourceGroupName -Confirm:$false -Force
            $status = New-Object -TypeName psobject -Property @{
                VMName = $VMName
                Started = $false
                Cores = $cores
            }
        }
        else 
        {
            # Start the Az VM
            Write-Output "Starting Azure VM: $VMName and waiting for it to complete ..."
            $start = Start-AzVm -Name $sessionVm.Name -ResourceGroupName $sessionVm.ResourceGroupName
            $IsVMStarted = $false
            $count = 0
            while (!$IsVMStarted) {
                if($count -eq 10)
                {
                    $status = New-Object -TypeName psobject -Property @{
                        VMName = $VMName
                        Started = $false
                    }
                    break
                }
                $RoleInstance = Get-AzVM -Status | Where-Object { $_.Name -eq $VMName }
                if ($RoleInstance.PowerState -eq "VM running") {                    
                    $login = Login-ToAzureForWorkspace -WVDConnection $WVDConnection
                    $count = 0
                    do
                    {
                        if($count -eq 10)
                        {
                            $status = New-Object -TypeName psobject -Property @{
                                VMName = $VMName
                                Started = $false
                            }                           
                            $IsVMStarted = $true
                            break;
                        }
                        sleep 60
                        $SessionHostIsAvailable = (Get-AzWvdSessionHost -Name $SessionHostName.Split("/")[1] -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostpoolName -SubscriptionId $WVDConnection.SubscriptionId).Status
                        $count++
                    }while($SessionHostIsAvailable -ne "Available") 
                    if($count -ne 10)
                    {
                        $status = New-Object -TypeName psobject -Property @{
                            VMName = $VMName
                            Started = $true
                            Cores = $cores
                        }                        
                    }                
                    $IsVMStarted = $true
                }
                sleep 20
            }
        }
        return $status
    }
} 

    function Get-FullPeakWindow
    {
        param (
            [string]$CurrentDateTime
        )
        $login = Login-ToAzureForWorkspace -WVDConnection $WVDConnection
        $isPeak = $true
        if ((Get-Date -Date $CurrentDateTime) -ge (Get-Date -Date $BeginPeakDateTime) -and (Get-Date -Date $CurrentDateTime) -le (Get-Date -Date $BeginPeakDateTime).AddHours($FullPeakHours)) {
            $update = Update-AzWvdHostPool -Name $HostpoolName -ResourceGroupName $HostPoolResourceGroupName -SubscriptionId $WVDConnection.SubscriptionId -LoadBalancerType BreadthFirst
        }
        else {
            $isPeak = $false
        }
        return $isPeak
    }

    function Get-IsPeak
    {
        param (
            [string]$CurrentDateTime
        )
        $login = Login-ToAzureForWorkspace -WVDConnection $WVDConnection
        $isPeak = $true
        if ((Get-Date -Date $CurrentDateTime) -ge (Get-Date -Date $BeginPeakDateTime) -and (Get-Date -Date $CurrentDateTime) -le (Get-Date -Date $EndPeakDateTime)) {
        }
        else {
            $isPeak = $false
            $update = Update-AzWvdHostPool -Name $HostpoolName -ResourceGroupName $HostPoolResourceGroupName -SubscriptionId $WVDConnection.SubscriptionId -LoadBalancerType DepthFirst
        }
        return $isPeak
    }

    function Get-DataFromJobs
    {
        param($jobs)
        $jobsRunning = $true
        $returnData = @()
        while($jobsRunning)
        {
            $count = 0
            foreach($job in $jobs)
            {
                if($job.State -eq "Running")
                {
                    $count++
                }
                else 
                {
                    try {
                        $returnData += Receive-Job -Job $job
                    }
                    catch {
                        Write-Output "Job $($job.Name) couldn't Be Received"
                    }
                }
                if($count -eq 19)
                {
                    $jobsRunning = $false
                    try {
                        Get-Job | Stop-Job
                    } catch{

                    }
                }
                if($count -eq 0)
                {
                    $jobsRunning = $false
                }
                else
                {
                    Write-Output "Waiting for Jobs to Finish"
                    sleep 30
                }
            }            
        }
        try {
            Get-Job | Remove-Job
        } catch {

        }
        return $returnData 
    }

    $scriptBlockPowerOn = {
        param($SessionHostName,$HostpoolName,$HostPoolResourceGroupName,$Connection,$WVDConnection)
        Set-SessionHostPowerState -SessionHostName $SessionHostName -HostpoolName $HostpoolName -HostPoolResourceGroupName $HostPoolResourceGroupName -Connection $Connection -WVDConnection $WVDConnection
    }

    $scriptBlockPowerDown = {
        param($SessionHostName,$Connection)
        Set-SessionHostPowerState -SessionHostName $SessionHostName -Connection $Connection -powerDown
    }
    
    #Converting date time from UTC to Local
    $CurrentDateTime = Convert-UTCtoLocalTime
    $isPeak = Get-IsPeak -CurrentDateTime $CurrentDateTime    
    $isFullPeakWindow = Get-FullPeakWindow -CurrentDateTime $CurrentDateTime
    
    #Checking givne host pool name exists in Tenant
    $HostpoolInfo = Get-AzWvdHostPool -ResourceGroupName $HostPoolResourceGroupName -Name $HostpoolName -SubscriptionId $WVDConnection.SubscriptionId
    if ($HostpoolInfo -eq $null) {
        Write-Output "Hostpoolname '$HostpoolName' does not exist in the tenant of '$TenantName'. Ensure that you have entered the correct values."
        exit
    }

    # Setting up appropriate load balacing type based on PeakLoadBalancingType in Peak hours
    $HostpoolLoadbalancerType = $HostpoolInfo.LoadBalancerType
    [int]$MaxSessionLimitValue = $HostpoolInfo.MaxSessionLimit
    Write-Output "Starting WVD tenant hosts scale optimization: Current Date Time is: $CurrentDateTime"
    # Check the after changing hostpool loadbalancer type
    $HostpoolInfo = Get-AzWvdHostPool -ResourceGroupName $HostPoolResourceGroupName -Name $HostpoolName -SubscriptionId $WVDConnection.SubscriptionId

    # Check if the hostpool have session hosts
    $ListOfSessionHosts = Get-AzWvdSessionHost -ResourceGroupName $HostPoolResourceGroupName -SubscriptionId $WVDConnection.SubscriptionId -HostPoolName $HostpoolName
    if ($ListOfSessionHosts -eq $null) {
        Write-Output "Session hosts does not exist in the Hostpool of '$HostpoolName'. Ensure that hostpool have hosts or not?."
        exit
    }



    # Check if it is during the peak or off-peak time
    if ($isPeak) {
        Write-Output "It is in peak hours now"
        Write-Output "Starting session hosts as needed based on current workloads."

        # Peak hours check and remove the MinimumnoofRDSH value dynamically stored in automation variable
        if($isFullPeakWindow)
        {
            Write-Output "Currently Full Peak Time"
            $MinimumNumberOfRDSH = $PeakMinimumNoOfRDSH
        } 												   
        $OffPeakUsageMinimumNoOfRDSH = $MinimumNumberOfRDSH
        # Check the number of running session hosts
        [int]$NumberOfRunningHost = 0
        # Total of running cores
        [int]$TotalRunningCores = 0
        # Total capacity of sessions of running VMs
        $AvailableSessionCapacity = 0
        #Initialize variable for to skip the session host which is in maintenance.
        $SkipSessionhosts = 0
        $SkipSessionhosts = @()
        $login = Login-ToAzureForWorkspace -WVDConnection $WVDConnection
        $HostPoolUserSessions = Get-AzWvdUserSession -HostPoolName $HostpoolName -ResourceGroupName $HostPoolResourceGroupName -SubscriptionId $WVDConnection.SubscriptionId
        $login = Login-ToAzureForSessionHosts -Connection $Connection
        foreach ($SessionHost in $ListOfSessionHosts) {
            $SessionHostName = $SessionHost.Name.Split("/")[1];
            $VMName = $SessionHostName.Split(".")[0]
            # Check if VM is in maintenance
            $RoleInstance = Get-AzVM -Status | Where-Object { $_.Name.Contains($VMName) }
            if($RoleInstance -ne $null)
            {
                if ($RoleInstance.Tags.Keys -contains $MaintenanceTagName) {
                    Write-Output "Session host is in maintenance: $VMName, so script will skip this VM"
                    $SkipSessionhosts += $SessionHost.Name
                    continue
                }
                #$AllSessionHosts = Compare-Object $ListOfSessionHosts $SkipSessionhosts | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject }
                $AllSessionHosts = $ListOfSessionHosts | Where-Object { $SkipSessionhosts -notcontains $_.Name }

                Write-Output "Checking session host: $($SessionHostName)  of sessions: $($SessionHost.Session) and status: $($SessionHost.Status)"
                if ($SessionHostName.ToLower().Contains($RoleInstance.Name.ToLower())) {
                    # Check if the Azure vm is running       
                    if ($RoleInstance.PowerState -eq "VM running") {
                        [int]$NumberOfRunningHost = [int]$NumberOfRunningHost + 1
                        # Calculate available capacity of sessions						
                        $RoleSize = Get-AzVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
                        $AvailableSessionCapacity = $AvailableSessionCapacity + $RoleSize.NumberOfCores * $SessionThresholdPerCPU
                        [int]$TotalRunningCores = [int]$TotalRunningCores + $RoleSize.NumberOfCores
                    }
                }
            }
        }
            $login = Login-ToAzureForWorkspace -WVDConnection $WVDConnection
            foreach($sessionHost in $AllSessionHosts)
            {
                if($sessionHost.AllowNewSession -ne $true)
                {
                    $update = Update-AzWvdSessionHost -Name $sessionHost.Name.Split("/")[1] -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostPoolName -SubscriptionId $WVDConnection.SubscriptionId -AllowNewSession
                }
            }
            foreach($sessionHost in $SkipSessionhosts)
            {
                if($sessionHost.AllowNewSession -ne $false)
                {
                    $update = Update-AzWvdSessionHost -Name $sessionHost.Name.Split("/")[1] -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostPoolName -SubscriptionId $WVDConnection.SubscriptionId -AllowNewSession:$false
                }
            }
            Write-Output "Current number of running hosts:$NumberOfRunningHost"
            $startedVms = @()
            $login = Login-ToAzureForSessionHosts -Connection $Connection
            if ($NumberOfRunningHost -lt $MinimumNumberOfRDSH) {
                Write-Output "Current number of running session hosts is less than minimum requirements, start session host ..."
                # Start VM to meet the minimum requirement            
                foreach ($SessionHost in $AllSessionHosts.Name) {
                    # Check whether the number of running VMs meets the minimum or not
                    if ($NumberOfRunningHost -lt $MinimumNumberOfRDSH) {
                        $VMName = $SessionHost.Split("/")[1].Split(".")[0]
                        $RoleInstance = Get-AzVM -Status | Where-Object { $_.Name.Contains($VMName) }
                        if ($SessionHost.ToLower().Contains($RoleInstance.Name.ToLower())) {
                            # Check if the Azure VM is running and if the session host is healthy
                            $login = Login-ToAzureForWorkspace -WVDConnection $WVDConnection
                            $SessionHostInfo = Get-AzWvdSessionHost -Name $SessionHost.Split("/")[1] -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostPoolName -SubscriptionId $WVDConnection.SubscriptionId                            
                            $login = Login-ToAzureForSessionHosts -Connection $Connection
                            if ($RoleInstance.PowerState -ne "VM running" -and $SessionHostInfo.UpdateState -eq "Succeeded") {
                                # Check if the session host is allowing new connections
                                if($SessionHostInfo.AllowNewSession = $true)
                                {
                                    Write-Output "Starting VM: $($VMName)"
                                    # Start the Az VM
                                    $startedVms += Start-Job -InitializationScript $functions -ScriptBlock $scriptBlockPowerOn -ArgumentList @($SessionHostInfo.Name,$HostpoolName,$HostPoolResourceGroupName,$Connection,$WVDConnection) -Name $VMName
                                }                            
                                # Calculate available capacity of sessions
                                $login = Login-ToAzureForSessionHosts -Connection $Connection
                                $RoleSize = Get-AzVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
                                $AvailableSessionCapacity = $AvailableSessionCapacity + $RoleSize.NumberOfCores * $SessionThresholdPerCPU
                                [int]$NumberOfRunningHost = [int]$NumberOfRunningHost + 1
                                [int]$TotalRunningCores = [int]$TotalRunningCores + $RoleSize.NumberOfCores
                                if ($NumberOfRunningHost -ge $MinimumNumberOfRDSH) {                                    
                                        break;
                                }
                            }
                        }
                    }
                }
                if($startedVms.Count -gt 0)
                {
                    Get-DataFromJobs -jobs $startedVms
                    Write-Output "Jobs Finished"
                }
                else {
                    Write-Output "VMs Already Running"
                }
            }
            if ($isFullPeakWindow -ne $true) {
            #check if the available capacity meets the number of sessions or not
            Write-Output "Current total number of user sessions: $(($HostPoolUserSessions).Count)"
            Write-Output "Current available session capacity is: $AvailableSessionCapacity"
            if ($HostPoolUserSessions.Count -ge $AvailableSessionCapacity) {
                Write-Output "Current available session capacity is less than demanded user sessions, starting session host"
                # Running out of capacity, we need to start more VMs if there are any 
                foreach ($SessionHost in $AllSessionHosts.Name) {
                    if ($HostPoolUserSessions.Count -ge $AvailableSessionCapacity) {
                        $VMName = $SessionHost.Split("/")[1].Split(".")[0]
                        $login = Login-ToAzureForSessionHosts
                        $RoleInstance = Get-AzVM -Status | Where-Object { $_.Name.Contains($VMName) }

                        if ($SessionHost.ToLower().Contains($RoleInstance.Name.ToLower())) {
                            # Check if the Azure VM is running and if the session host is healthy
                            $login = Login-ToAzureForWorkspace -WVDConnection $WVDConnection
                            $SessionHostInfo = Get-AzWvdSessionHost -Name $SessionHost.Split("/")[1] -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostPoolName -SubscriptionId $WVDConnection.SubscriptionId
                            $login = Login-ToAzureForSessionHosts -Connection $Connection
                            if ($RoleInstance.PowerState -ne "VM running" -and $SessionHostInfo.UpdateState -eq "Succeeded") {
                                # Check if the session host is allowing new connections
                                if($SessionHostInfo.AllowNewSession = $true)
                                {
                                    # Start the Az VM
                                    $startedVms += Start-Job -InitializationScript $functions -ScriptBlock $scriptBlockPowerOn -ArgumentList @($SessionHostInfo.Name,$HostpoolName,$HostPoolResourceGroupName,$Connection,$WVDConnection) -Name $VMName
                                }                            
                                # Calculate available capacity of sessions
                                $login = Login-ToAzureForSessionHosts -Connection $Connection
                                $RoleSize = Get-AzVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
                                $AvailableSessionCapacity = $AvailableSessionCapacity + $RoleSize.NumberOfCores * $SessionThresholdPerCPU
                                [int]$NumberOfRunningHost = [int]$NumberOfRunningHost + 1
                                [int]$TotalRunningCores = [int]$TotalRunningCores + $RoleSize.NumberOfCores
                                Write-Output "New available session capacity is: $AvailableSessionCapacity"
                                if ($AvailableSessionCapacity -gt $HostPoolUserSessions.Count) {
                                    break
                                }
                            }
                            #Break # break out of the inner foreach loop once a match is found and checked
                        }
                    }
                }
                if($startedVms.Count -gt 0)
                {
                    Get-DataFromJobs -jobs $startedVms
                    Write-Output "Jobs Finished"
                }
                else {
                    Write-Output "VMs Already Running"
                }
            }
            else 
            {
                Write-Output "Powering Down Hosts with no sessions"                       
                # Breadth first session hosts shutdown in off peak hours
                if ($AvailableSessionCapacity -gt $HostPoolUserSessions.Count -and $NumberOfRunningHost -gt $MinimumNumberOfRDSH) {
                    $stoppedVms = @()
                    foreach ($SessionHost in $AllSessionHosts) {
                        #Check the status of the session host
                        if ($SessionHost.Status -ne "NoHeartbeat") {
                            Write-Output "SessionHost $($SessionHost.Name) being checked for Powerdown"
                            if ($NumberOfRunningHost -gt $MinimumNumberOfRDSH) {
                                $SessionHostName = $SessionHost.Name
                                $VMName = $SessionHostName.Split("/")[1].Split(".")[0]
                                $login = Login-ToAzureForSessionHosts -Connection $Connection
                                $RoleInstance = Get-AzVM -Status | Where-Object { $_.Name.Contains($VMName) }
                                if($RoleInstance -ne $null)
                                {
                                    Write-Output "$($RoleInstance.Name) PowerState is $($RoleInstance.PowerState)"
                                    if ($SessionHost.Session -eq 0 -and $RoleInstance.PowerState -eq "VM running") {
                                        # Shutdown the Azure VM, which session host have 0 sessions
                                        Write-Output "Stopping Azure VM: $VMName and waiting for it to complete ..."
                                        $stoppedVms += Start-Job -InitializationScript $functions -ScriptBlock $scriptBlockPowerDown -ArgumentList @($SessionHost.Name,$Connection) -Name $VMName
                                        $login = Login-ToAzureForSessionHosts -Connection $Connection
                                        $RoleSize = Get-AzVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
                                        $AvailableSessionCapacity = $AvailableSessionCapacity - $RoleSize.NumberOfCores * $SessionThresholdPerCPU
                                        [int]$NumberOfRunningHost = [int]$NumberOfRunningHost - 1
                                        [int]$TotalRunningCores = [int]$TotalRunningCores - $RoleSize.NumberOfCores
                                        Write-Output "New available session capacity is: $AvailableSessionCapacity"
                                    }
                                    if ($NumberOfRunningHost -eq $MinimumNumberOfRDSH) {
                                        break
                                    }                                    
                                }
                            } 
                        }                      
                    }
                    if($stoppedVms.Count -gt 0)
                    {
                        Get-DataFromJobs -jobs $stoppedVms
                        Write-Output "Jobs Finished"
                    }
                    else {
                        Write-Output "No VMs to Stop"
                    }
                }
            }
        }           
    }
    else {
        Write-Output "It is Off-peak hours"
        Write-Output "Starting to scale down WVD session hosts ..."
        Write-Output "Processing hostpool $($HostpoolName)"
        $login = Login-ToAzureForWorkspace -WVDConnection $WVDConnection
        # Check the number of running session hosts
        [int]$NumberOfRunningHost = 0
        # Total number of running cores
        [int]$TotalRunningCores = 0
        #Initialize variable for to skip the session host which is in maintenance.
        $SkipSessionhosts = 0
        $SkipSessionhosts = @()
        $ListOfSessionHosts = Get-AzWvdSessionHost -HostPoolName $HostpoolName -ResourceGroupName $HostPoolResourceGroupName -SubscriptionId $WVDConnection.SubscriptionId
        $login = Login-ToAzureForSessionHosts -Connection $Connection
        foreach ($SessionHost in $ListOfSessionHosts) {
            $SessionHostName = $SessionHost.Name
            $VMName = $SessionHostName.Split("/")[1].Split(".")[0]
            $RoleInstance = Get-AzVM -Status | Where-Object { $_.Name.Contains($VMName) }
            # Check the session host is in maintenance
            if ($RoleInstance.Tags.Keys -contains $MaintenanceTagName) {
                Write-Output "Session host is in maintenance: $VMName, so script will skip this VM"
                $SkipSessionhosts += $SessionHost
                continue
            }
            # Maintenance VMs skipped and stored into a variable
            $AllSessionHosts = $ListOfSessionHosts | Where-Object { $SkipSessionhosts -notcontains $_ } | Sort-Object Session
            if ($SessionHostName.ToLower().Contains($RoleInstance.Name.ToLower())) {
                # Check if the Azure VM is running
                if ($RoleInstance.PowerState -eq "VM running") {
                    Write-Output "Checking session host: $($SessionHost.Name.Split("/")[1])  of sessions:$($SessionHost.Session) and status:$($SessionHost.Status)"
                    [int]$NumberOfRunningHost = [int]$NumberOfRunningHost + 1
                    # Calculate available capacity of sessions  
                    $RoleSize = Get-AzVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
                    [int]$TotalRunningCores = [int]$TotalRunningCores + $RoleSize.NumberOfCores
                }
            }
        }
        # Defined minimum no of rdsh value from webhook data
        [int]$DefinedMinimumNumberOfRDSH = [int]$MinimumNumberOfRDSH
        ## Check and Collecting dynamically stored MinimumNoOfRDSH value																 
        $OffPeakUsageMinimumNoOfRDSH = $MinimumNumberOfRDSH
        if ($OffPeakUsageMinimumNoOfRDSH) {
            [int]$MinimumNumberOfRDSH = $OffPeakUsageMinimumNoOfRDSH
            if ($MinimumNumberOfRDSH -lt $DefinedMinimumNumberOfRDSH) {
                Write-Output "Don't enter the value of '$HostpoolName-OffPeakUsage-MinimumNoOfRDSH' manually, which is dynamically stored value by script. You have entered manually, so script will stop now."
                Exit
            }
        }

        # Breadth first session hosts shutdown in off peak hours
        if ($NumberOfRunningHost -gt $MinimumNumberOfRDSH) {
            $stoppedVms = @()
            foreach ($SessionHost in $AllSessionHosts) {
                #Check the status of the session host
                if ($SessionHost.Status -ne "NoHeartbeat") {
                    if ($NumberOfRunningHost -gt $MinimumNumberOfRDSH) {
                        $SessionHostName = $SessionHost.Name.Split("/")[1]
                        $VMName = $SessionHostName.Split(".")[0]
                        if ($SessionHost.Session -eq 0) {
                            # Shutdown the Azure VM, which session host have 0 sessions
                            Write-Output "Stopping Azure VM: $VMName and waiting for it to complete ..."
                            $stoppedVms += Start-Job -InitializationScript $functions -ScriptBlock $scriptBlockPowerDown -ArgumentList @($SessionHost.Name,$Connection) -Name $VMName
                        }
                        else {
                            $login = Login-ToAzureForWorkspace -WVDConnection $WVDConnection
                            # Ensure the running Azure VM is set as drain mode
                            try {                                
                                $KeepDrianMode = Update-AzWvdSessionHost -Name $SessionHostName -HostPoolName $HostpoolName -ResourceGroupName $HostPoolResourceGroupName -SubscriptionId $WVDConnection.SubscriptionId -AllowNewSession:$false
                            }
                            catch {
                                Write-Output "Unable to set it to allow connections on session host: $SessionHostName with error: $($_.exception.message)"
                                exit
                            }
                            # Notify user to log off session
                            # Get the user sessions in the hostpool
                            try {
                                $HostPoolUserSessions = Get-AzWvdUserSession -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostpoolName -SubscriptionId $WVDConnection.SubscriptionId
                            }
                            catch {
                                Write-Output "Failed to retrieve user sessions in hostpool: $($Name) with error: $($_.exception.message)"
                                exit
                            }
                            $HostUserSessionCount = ($HostPoolUserSessions | Where-Object -FilterScript { $_.Name -contains $SessionHostName }).Count
                            Write-Output "Counting the current sessions on the host $SessionHostName :$HostUserSessionCount"
                            $ExistingSession = 0
                            foreach ($session in $HostPoolUserSessions) {
                                if ($session.Id -contains $SessionHostName -and $session.SessionState -eq "Active") {
                                    if ($LimitSecondsToForceLogOffUser -ne 0) {
                                        # Send notification
                                        try {
                                            Send-AzWvdUserSessionMessage -SessionHostName $SessionHostName -HostPoolName $HostpoolName -ResourceGroupName $HostPoolResourceGroupName -MessageTitle $LogOffMessageTitle -MessageBody $LogOffMessageBody -UserSessionId $session.Id.Split("/")[-1] -SubscriptionId $WVDConnection.SubscriptionId
                                        }
                                        catch {
                                            Write-Output "Failed to send message to user with error: $($_.exception.message)"
                                            exit
                                        }
                                        Write-Output "Script was sent a log off message to user: $($Session.UserPrincipalName | Out-String)"
                                    }
                                }
                                $ExistingSession = $ExistingSession + 1
                            }
                            # Wait for n seconds to log off user
                            if($ExistingSession -ne 0)
                            {                                
                                Start-Sleep -Seconds $LimitSecondsToForceLogOffUser
                            }

                            if ($LimitSecondsToForceLogOffUser -ne 0 -and $ExistingSession -gt 0) {
                                # Force users to log off
                                Write-Output "Force users to log off ..."
                                foreach ($Session in $HostPoolUserSessions) {
                                    if ($Session.Id -contains $SessionHostName) {
                                        #Log off user
                                        try {
                                            Disconnect-AzWvdUserSession -HostPoolName $HostpoolName -ResourceGroupName $HostPoolResourceGroupName -Id $Session.Id.Split("/")[-1] -SessionHostName $SessionHostName
                                            $ExistingSession = $ExistingSession - 1
                                        }
                                        catch {
                                            Write-Output "Failed to log off user with error: $($_.exception.message)"
                                            exit
                                        }
                                        Write-Output "Forcibly logged off the user: $($Session.UserPrincipalName)"
                                    }
                                }
                            }
                            # Check the session count before shutting down the VM
                            if ($ExistingSession -eq 0) {
                                # Shutdown the Azure VM
                                Write-Output "Stopping Azure VM: $VMName and waiting for it to complete ..."
                                $stoppedVms += Start-Job -InitializationScript $functions -ScriptBlock $scriptBlockPowerDown -ArgumentList @($SessionHost.Name,$Connection) -Name $VMName
                            }
                        }
                        #wait for the VM to stop
                        $RoleSize = Get-AzVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
                        #decrement number of running session host
                        [int]$NumberOfRunningHost = [int]$NumberOfRunningHost - 1
                        [int]$TotalRunningCores = [int]$TotalRunningCores - $RoleSize.NumberOfCores
                    }
                }
            }
            
            Get-DataFromJobs -jobs $stoppedVms
        }
        $OffPeakUsageMinimumNoOfRDSH = $MinimumNumberOfRDSH
        if ($OffPeakUsageMinimumNoOfRDSH) {
            [int]$MinimumNumberOfRDSH = $OffPeakUsageMinimumNoOfRDSH
            $NoConnectionsofhost = 0
            if ($NumberOfRunningHost -le $MinimumNumberOfRDSH) {
                foreach ($SessionHost in $AllSessionHosts) {
                    if ($SessionHost.Status -eq "Available" -and $SessionHost.Sessions -eq 0) {
                        $NoConnectionsofhost = $NoConnectionsofhost + 1
                    }
                }
                $NoConnectionsofhost = $NoConnectionsofhost - $DefinedMinimumNumberOfRDSH
                if ($NoConnectionsofhost -gt $DefinedMinimumNumberOfRDSH) {
                    [int]$MinimumNumberOfRDSH = [int]$MinimumNumberOfRDSH - $NoConnectionsofhost
                }
            }
        }
        $HostpoolMaxSessionLimit = $HostpoolInfo.MaxSessionLimit
        $login = Login-ToAzureForWorkspace -WVDConnection $WVDConnection
        $HostpoolSessionCount = (Get-AzWvdUserSession -HostPoolName $HostpoolName -ResourceGroupName $HostPoolResourceGroupName -SubscriptionId $WVDConnection.SubscriptionId).Count
        if ($HostpoolSessionCount -ne 0) {
            # Calculate the how many sessions will allow in minimum number of RDSH VMs in off peak hours and calculate TotalAllowSessions Scale Factor
            $TotalAllowSessionsInOffPeak = [int]$MinimumNumberOfRDSH * $HostpoolMaxSessionLimit
            $SessionsScaleFactor = $TotalAllowSessionsInOffPeak * 0.90
            $ScaleFactor = [math]::Floor($SessionsScaleFactor)

            if ($HostpoolSessionCount -ge $ScaleFactor) {
                $ListOfSessionHosts = Get-AzWvdSessionHost -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostpoolName -SubscriptionId $WVDConnection.SubscriptionId | Where-Object { $_.Status -eq "NoHeartbeat" }
                #$AllSessionHosts = Compare-Object $ListOfSessionHosts $SkipSessionhosts | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject }
                $AllSessionHosts = $ListOfSessionHosts | Where-Object { $SkipSessionhosts -notcontains $_ }
                $startedVms = @()
                foreach ($SessionHost in $AllSessionHosts) {
                    # Check the session host status and if the session host is healthy before starting the host
                    if ($SessionHost.UpdateState -eq "Succeeded") {
                        Write-Output "Existing sessionhost sessions value reached near by hostpool maximumsession limit need to start the session host"
                        $SessionHostName = $SessionHost.Name.Split("/")[1]
                        $VMName = $SessionHostName.Split(".")[0]
                        # Start the Az VM
                        Write-Output "Starting Azure VM: $VMName and waiting for it to complete ..."
                        $startedVms += Start-Job -InitializationScript $functions -ScriptBlock $scriptBlockPowerOn -ArgumentList @($SessionHost.Name,$HostpoolName,$HostPoolResourceGroupName,$Connection,$WVDConnection) -Name $VMName
                        # Increment the number of running session host
                        [int]$NumberOfRunningHost = [int]$NumberOfRunningHost + 1
                        # Increment the number of minimumnumberofrdsh
                        [int]$MinimumNumberOfRDSH = [int]$MinimumNumberOfRDSH + 1
                        $OffPeakUsageMinimumNoOfRDSH = $MinimumNumberOfRDSH
                        if ($OffPeakUsageMinimumNoOfRDSH -eq $null) {
                            New-AzAutomationVariable -Name "$HostpoolName-OffPeakUsage-MinimumNoOfRDSH" -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName -Encrypted $false -Value $MinimumNumberOfRDSH -Description "Dynamically generated minimumnumber of RDSH value"
                        }
                        else {
                            Set-AzAutomationVariable -Name "$HostpoolName-OffPeakUsage-MinimumNoOfRDSH" -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName -Encrypted $false -Value $MinimumNumberOfRDSH
                        }
                        # Calculate available capacity of sessions
                        $RoleSize = Get-AzVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
                        $AvailableSessionCapacity = $TotalAllowSessions + $HostpoolInfo.MaxSessionLimit
                        [int]$TotalRunningCores = [int]$TotalRunningCores + $RoleSize.NumberOfCores
                        Write-Output "New available session capacity is: $AvailableSessionCapacity"
                        break
                    }
                }
                Get-DataFromJobs -jobs $startedVms
            }

        }
    }

    Write-Output "HostpoolName: $HostpoolName, TotalRunningCores: $TotalRunningCores NumberOfRunningHosts: $NumberOfRunningHost"
    Write-Output "End WVD tenant scale optimization."
