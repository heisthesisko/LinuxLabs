# Check if the script is running with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as an administrator."
    Exit 1
}

# Define variables
$folderPath = "C:\\LinuxLab"
$logFilePath = "C:\\LinuxLab\\LinuxLabBuilder.txt"
$VHDPath = "C:\\LinuxLab\\VMFiles\\"
$isoFolder = "C:\\LinuxLab\\"

function Write-Log {
    param (
        [string]$EventTimeStamp,
        [string]$Comment
    )
    
    # Get the current date and time
    $currentDateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fffffff"
    
    # Format the log entry
    $logEntry = "$currentDateTime - $Comment"
    
    # Write the log entry to the log file
    Add-Content -Path $EventTimeStamp -Value $logEntry
    
    # Ensure the log file is updated immediately
    [System.IO.File]::WriteAllText($EventTimeStamp, [System.IO.File]::ReadAllText($EventTimeStamp) + "`r`n")
}

# Verify the existence of the LinuxLab folder and the LinuxLabBuilder.txt file

if (-Not (Test-Path $folderPath)) {
    Write-Host "LinuxLab folder does not exist. Creating the folder..."
    New-Item -Path $folderPath -ItemType Directory
}

if (-Not (Test-Path $logFilePath)) {
    Write-Host "LinuxLabBuilder.txt file does not exist. Creating the file..."
    New-Item -Path $logFilePath -ItemType File
}

if (-Not (Test-Path $VHDPath)) {    # Check if the VMFiles folder exists
    Write-Host "VMFiles folder does not exist. Creating the folder..."
    New-Item -Path $VHDPath -ItemType Directory    <# Action to perform if the condition is true #>
}

# Example usage
$Comment = "Script started"
Write-Log -EventTimeStamp $logFilePath -Comment $Comment

# Define the Hyper-V feature name
$featureName = "Microsoft-Hyper-V-All"

# Function to check if Hyper-V is installed
function Confirm-HyperV {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName
    return $feature.State -eq "Enabled"
}

# Function to install Hyper-V
function Install-HyperV {
    Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart
    Write-Host "Hyper-V has been installed. Please restart your computer to complete the installation."
    $Comment= "Hyper-V has been installed. Restart will be needed"
    Write-Log -EventTimeStamp $logFilePath -Comment $Comment
}

# Check if Hyper-V is installed
if (Confirm-HyperV) {
    Write-Host "Hyper-V is already installed."
    $Comment= "Hyper-V is already installed"
    Write-Log -EventTimeStamp $logFilePath -Comment $Comment
} else {
    Write-Host "Hyper-V is not installed. Installing now..."
    $Comment= "Hyper-V is not installed. Installing now"
    Write-Log -EventTimeStamp $logFilePath -Comment $Comment
    Install-HyperV
}




# Function to check if ISO exists
function Confirm-ISOExists {
    param (
        [string]$folder,
        [string]$fileName
    )

    $filePath = Join-Path -Path $folder -ChildPath $fileName
    return Test-Path -Path $filePath
}

# Function to start BITS job
function Start-BITSJob {
    param (
        [string]$jobName,
        [string]$sourceUrl,
        [string]$destinationPath
    )

    Write-Output "Starting BITS job: $jobName"
    Start-BitsTransfer -Source $sourceUrl -Destination $destinationPath -DisplayName $jobName -Asynchronous
   
}

# Function to create a virtual machine
function Create-VM {
    param (
        [string]$vmName,
        [string]$isoPath
    )

    Write-Output "Creating VM: $vmName"

    New-VM -Name $vmName -MemoryStartupBytes 2GB -Generation 1 -NewVHDPath "C:\LinuxLab\VMFiles\$vmName.vhdx" -NewVHDSizeBytes 60GB
    Set-VMProcessor -VMName $vmName -Count 2
    Add-VMDvdDrive -VMName $vmName -Path $isoPath
    Set-VMDvdDrive -VMName $vmName -ControllerNumber 0 -ControllerLocation 1
    Start-VM -Name $vmName

    Write-Output "VM $vmName created and started."
}

# BITS job details
$bitsJobs = @(
    @{ JobName = "Job1"; SourceUrl = "https://mirrors.ocf.berkeley.edu/centos-stream/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-dvd1.iso"; DestinationPath = "C:\\LinuxLab\\CentOS-Stream-9.iso" },
    @{ JobName = "Job2"; SourceUrl = "https://releases.ubuntu.com/18.04/ubuntu-18.04.6-live-server-amd64.iso"; DestinationPath = "C:\\LinuxLab\\Ubuntu-18.iso" },
    @{ JobName = "Job3"; SourceUrl = "https://download.rockylinux.org/pub/rocky/10/isos/x86_64/Rocky-10-latest-x86_64-minimal.iso"; DestinationPath = "C:\\LinuxLab\\Rocky-9.iso" },
    @{ JobName = "Job4"; SourceUrl = "https://download.opensuse.org/distribution/leap/15.6/iso/openSUSE-Leap-15.6-NET-x86_64-Media.iso"; DestinationPath = "C:\\LinuxLab\\Suse-15.iso" },
    @{ JobName = "Job5"; SourceUrl = "https://repo.almalinux.org/almalinux/9/isos/aarch64/AlmaLinux-9-latest-aarch64-minimal.iso"; DestinationPath = "C:\\LinuxLab\\AlmaLinux-9.iso" },
    @{ JobName = "Job6"; SourceUrl = "https://download.fedoraproject.org/pub/fedora/linux/releases/42/Server/x86_64/iso/Fedora-Server-dvd-x86_64-42-1.1.iso"; DestinationPath = "C:\\LinuxLab\\Fedora-40.iso" },
    @{ JobName = "Job7"; SourceUrl = "https://vault.centos.org/7.7.1908/isos/x86_64/CentOS-7-x86_64-Everything-1908.iso"; DestinationPath = "C:\\LinuxLab\\CentOS-7-EOL.iso" }
    

    
    # Add more jobs as needed
)

