param (
    [string]$uncPath
)

Invoke-WebRequest -Uri https://aka.ms/fslogix_download -Method Get -OutFile fslogix.zip;
Expand-Archive -Path fslogix.zip -Force;
Set-Location .\fslogix\x64\Release;
Start-Process -FilePath .\FSLogixAppsSetup.exe -ArgumentList "/install /quiet" -Verb runas -Wait;
New-Item -Path HKLM:\SOFTWARE\FSLogix\Profiles
New-ItemProperty -Path HKLM:\SOFTWARE\FSLogix\Profiles -Name Enabled -PropertyType DWord -Value 1
New-ItemProperty -Path HKLM:\SOFTWARE\FSLogix\Profiles -Name DeleteLocalProfileWhenVHDShouldApply -PropertyType DWord -Value 1
New-ItemProperty -Path HKLM:\SOFTWARE\FSLogix\Profiles -Name VHDLocations -PropertyType MultiString -Value @($uncPath)