# Main routine
foreach ($bitsJob in $bitsJobs) {
    $jobName = $bitsJob.JobName
    $sourceUrl = $bitsJob.SourceUrl
    $destinationPath = $bitsJob.DestinationPath
    $isoFileName = [System.IO.Path]::GetFileName($destinationPath)
    $vmName = "LinuxLabVM-" + [System.IO.Path]::GetFileNameWithoutExtension($isoFileName)
    $retryCount = 0
    $maxRetries = 3
    $isoExists = $false

    while (-not $isoExists -and $retryCount -lt $maxRetries) {
        # Start the BITS job
        Start-BITSJob -jobName $jobName -sourceUrl $sourceUrl -destinationPath $destinationPath
        $Comment = "Starting $sourceUrl download"
        Write-Log -EventTimeStamp $logFilePath -Comment $Comment

                
        # Wait for the BITS job to complete
        $job = Get-BitsTransfer -Name $jobName
        while ($job.JobState -ne 'Transferred' -and $job.JobState -ne 'Suspended' -and $job.JobState -ne 'Error') {
            Start-Sleep -Seconds 5
            $job = Get-BitsTransfer -Name $jobName
        }

        if ($job.JobState -eq 'Transferred') {
            Complete-BitsTransfer -BitsJob $job
        } elseif ($job.JobState -eq 'Error') {
            Write-Host "BITS job failed: $($job | Select-Object -ExpandProperty ErrorDescription)"
            Write-Log -EventTimeStamp $logFilePath -Comment "BITS job failed: $($job | Select-Object -ExpandProperty ErrorDescription)"
        }

        # Check if the ISO exists
        $isoExists = Confirm-ISOExists -folder $isoFolder -fileName $isoFileName
        if ($isoExists) {
            Write-Output "ISO exists: $isoFileName"
        } else {
            $retryCount++
            Write-Output "ISO not found, repeating BITS job... Attempt $retryCount of $maxRetries"
            Write-Log -EventTimeStamp $logFilePath -Comment "ISO not found: $isoFileName, Attempt $retryCount of $maxRetries"
        }
    }

    if (-not $isoExists) {
        Write-Host "Failed to download $isoFileName after $maxRetries attempts. Please download manually."
        Write-Log -EventTimeStamp $logFilePath -Comment "Failed to download $isoFileName after $maxRetries attempts. Please download manually."
        Add-Content -Path $failedLogFilePath -Value "$isoFileName`n"
    }

        # Create a virtual machine using the downloaded ISO
        Create-VM -vmName $vmName -isoPath $destinationPath
        $Comment = $vmName + " created"
        Write-Log -EventTimeStamp $logFilePath -Comment $Comment
}

# VM creation complete
Write-Output "All BITS jobs completed, ISOs validated, and VMs created."
$Comment = "All BITS jobs completed, ISOs validated, and VMs created."
Write-Log -EventTimeStamp $logFilePath -Comment $Comment

#Post installation setup of VM's

# CentOS 7 EOL VM setup
#$vmName = "LinuxLabVM-CentOS-7-EOL"
#$ksURL = "https://github.com/heisthesisko/LinuxLabs/blob/main/Hyper-V%20Based%20Labs/PostConfigurations/ks.cfg"

# Connect to VM console to send keystrokes (requires vmconnect.exe)
#$vmConnectPath = "C:\Windows\System32\vmconnect.exe"
#$vmHost = "localhost"

# Start VMConnect in the background to send keystrokes
#Start-Process $vmConnectPath -ArgumentList "$vmHost", "$vmName" -NoNewWindow

# Sleep to allow VMConnect to establish connection
#Start-Sleep -Seconds 10

# Send keystrokes to boot with kickstart file
#$wsh = New-Object -ComObject WScript.Shell
#$wsh.AppActivate($vmName)
##Start-Sleep -Seconds 1
#$wsh.SendKeys('^]')
#Start-Sleep -Seconds 1
#$wsh.SendKeys('linux ks=' + $ksURL + '{ENTER}')

# The VM will now start the installation using the kickstart file
# AlmaLinux 9 VM setup
#$vmName = "LinuxLabVM-AlmaLinux-9"

# Fedora 40 VM setup
#$vmName = "LinuxLabVM-Fedora-40"

# Debian 12 VM setup
#$vmName = "LinuxLabVM-Debian-12"

# Suse 15 VM setup
#$vmName = "LinuxLabVM-Suse-15"

# Rocky 9 VM setup
#$vmName = "LinuxLabVM-Rocky-9"

# Ubuntu 24 VM setup
#$vmName = "LinuxLabVM-Ubuntu-24"

# CentOS Stream 9 VM setup
#$vmName = "LinuxLabVM-CentOS-Stream-9"


# Script completion message
$Comment = "Script has completed"
Write-Log -EventTimeStamp $logFilePath -Comment $Comment
