#script assumes machine running the script is able to communicate with the IP address of the VDI machines, the vdi host machines are built on, and the RDSH manager server that machines will be registered with

$script:TargetCollectionName = "Collection 1"
$script:NotificationTitle = "Urgent Message from IT Support"
$script:VMPrefix = "VDI-" #This script assumes VDI machines are named uniformly with a prefix, here, and a unique four digit number after
$script:OrgUnitPath = 'OU=Office1,OU=Computers,dc=domain,dc=com' #path in domain where computers objects will be placed when joined
$script:DomainToJoin = "domain.com" #used when joining machines after building
$script:RDSHPoolManager = "RDSHost.domain.com" #fqdn of the RDSH server responsible for the pool you're managing, likely the gateway
$script:DefaultVDIHost = "Default" #default hyper-v host name to use when none is given
$script:ChunkSize = 5 #when breaking large jobs into smaller chunks, this is how many to do at a time
$script:PostBuildPause = 300 #amount of time to pause to give all of the newly built machines time to finish starting up, adjust as necessary
#300 - 5 minutes (good for batches of 5)
#150 - 2.5 minutes (good for batches of 2)

#Parameters for machine creation
$script:VMPath = "G:\VDI Machines" #path where new VDI Machine files will be placed
$script:ProcessorCount = 15
$script:StartupMemory = 6GB
$script:MinMemory = 1GB
$script:MaxMemory = 16GB
$script:StartAction = "StartIfRunning"
$script:StopAction = "Save"
$script:AutoStartDelay = 10
$script:SysVHDPath = "G:\Golden Images\20220210 - VDI-Base\Virtual Hard Disks\DiffDisk.vhdx" #path to the base diff disk
$script:VMSwitchName = "VMSwitch1"
$script:VlanId = 0
$script:VMQ = $False
$script:IPSecOffload = $True
$script:SRIOV = $False
$script:MacSpoofing = $False
$script:DHCPGuard = $False
$script:RouterGuard = $False
$script:NicTeaming = $False

function DivideList {
    param(
        [object[]]$list,     # The input list to be divided
        [int]$chunkSize      # The size of each chunk
    )

    # Iterate over the list, starting from index 0 and incrementing by chunkSize
    for ($i = 0; $i -lt $list.Count; $i += $chunkSize) {
        # Select a chunk of elements from the list using the Skip and First parameters
        $chunk = $list | Select-Object -Skip $i -First $chunkSize

        # Output the chunk as an array
        , $chunk
    }
}

Function GetKeyPress([string]$regexPattern='[ynq]', [string]$message=$null, [int]$timeOutSeconds=0) {
    $key = $null
    $Host.UI.RawUI.FlushInputBuffer() 

    # Display the message in yellow text on a dark green background
    if (![string]::IsNullOrEmpty($message))
    {
        Write-Host -NoNewLine $message -Foregroundcolor Yellow -Backgroundcolor DarkGreen
    }

    $counter = $timeOutSeconds * 1000 / 250

    # Loop until a valid key is pressed or the timeout is reached
    while ($key -eq $null -and ($timeOutSeconds -eq 0 -or $counter-- -gt 0))
    {
        if (($timeOutSeconds -eq 0) -or $Host.UI.RawUI.KeyAvailable)
        {                       
            # Read a key without displaying it and check if it matches the regex pattern
            $key_ = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown,IncludeKeyUp")
            if ($key_.KeyDown -and $key_.Character -match $regexPattern)
            {
                $key = $key_  # Store the matched key
            }
        }
        else
        {
            Start-Sleep -m 250  # Wait for 250 milliseconds
        }
    }                       

    # Display the pressed key if it exists
    if (-not ($key -eq $null))
    {
        Write-Host -NoNewLine "$($key.Character)" 
    }

    if (![string]::IsNullOrEmpty($message))
    {
        Write-Host ""  # Print a newline after the message
    }       

    return $(if ($key -eq $null) {$null} else {$key.Character})
}

function Manage_Existing_Machines () {
	[CmdletBinding()]
	param([string]$Mode)

	if ($Mode -eq "RemoveVDIAssignments-ThatAreLoggedOff") {
		# Remove VDI Assignments where there are NO active OR disconnected connections
		Write-Host "`nRemoving VDI Machine Assignments where there are NO active OR disconnected connections" -ForegroundColor Yellow -BackgroundColor DarkGreen

		# Get a list of ALL assigned desktops
		$DesktopAssignments = Get-RDPersonalVirtualDesktopAssignment -CollectionName $script:TargetCollectionName

		# Get a list of ALL sessions active or disconnected
		$RDUserSessions = Get-RDUserSession -CollectionName $script:TargetCollectionName

		# Create a list of assigned desktops with no active or disconnected session
		$DesktopAssignmentsToRemove = $DesktopAssignments | Where-Object { $RDUserSessions.ServerName -notcontains $_.VirtualDesktopName }

		# Remove any assignments that are not currently being used
		foreach ($Session in $DesktopAssignmentsToRemove) {
			$Session
			Remove-RDPersonalVirtualDesktopAssignment -CollectionName $script:TargetCollectionName -VirtualDesktopName $Session.VirtualDesktopName -Force
		}

		break
	}

		
	while ($Ready -ne "TRUE") {
		# Notify the logged in users?
		$NotifyUsers = Read-Host "`nNotify Users? [y/n]"
		if ($NotifyUsers -eq 'n') {
			$NotifyUsers = $False
			$Ready = "TRUE"
		}
		if ($NotifyUsers -eq 'y') {
			$NotifyUsers = $True
			$Ready = "TRUE"
			$NotificationBody = Read-Host "`nPlease enter the message body of the notification you wish to send."

			# Delay the Notification?
			while ($Ready2 -ne "TRUE") {
				$NotificationDelay = Read-Host "`nDelay (In Minutes) for the user notification? Press Enter for no delay."
				if ([string]::IsNullOrWhiteSpace($NotificationDelay)) {
					$NotificationDelay = 0
				}
				$NotificationDelay = [int]$NotificationDelay * 60
				if ([int]$NotificationDelay -Or $NotificationDelay -eq 0) {
					$Ready2 = "TRUE"
					Write-Host "`nNotification will be delayed by $NotificationDelay Seconds" -ForegroundColor Yellow -BackgroundColor DarkGreen
				} else {
					Write-Host "No delay or invalid entry detected"
				}
			}
			$Ready2 = "FALSE" # Resetting for next use
		}
	}

	$Ready = "FALSE" # Resetting for next use

	if ($Mode -ne "NotifyOnly") {
		# Setup the action delay
		while ($Ready -ne "TRUE") {
			$DelayAction = Read-Host "`nDelay Action? [y/n]"
			if ($DelayAction -eq 'n') {
				$DelayAction = $False
				$Ready = "TRUE"
				$ActionDelay = 0
			}
			if ($DelayAction -eq 'y') {
				$DelayAction = $True
				$Ready = "TRUE"
				$ActionDelay = Read-Host -Prompt "`nDelay (In Minutes) for the action?  Press Enter for no delay."
				
				# Check if the entered delay is empty or whitespace
				if ([string]::IsNullOrWhiteSpace($ActionDelay)) {
					$ActionDelay = 0
				}
				
				# Convert delay from minutes to seconds
				$ActionDelay = [int]$ActionDelay * 60
				
				# Notify the user about the action delay
				Write-Host "`nAction will be delayed by $ActionDelay Seconds, timer starting after user notification." -ForegroundColor Yellow -BackgroundColor DarkGreen
			}
		}
	}

	if ($Mode) {
		# Select which VDI Machines
		[int]$NumberofVMs = Read-Host -Prompt "`nHow many VM's do you want to select?"
		if ([string]::IsNullOrWhiteSpace($NumberofVMs)) {
			Exit
		}

		$VMStartingNumber = Read-Host -Prompt "Starting Number for VM's?  IE 5 or 1003 or 5001.  Script will count up from here selecting the number of VM's specified in the previous prompt."
		if ([string]::IsNullOrWhiteSpace($VMStartingNumber)) {
			Exit
		}

		$VDIHost = Read-Host -Prompt "Which VM Host? DNS or FQDN of the Target Hyper-V Host"
		if ([string]::IsNullOrWhiteSpace($VDIHost)) {
			Break
		}

		$CollectionName = $script:TargetCollectionName
		$VMPrefix = $script:VMPrefix

		[int]$VMEndingNumber = ([int]$VMStartingNumber) + (($NumberofVMs) - 1)
		$VMNumberArray = ([int]$VMStartingNumber..$VMEndingNumber)
		$VMNumberArray = $VMNumberArray | ForEach-Object {"{0:D4}" -f $_}
		$VMNameArray = $VMNumberArray | ForEach-Object {"$VMPrefix$_"}

		# Output selected VM names
		Write-Host "`nSelecting $NumberofVMs VMs on $VDIHost, here is a list of the selected names:" -ForegroundColor Yellow -BackgroundColor DarkGreen
		Write-Host $VMNameArray -ForegroundColor Yellow -BackgroundColor DarkGreen

		# Cleanup any previous jobs
		Remove-Job -State Completed
		Remove-Job -State Failed
	}

	if($Mode -eq "ChangeHardware"){ 
		#Query for hardware change info
		$StartupBytes = Read-Host -Prompt "Startup Memory Amount in GB?  IE 1 or 4."
		if([string]::IsNullOrWhiteSpace($StartupBytes)){Exit}
		$Minimumbytes = Read-Host -Prompt "Dynamic memory minimum in GB?  IE 1 or 4.  Must be same or less than startup amount."
		if([string]::IsNullOrWhiteSpace($Minimumbytes)){Exit}
		$MaximumBytes = Read-Host -Prompt "Dynamic memory maximum in GB?  IE 1 or 4.  Must be same or larger than startup amount."
		if([string]::IsNullOrWhiteSpace($MaximumBytes)){Exit}
		$ProcessorCount = Read-Host -Prompt "Number of processing cores?  IE 4."
		if([string]::IsNullOrWhiteSpace($ProcessorCount)){Exit}
	}

	Write-Warning "Are you sure you want to continue?" -WarningAction Inquire

	if ($NotifyUsers) {
		# Notify Users

		# Check if there is a notification delay and pause if necessary
		if ($NotificationDelay -gt 0) {
			Write-Host "`nPausing for Notification Delay of $NotificationDelay Seconds`n" -ForegroundColor Yellow -BackgroundColor DarkGreen
			Start-Sleep -Seconds $NotificationDelay
		}

		# Get the list of user sessions for the target collection
		$SessionList = Get-RDUserSession -CollectionName $script:TargetCollectionName

		Write-Host "`nNotifying Users" -ForegroundColor Yellow -BackgroundColor DarkGreen

		# Iterate through each VM name in the VMNameArray
		foreach ($VMName in $VMNameArray) {
			# Start a job for each VM to send the notification
			Start-Job -Name $VMName -ArgumentList $VMName, $VDIHost, $SessionList, $NotificationBody, $script:NotificationTitle -ScriptBlock {
				param($VMName, $VDIHost, $SessionList, $NotificationBody, $NotificationTitle)

				# Iterate through each user session
				foreach ($Session in $SessionList) {
					$VMTestName = $Session.ServerName

					# Check if the session's server name matches the current VM name
					if ($VMTestName -eq $VMName) {
						$Script:SelectedSession = $Session.UnifiedSessionID
						$Script:SelectedServer = $Session.HostServer
					}
				}

				# Send the notification if a selected server is found
				if ($SelectedServer) {
					Send-RDUserMessage -HostServer $SelectedServer -UnifiedSessionID $SelectedSession -MessageTitle $NotificationTitle -MessageBody $NotificationBody
				}
			}
		}

		Write-Host "Jobs Started, waiting" -ForegroundColor Yellow -BackgroundColor DarkGreen
		# Wait for all jobs to complete
		Get-Job | Wait-Job
		Write-Host "Finished Notifying Users" -ForegroundColor Yellow -BackgroundColor DarkGreen
		# Remove completed jobs
		Remove-Job -State Completed
	}

	if ($Mode -eq "Reboot") {
		if ($ActionDelay -gt 0) {
			Write-Host "`nPausing for Action Delay of $ActionDelay Seconds`n" -ForegroundColor Yellow -BackgroundColor DarkGreen
			Start-Sleep -Seconds $ActionDelay
		}
		
		Write-Host "`nRebooting VDI Machines" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		foreach ($VMName in $VMNameArray) {
			# Start a background job for each VM
			Start-Job -Name $VMName -ArgumentList $VMName, $VDIHost -ScriptBlock {
				param($VMName, $VDIHost)
				
				# Retrieve the IP address of the VM
				$script = {
					(Get-VM -Name $using:VMName | Get-VMNetworkAdapter).IpAddresses[0]
				}
				$VMIPAddress = Invoke-Command -ComputerName $VDIHost -ScriptBlock $script
				
				# Reboot the VM using Stop-VM, wait until it's off, then start it again
				$RebootScript = {
					Stop-VM -Name $using:VMName
					while ((Get-VM -Name $using:VMName).State -ne 'Off') {
						Start-Sleep -Seconds 2
					}
					Start-VM $using:VMName
				}
				Invoke-Command -ComputerName $VDIHost -ScriptBlock $RebootScript | Out-Null
				
				# Wait until the VM is reachable over RDP (port 3389)
				do {
					Start-Sleep -Seconds 3
				} until (Test-NetConnection $VMIPAddress -Port 3389 | ? {$_.TcpTestSucceeded})
			}
		}
		
		Write-Host "Jobs Started, waiting" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		# Wait for all background jobs to complete
		Get-Job | Wait-Job
		
		Write-Host "Reboot Operations Complete" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		# Remove completed and failed jobs
		Remove-Job -State Completed
		Remove-Job -State Failed
	}

	if ($Mode -eq "Shutdown") {
		# If there is an action delay, pause execution for the specified duration
		if ($ActionDelay -gt 0) {
			Write-Host "`nPausing for Action Delay of $ActionDelay Seconds`n" -ForegroundColor Yellow -BackgroundColor DarkGreen
			Start-Sleep -Seconds $ActionDelay
		}
		
		# Display a message indicating the VDI machines are being shut down
		Write-Host "`nShutting Down VDI Machines" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		# Iterate through the array of VM names
		foreach ($VMName in $VMNameArray) {
			# Start a job for each VM to run the shutdown script
			Start-Job -Name $VMName -ArgumentList $VMName, $VDIHost -ScriptBlock {
				param($VMName, $VDIHost)
				
				# Define the shutdown script to stop the VM and wait until it's turned off
				$ShutdownScript = {
					Stop-VM -Name $using:VMName
					while ((Get-VM -Name $using:VMName).State -ne 'Off') {
						Start-Sleep -Seconds 2
					}
				}
				
				# Invoke the shutdown script on the remote VDI host
				Invoke-Command -ComputerName $VDIHost -ScriptBlock $ShutdownScript | Out-Null
			}
		}
		
		Write-Host "Jobs Started, waiting" -ForegroundColor Yellow -BackgroundColor DarkGreen
		# Wait for all jobs to complete
		Get-Job | Wait-Job
		Write-Host "Shutdown Operations Complete" -ForegroundColor Yellow -BackgroundColor DarkGreen
		# Remove completed and failed jobs
		Remove-Job -State Completed
		Remove-Job -State Failed
	}

	if ($Mode -eq "Save") {
		if ($ActionDelay -gt 0) {
			Write-Host "`nPausing for Action Delay of $ActionDelay Seconds`n" -ForegroundColor Yellow -BackgroundColor DarkGreen
			sleep $ActionDelay
		}
		
		Write-Host "`nSaving VDI Machines" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		# Iterate through the array of VM names
		foreach ($VMName in $VMNameArray) {
			start-job -Name $VMName -ArgumentList $VMName, $VDIHost -ScriptBlock {
				param($VMName, $VDIHost)
				
				# Retrieve the IP address of the VM
				$script = {
					(Get-VM -Name $using:VMName | Get-VMNetworkAdapter).IpAddresses[0]
				}
				$VMIPAddress = Invoke-Command -ComputerName $VDIHost -ScriptBlock $script
				
				# Save the VM and wait until it is in the 'Saved' state
				$SaveScript = {
					Save-VM -Name $using:VMName
					while ((Get-VM -Name $using:VMName).State -ne 'Saved') {
						Start-Sleep -Seconds 2
					}
				}
				Invoke-Command -Computername $VDIHost -ScriptBlock $SaveScript | Out-Null
			}
		}
		
		Write-Host "Jobs Started, waiting" -ForegroundColor Yellow -BackgroundColor DarkGreen
		Get-Job | Wait-Job
		Write-Host "VM Save Operations Complete" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		# Remove completed and failed jobs
		Remove-Job -State Completed
		Remove-Job -State Failed
	}

	if ($Mode -eq "LogOff") {
		# Check if there is an action delay and pause if necessary
		if ($ActionDelay -gt 0) {
			Write-Host "`nPausing for Action Delay of $ActionDelay Seconds`n" -ForegroundColor Yellow -BackgroundColor DarkGreen
			sleep $ActionDelay
		}

		# Retrieve the list of user sessions for the specified collection
		$SessionList = Get-RDUserSession -CollectionName $script:TargetCollectionName

		# Log off users from VDI machines
		Write-Host "`nLogging users off VDI Machines" -ForegroundColor Yellow -BackgroundColor DarkGreen
		foreach ($VMName in $VMNameArray) {
			# Start a job to log off a user from a VDI machine
			start-job -Name $VMName -ArgumentList $VMName, $VDIHost, $SessionList -ScriptBlock {
				param($VMName, $VDIHost, $SessionList)

				# Iterate through the user sessions to find the matching session for the current VDI machine
				foreach ($Session in $SessionList) {
					$VMTestName = $Session.ServerName

					# Check if the session corresponds to the current VDI machine
					if ($VMTestName -eq $VMName) {
						$Script:SelectedSession = $Session.UnifiedSessionID
						$Script:SelectedServer = $Session.HostServer
					}
				}

				# If a selected server is found, initiate the user logoff
				if ($SelectedServer) {
					Invoke-RDUserLogoff -HostServer $SelectedServer -UnifiedSessionID $SelectedSession -Force
				}
			}
		}

		# Wait for all jobs to complete
		Write-Host "Jobs Started, waiting" -ForegroundColor Yellow -BackgroundColor DarkGreen
		Get-Job | Wait-Job

		Write-Host "Finished Logging off Users" -ForegroundColor Yellow -BackgroundColor DarkGreen
		# Remove completed jobs
		Remove-Job -State Completed
	}


	if ($Mode -eq "ChangeHardware") { 
		# Check if there is an action delay and pause if necessary
		if ($ActionDelay -gt 0) {
			Write-Host "`nPausing for Action Delay of $ActionDelay Seconds`n" -ForegroundColor Yellow -BackgroundColor DarkGreen
			sleep $ActionDelay
		}
		
		Write-Host "`nUpdating VDI Machine Hardware Configuration" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		# Iterate through the array of VM names
		foreach ($VMName in $VMNameArray) {
			
			# Start a new job with the provided parameters and script block
			start-job -Name $VMName -ArgumentList $VMName, $VDIHost, $MinimumBytes, $StartupBytes, $MaximumBytes, $ProcessorCount -ScriptBlock {
				param($VMName, $VDIHost, $MinimumBytes, $StartupBytes, $MaximumBytes, $ProcessorCount)
				
				# Retrieve the IP address of the VM using a script block
				$script = {(get-vm -Name $using:VMName | Get-VMNetworkAdapter).IpAddresses[0]}
				$VMIPAddress = Invoke-Command -ComputerName $VDIHost -ScriptBlock $script
				
				$HardwareUpdateScript = {
					# Script block to update the VM's hardware configuration
					
					# Stop the VM and wait until it is turned off
					Stop-VM -Name $using:VMName
					while ((get-vm -name $using:VMName).state -ne 'Off') {
						start-sleep -Seconds 2
					}
					
					# Update the memory and processor count of the VM
					Set-VMMemory $using:VMName -MinimumBytes (1Gb * $using:MinimumBytes) -StartupBytes (1Gb * $using:StartupBytes) -MaximumBytes (1Gb * $using:MaximumBytes)
					Set-VMProcessor -VMName $using:VMName -Count $using:ProcessorCount
					
					# Start the VM
					start-vm $using:VMName
				}
				
				# Invoke the hardware update script block on the VDIHost
				Invoke-Command -Computername $VDIHost -ScriptBlock $HardwareUpdateScript | Out-Null
				
				write-host "Proc - $ProcessorCount, Min - $MinimumBytes, Max - $MaximumBytes, Start - $StartupBytes"
				
				# Wait until the VM is accessible via RDP (Remote Desktop Protocol)
				do {
					sleep 3
				} until (test-netconnection $VMIPAddress -Port 3389 | ? { $_.TcpTestSucceeded })
			}
		}
		
		write-host "Jobs Started, waiting" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		# Wait for all jobs to complete
		Get-Job | Wait-Job
		
		write-host "Hardware Config Change Operations Complete" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		# Remove completed and failed jobs
		Remove-Job -State Completed
		Remove-Job -State Failed
	}

	if ($Mode -eq "JoinDomain") {
		# Check if domain credentials are already collected
		if ([string]::IsNullOrWhiteSpace($script:DomainCreds)) {
			write-host "`n`n`nPreviously entered credentials not detected, let's collect your credentials before we proceed" -ForegroundColor Yellow -BackgroundColor DarkGreen

			# Collect domain credentials
			write-host "`n`n`n**** Enter your domain credentials that can join machines to the domain, LIKE - domain\username - ****" -ForegroundColor White -BackgroundColor Blue
			$script:DomainCreds = get-credential

			# Collect local admin credentials for target machines
			write-host "`n`n`n**** Enter the LOCAL ADMIN Credentials of target machines, LIKE  - localhost\username - ****" -ForegroundColor White -BackgroundColor Red
			$script:LocalCred = get-credential

			# Warning message to confirm correct input of credentials
			Write-Warning "`n`n`nCredentials collected. ARE YOU ABSOLUTELY SURE YOU TYPED THEM IN CORRECTLY? These will be stored until the script is ended.`nPress H if not sure, and try again" -WarningAction Inquire
		}

		# Pause if an action delay is specified
		if ($ActionDelay -gt 0) {
			Write-Host "`nPausing for Action Delay of $ActionDelay Seconds`n" -ForegroundColor Yellow -BackgroundColor DarkGreen
			sleep $ActionDelay
		}

		Write-Host "`nJoining VDI Machines to the Domain" -ForegroundColor Yellow -BackgroundColor DarkGreen

		# Iterate through the array of VM names
		foreach ($VMName in $VMNameArray) {
			# Start a job for each VM to join it to the domain
			start-job -Name $VMName -ArgumentList $script:OrgUnitPath, $script:DomainToJoin, $VMName, $VDIHost, $DomainCreds, $LocalCred -ScriptBlock {
				param($OrgUnitPath, $DomainToJoin, $VMName, $VDIHost, $DomainCreds, $LocalCred)

				# Get the IP address of the VM
				$script = {
					(get-vm -Name $using:VMName | Get-VMNetworkAdapter).IpAddresses[0]
				}
				$VMIPAddress = Invoke-Command -ComputerName $VDIHost -ScriptBlock $script

				# Join the VM to the domain
				add-computer -ComputerName $VMIPAddress -DomainName $DomainToJoin -LocalCredential $LocalCred -DomainCredential $DomainCreds -OUPath $OrgUnitPath

				# Restart the VM
				restart-computer -ComputerName $VMIPAddress -Credential $LocalCred -Force

				sleep 15

				# Check if the VM is reachable over RDP (port 3389)
				do {
					sleep 3
				} until (test-netconnection $VMIPAddress -Port 3389 | ? { $_.TcpTestSucceeded })

				sleep 45
			}
		}

		write-host "Jobs Started, waiting" -ForegroundColor Yellow -BackgroundColor DarkGreen

		# Wait for all jobs to complete
		Get-Job | Wait-Job

		write-host "Domain Join Operations Complete" -ForegroundColor Yellow -BackgroundColor DarkGreen

		# Remove completed and failed jobs
		Remove-Job -State Completed
		Remove-Job -State Failed
	}


	if ($Mode -eq "RenameAndJoinDomain") {
		# Check if domain credentials are already provided
		if ([string]::IsNullOrWhiteSpace($script:DomainCreds)) {
			write-host "`n`n`nPreviously entered credentials not detected. Let's collect your credentials before we proceed." -ForegroundColor Yellow -BackgroundColor DarkGreen
			
			# Prompt for domain credentials
			write-host "`n`n`n**** Enter your domain credentials that can join machines to the domain, LIKE - domain\username - ****" -ForegroundColor White -BackgroundColor Blue
			$script:DomainCreds = get-credential
			
			# Prompt for local admin credentials of target machines
			write-host "`n`n`n**** Enter the LOCAL ADMIN Credentials of target machines, LIKE  - localhost\username - ****" -ForegroundColor White -BackgroundColor Red
			$script:LocalCred = get-credential
			
			# Warning to verify the entered credentials
			Write-Warning "`n`n`nCredentials collected. ARE YOU ABSOLUTELY SURE YOU TYPED THEM IN CORRECTLY? These will be stored until the script is ended.`nPress H if not sure and try again" -WarningAction Inquire
		}
		
		# Pause if there is an action delay specified
		if ($ActionDelay -gt 0) {
			Write-Host "`nPausing for Action Delay of $ActionDelay Seconds`n" -ForegroundColor Yellow -BackgroundColor DarkGreen
			sleep $ActionDelay
		}
		
		Write-Host "`nRenaming and Joining VDI Machines to the Domain" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		# Iterate through the array of VM names
		foreach ($VMName in $VMNameArray) {
			# Remotely rename and join each computer to the domain using a background job
			start-job -Name $VMName -ArgumentList $script:OrgUnitPath, $script:DomainToJoin, $VMName, $VDIHost, $DomainCreds, $LocalCred -ScriptBlock {
				param($OrgUnitPath, $DomainToJoin, $VMName, $VDIHost, $DomainCreds, $LocalCred)
				
				# Get the IP address of the VM
				$script = {
					(get-vm -Name $using:VMName | Get-VMNetworkAdapter).IpAddresses[0]
				}
				$VMIPAddress = Invoke-Command -ComputerName $VDIHost -ScriptBlock $script
				
				# Rename the computer
				rename-computer -ComputerName $VMIPAddress -NewName $VMName -LocalCredential $LocalCred -Force
				
				# Restart the computer
				restart-computer -ComputerName $VMIPAddress -Credential $LocalCred -Force
				sleep 30
				
				# Wait until the VM is reachable over RDP
				do {
					sleep 3
				} until (test-netconnection $VMIPAddress -Port 3389 | ? { $_.TcpTestSucceeded })
				
				sleep 60
				
				# Add the computer to the domain
				add-computer -ComputerName $VMIPAddress -DomainName $DomainToJoin -LocalCredential $LocalCred -DomainCredential $DomainCreds -OUPath $OrgUnitPath
				
				# Restart the computer again
				restart-computer -ComputerName $VMIPAddress -Credential $LocalCred -Force
				sleep 15
				
				# Wait until the VM is reachable over RDP after domain join
				do {
					sleep 3
				} until (test-netconnection $VMIPAddress -Port 3389 | ? { $_.TcpTestSucceeded })
				
				sleep 45
			}
		}
		
		write-host "Jobs Started, waiting" -ForegroundColor Yellow -BackgroundColor DarkGreen
		Get-Job | Wait-Job
		
		write-host "Rename and Domain Join Operations Complete" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		# Remove completed and failed jobs
		Remove-Job -State Completed
		Remove-Job -State Failed
	}


	if ($Mode -eq "RemoveFromPool") {
		# Remove VDI Machines from the Pool
		if ($ActionDelay -gt 0) {
			Write-Host "`nPausing for Action Delay of $ActionDelay Seconds`n" -ForegroundColor Yellow -BackgroundColor DarkGreen
			Start-Sleep -Seconds $ActionDelay
		}
		
		Write-Host "`nRemoving VDI Machines from the Pool" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		foreach ($VMName in $VMNameArray) {
			$CollectionName = $script:TargetCollectionName
			# Remove the virtual desktop from the collection
			Remove-RDVirtualDesktopFromCollection -ConnectionBroker $script:RDSHPoolManager -CollectionName "$CollectionName" -VirtualDesktopName @("$VMName") -Force
		}
	}

	if ($Mode -eq "RemoveVDIAssignment") {
		# Remove VDI Assignments
		if ($ActionDelay -gt 0) {
			Write-Host "`nPausing for Action Delay of $ActionDelay Seconds`n" -ForegroundColor Yellow -BackgroundColor DarkGreen
			Start-Sleep -Seconds $ActionDelay
		}
		
		Write-Host "`nRemoving VDI Machine Assignments" -ForegroundColor Yellow -BackgroundColor DarkGreen
		
		foreach ($VMName in $VMNameArray) {
			# Remove the personal virtual desktop assignment
			Remove-RDPersonalVirtualDesktopAssignment -CollectionName $script:TargetCollectionName -VirtualDesktopName "$VMName" -Force
		}
	}




}

function Create_Or_Replace_VDI_Machines (){

# Check if domain credentials are already entered
if ([string]::IsNullOrWhiteSpace($script:DomainCreds)) {
    write-host "`n`n`nPreviously entered credentials not detected. Let's collect your credentials before we proceed." -ForegroundColor Yellow -BackgroundColor DarkGreen
    
    # Prompt user to enter domain credentials
    write-host "`n`n`n**** Enter your domain credentials that can join machines to the domain, LIKE - domain\username - ****" -ForegroundColor White -BackgroundColor Blue
    $script:DomainCreds = Get-Credential
    
    # Prompt user to enter local admin credentials
    write-host "`n`n`n**** Enter the LOCAL ADMIN Credentials of target machines, LIKE  - localhost\username - ****" -ForegroundColor White -BackgroundColor Red
    $script:LocalCred = Get-Credential
    
    # Warn the user about credentials and ask for confirmation
    Write-Warning "`n`n`nCredentials collected. ARE YOU ABSOLUTELY SURE YOU TYPED THEM IN CORRECTLY? These will be stored until the script is ended.`nPress H if not sure, and try again" -WarningAction Inquire
}

# Prompt the user for the number of VMs to be created
[int]$NumberofVMs = Read-Host -Prompt "How many VM's should be created?"
if([string]::IsNullOrWhiteSpace($NumberofVMs)){Exit}

# Prompt the user for the starting number for VMs
$VMStartingNumber = Read-Host -Prompt "Starting Number for VM's?  IE 5 or 1003 or 5001.  Press ENTER for 1.  Script will count up from here creating the number of VM's specified in the previous prompt."
if([string]::IsNullOrWhiteSpace($VMStartingNumber)){$VMStartingNumber = 1}

# Prompt the user for the VM host (VDI host)
$VDIHost = Read-Host -Prompt "Which VM Host? Press ENTER to use the default - $script:DefaultVDIHost"
if([string]::IsNullOrWhiteSpace($VDIHost)){$VDIHost = $script:DefaultVDIHost}

#pulling in variables to this function to be sent to the script later
$RDSHPoolManager = $script:RDSHPoolManager
$VMPath = $script:VMPath
$ProcessorCount = $script:ProcessorCount
$StartupMemory = $script:StartupMemory
$MinMemory = $script:MinMemory
$MaxMemory = $script:MaxMemory
$StartAction = $script:StartAction
$StopAction = $script:StopAction
$AutoStartDelay = $script:AutoStartDelay
$SysVHDPath = $script:SysVHDPath
$VMSwitchName = $script:VMSwitchName
$VlanId = $script:VlanId
$VMQ = $script:VMQ
$IPSecOffload = $script:IPSecOffload
$SRIOV = $script:SRIOV
$MacSpoofing = $script:MacSpoofing
$DHCPGuard = $script:DHCPGuard
$RouterGuard = $script:RouterGuard
$NicTeaming = $script:NicTeaming

$CollectionName = $script:TargetCollectionName

# Calculate the ending VM number based on the starting number and the total number of VMs
[int]$VMEndingNumber = ([int]$VMStartingNumber) + (($NumberofVMs) - 1)

# Display the starting and ending VM numbers
Write-Host "VM Start = $VMStartingNumber, VM END = $VMEndingNumber" -ForegroundColor Yellow -BackgroundColor DarkGreen

# Generate an array of VM numbers from the starting number to the ending number
$VMNumberArray = ([int]$VMStartingNumber..$VMEndingNumber)

# Format the VM numbers with leading zeros (e.g., 0001, 0002, etc.)
$VMNumberArray = $VMNumberArray | ForEach-Object {"{0:D4}" -f $_}

# Generate an array of VM names by appending the VM prefix to each VM number
$VMNameArray = $VMNumberArray | ForEach-Object {"$script:VMPrefix$_"}

# Display the VM names that will be created
Write-Host "`n`nCreating $NumberofVMs VMs on $VDIHost and registering on $RDSHPoolManager, names will be:" -ForegroundColor Yellow -BackgroundColor DarkGreen
Write-Host $VMNameArray -ForegroundColor Yellow -BackgroundColor DarkGreen

Write-Warning "Are you sure you want to continue?" -WarningAction Inquire

Write-Host "`nSplitting the array of machines into chunks of $script:ChunkSize to be processed in sequence." -ForegroundColor Yellow -BackgroundColor DarkGreen

if ($VMNameArray.Length -gt $script:ChunkSize) {
    # If the array length is greater than the chunk size, divide the array into smaller chunks
    $VMNameArrayOfArrays = DivideList -List $VMNameArray -ChunkSize $script:ChunkSize
} else {
    # If the array length is smaller than or equal to the chunk size, keep the array as a single chunk
    $VMNameArrayOfArrays = @(,@($VMNameArray))
    # Weird shenanigans here to put the array inside the array as an array so that the following foreach statements work correctly on non-split arrays
}


foreach ($VMNameChunk in $VMNameArrayOfArrays)
{
	# Build/Rename operations
	
	write-host "`n`nStarting Build/Rename/Join operations on the following group" -ForegroundColor Yellow -BackgroundColor DarkGreen
	write-host $VMNameChunk -ForegroundColor Yellow -BackgroundColor DarkGreen
	write-host "`n`n`nBuilding VDI Machines. Warnings and Errors are common in this section, gems such as *already in the specified state* or *is not a member of the specified virtual desktop collection*." -ForegroundColor Yellow -BackgroundColor DarkGreen
	
	foreach ($VMName in $VMNameChunk)
	{
		Invoke-Command -ComputerName $VDIHost -ScriptBlock { Start-VM $using:VMName } | Out-Null  # have to start the VM or it won't remove correctly from the pool
		
		Remove-RDVirtualDesktopFromCollection -ConnectionBroker $RDSHPoolManager -CollectionName "$CollectionName" -VirtualDesktopName @("$VMName") -Force
		
		$script = {
			$VMName = $using:VMName
			$CollectionName = $using:CollectionName
			$RDSHPoolManager = $using:RDSHPoolManager
			$VMPath = $using:VMPath
			$ProcessorCount = $using:ProcessorCount
			$StartupMemory = $using:StartupMemory
			$MinMemory = $using:MinMemory
			$MaxMemory = $using:MaxMemory
			$StartAction = $using:StartAction
			$StopAction = $using:StopAction
			$AutoStartDelay = $using:AutoStartDelay
			$SysVHDPath = $using:SysVHDPath
			$OsDiskName = $VMName
			$VMSwitchName = $using:VMSwitchName
			$VlanId = $using:VlanId
			$VMQ = $using:VMQ
			$IPSecOffload = $using:IPSecOffload
			$SRIOV = $using:SRIOV
			$MacSpoofing = $using:MacSpoofing
			$DHCPGuard = $using:DHCPGuard
			$RouterGuard = $using:RouterGuard
			$NicTeaming = $using:NicTeaming
			
			While (-not $VMCreationComplete)
			{
				# Create the VM
				if (!(Get-VM $VMName -ErrorAction 0))
				{
					Write "Creating VM"
					
					# Create the VM
					New-VM -Name $VMName `
						   -Path $VMPath `
						   -NoVHD `
						   -Generation 2 `
						   -MemoryStartupBytes 1GB `
						   -SwitchName $VMSwitchName
					
					# Set VM Config
					Set-VM -Name $VMName `
						   -ProcessorCount $ProcessorCount `
						   -DynamicMemory `
						   -MemoryMinimumBytes $MinMemory `
						   -MemoryStartupBytes $StartupMemory `
						   -MemoryMaximumBytes $MaxMemory `
						   -AutomaticStartAction $StartAction `
						   -AutomaticStartDelay $AutoStartDelay `
						   -AutomaticStopAction $StopAction
					
					# Set the primary network adapters
					$PrimaryNetAdapter = Get-VM $VMName | Get-VMNetworkAdapter
					$PrimaryNetAdapter | Set-VMNetworkAdapterVLAN -Untagged
					
					# Set other network adapter parameters
					if ($VMQ) { $PrimaryNetAdapter | Set-VMNetworkAdapter -VmqWeight 100 }
					else { $PrimaryNetAdapter | Set-VMNetworkAdapter -VmqWeight 0 }
					if ($IPSecOffload) { $PrimaryNetAdapter | Set-VMNetworkAdapter -IPsecOffloadMaximumSecurityAssociation 512 }
					else { $PrimaryNetAdapter | Set-VMNetworkAdapter -IPsecOffloadMaximumSecurityAssociation 0 }
					if ($SRIOV) { $PrimaryNetAdapter | Set-VMNetworkAdapter -IovQueuePairsRequested 1 -IovInterruptModeration Default -IovWeight 100 }
					else { $PrimaryNetAdapter | Set-VMNetworkAdapter -IovWeight 0 }
					if ($MacSpoofing) { $PrimaryNetAdapter | Set-VMNetworkAdapter -MacAddressSpoofing On }
					else { $PrimaryNetAdapter | Set-VMNetworkAdapter -MacAddressSpoofing Off }
					if ($DHCPGuard) { $PrimaryNetAdapter | Set-VMNetworkAdapter -DHCPGuard On }
					else { $PrimaryNetAdapter | Set-VMNetworkAdapter -DHCPGuard Off }
					if ($RouterGuard) { $PrimaryNetAdapter | Set-VMNetworkAdapter -RouterGuard On }
					else { $PrimaryNetAdapter | Set-VMNetworkAdapter -RouterGuard Off }
					if ($NicTeaming) { $PrimaryNetAdapter | Set-VMNetworkAdapter -AllowTeaming On }
					else { $PrimaryNetAdapter | Set-VMNetworkAdapter -AllowTeaming Off }
					
					# Copy the OS Disk and Rename
					$OsDiskInfo = Get-Item $SysVHDPath
					Copy-Item -Path $SysVHDPath -Destination "$($VMPath)\$VMName"
					
					Rename-Item -Path "$($VMPath)\$VMName\$($OsDiskInfo.Name)" -NewName "$($OsDiskName)$($OsDiskInfo.Extension)"
					
					# Attach the VHD(x) to the VM
					Add-VMHardDiskDrive -VMName $VMName -Path "$($VMPath)\$VMName\$($OsDiskName)$($OsDiskInfo.Extension)"
					$OsVirtualDrive = Get-VMHardDiskDrive -VMName $VMName -ControllerNumber 0
					
					# Change the boot order to the VHDX first
					Set-VMFirmware -VMName $VMName -FirstBootDevice $OsVirtualDrive
					
					# Set the VM Processor Compatibility Mode
					Set-VMProcessor $VMName -CompatibilityForMigrationEnabled $true
					
					# Start the VM
					Start-VM -Name $VMName
					
					$VMCreationComplete = $true
				}
				else
				{
					# If VM exists, delete it. Without $VMCreationComplete as true, the loop will start over, and a new machine will be created after this
					Write "VM Already Exists"
					
					Stop-VM -VMName $VMName -TurnOff:$true -Confirm:$false
					
					Get-VM -VMName $VMName | Get-VMHardDiskDrive | Foreach { Remove-Item -Path $_.Path -Recurse -Force -Confirm:$false }
					
					Remove-VM -VMName $VMName -Force
					
					$VMFullPath = "$VMPath\$VMName"
					Remove-Item -LiteralPath $VMFullPath -Force -Recurse
					
					Sleep 3
					
					Write "VM Deleted"
				} 
			}
		}
		Invoke-Command -ComputerName $VDIHost -ScriptBlock $script | Out-Null
	}

	Write-Host "VDI Machine Building Complete`n`n`nWaiting for Machines to Finish Booting" -ForegroundColor Yellow -BackgroundColor DarkGreen

	Remove-Job -State Completed
	Sleep 3

	# Wait for all machines to be fully booted
	foreach ($VMName in $VMNameChunk)
	{
		Start-Job -Name $VMName -ArgumentList $VMName,$VDIHost -ScriptBlock {
			param($VMName,$VDIHost)
			
			do
			{
				$script = { (Get-VM -Name $using:VMName | Get-VMNetworkAdapter).IpAddresses[0] }
				$VMIPAddress = Invoke-Command -ComputerName $using:VDIHost -ScriptBlock $script
				
				if(!$VMIPAddress)
				{
					$VMIPAddress = "0.0.0.0"
				}
				
				Sleep 3
			} until (Test-NetConnection $VMIPAddress -Port 3389 | ? { $_.TcpTestSucceeded })
		}
	}

	Write-Host "Jobs Started, waiting" -ForegroundColor Yellow -BackgroundColor DarkGreen
	Get-Job | Wait-Job -Timeout 300
	Write-Host "New VDI Machines Fully Booted" -ForegroundColor Yellow -BackgroundColor DarkGreen

	Write-Host "`n`n`nStarting Rename Operations on New VDI Machines" -ForegroundColor Yellow -BackgroundColor DarkGreen

	Remove-Job -State Completed

	foreach ($VMName in $VMNameChunk)
	{
		# Remotely rename each computer
		Start-Job -Name $VMName -ArgumentList $VMName,$VDIHost,$DomainCreds,$LocalCred -ScriptBlock {
			param($VMName,$VDIHost,$DomainCreds,$LocalCred)
			
			do
			{
				$script = { (Get-VM -Name $using:VMName | Get-VMNetworkAdapter).IpAddresses[0] }
				$VMIPAddress = Invoke-Command -ComputerName $using:VDIHost -ScriptBlock $script
				
				if(!$VMIPAddress)
				{
					$VMIPAddress = "0.0.0.0"
				}
				
				Sleep 3
			} until (Test-NetConnection $VMIPAddress -Port 3389 | ? { $_.TcpTestSucceeded })
			
			Rename-Computer -ComputerName $VMIPAddress -NewName $VMName -LocalCredential $LocalCred -Force
			
			$rnd = Get-Random -Minimum 1 -Maximum 5
			Sleep $rnd
			
			Restart-Computer -ComputerName $VMIPAddress -Credential $LocalCred -Force
		}
	}

	Write-Host "Jobs Started, waiting" -ForegroundColor Yellow -BackgroundColor DarkGreen
	Get-Job | Wait-Job -Timeout 300
	Write-Host "Rename Operations Complete" -ForegroundColor Yellow -BackgroundColor DarkGreen
}


# Pause to give all machines time to finish starting up
$key = GetKeyPress '[y]' "`n`n`nCheck that all machines are fully booted and ready for domain joining.`n`nThis prompt will timeout and the script will continue in 5 minutes.`n`nPress Y to continue now." $script:PostBuildPause

# Join domain Operations
foreach ($VMNameChunk in $VMNameArrayOfArrays) {
    # Display message indicating the start of domain joining operations
    write-host "`n`n`nStarting Domain Joining Operations on New VDI Machines" -Foregroundcolor Yellow -Backgroundcolor DarkGreen
    Remove-Job -State Completed
    
    foreach ($VMName in $VMNameChunk) {
        # Remotely join each computer to the domain
        start-job -Name $VMName -ArgumentList $script:OrgUnitPath, $script:DomainToJoin, $VMName, $VDIHost, $DomainCreds, $LocalCred -ScriptBlock {
            param($OrgUnitPath, $DomainToJoin, $VMName, $VDIHost, $DomainCreds, $LocalCred)
            
            # Get the IP address of the VM
            $script = {(Get-VM -Name $using:VMName | Get-VMNetworkAdapter).IpAddresses[0]}
            $VMIPAddress = Invoke-Command -ComputerName $using:VDIHost -ScriptBlock $script
            
            # Introduce a random delay to avoid issues with simultaneous domain joins
            $rnd = Get-Random -Minimum 1 -Maximum 10
            sleep $rnd
            
            # Join the computer to the domain
            add-computer -ComputerName $VMIPAddress -DomainName $DomainToJoin -LocalCredential $LocalCred -DomainCredential $DomainCreds -OUPath $OrgUnitPath
            
            # Wait for the domain join to complete before triggering a reboot
            sleep 5
            
            # Restart the computer
            restart-computer -ComputerName $VMIPAddress -Credential $LocalCred -Force
            
            # Wait for the machines to fully boot before moving on to the next set
            sleep 80
        }
    }
    
    # Display message indicating that the jobs have started and wait for them to complete
    write-host "Jobs Started, waiting" -Foregroundcolor Yellow -Backgroundcolor DarkGreen
    Get-Job | Wait-Job -Timeout 300
    write-host "Domain join Operations Complete" -Foregroundcolor Yellow -Backgroundcolor DarkGreen
}

# Left this here as an option, use $key if you want to timeout and continue automatically, use write-warning if you want it to wait indefinitely
#$key = GetKeyPress '[y]' "`n`n`nCheck that all machines are joined to the domain (Green Background).`n`nThis prompt will timeout and the script will continue in 5 minutes.`n`nPress Y to continue now." $script:PostBuildPause
Write-Warning "`n`n`nCheck that all machines are joined to the domain (Green Background). Continue?" -WarningAction Inquire

# Save all VMs in preparation for adding them to the pool
write-host "`n`nSaving All VM's in prep for adding to pool" -Foregroundcolor Yellow -Backgroundcolor DarkGreen
foreach ($VMName in $VMNameArray) {
    $script = {Save-VM -Name $using:VMName}
    Invoke-Command -ComputerName $VDIHost -ScriptBlock $script
}
sleep 20 # Wait for machines to finish going to sleep

# Add all VMs to the VDI Pool / Collection
write-host "Adding all VM's to the pool" -Foregroundcolor Yellow -Backgroundcolor DarkGreen
foreach ($VMName in $VMNameArray) {
    Add-RDVirtualDesktopToCollection -ConnectionBroker $RDSHPoolManager -CollectionName "$CollectionName" -VirtualDesktopName "$VMName"
}
write-host "Adding to pool is complete" -Foregroundcolor Yellow -Backgroundcolor DarkGreen

# Save/Add to Pool/Start operations
foreach ($VMNameChunk in $VMNameArrayOfArrays) {
    # Start up the VMs to finish any remaining new-machine tasks
    write-host "`n`n`nStarting up the following VM's, so they can finish any remaining new-machine stuff and be ready to use" -Foregroundcolor Yellow -Backgroundcolor DarkGreen
    write-host $VMNameChunk -Foregroundcolor Yellow -Backgroundcolor DarkGreen
    Remove-Job -State Completed
    
    foreach ($VMName in $VMNameChunk) {
        # Start all of the newly created VMs
        start-job -Name $VMName -ArgumentList $VMName, $VDIHost -ScriptBlock {
            param($VMName, $VDIHost)
            
            # Start the VM
            $script1 = {Start-VM -Name $using:VMName}
            Invoke-Command -ComputerName $VDIHost -ScriptBlock $script1
            
            # Get the IP address of the VM
            $script2 = {(Get-VM -Name $using:VMName | Get-VMNetworkAdapter).IpAddresses[0]}
            $VMIPAddress = Invoke-Command -ComputerName $VDIHost -ScriptBlock $script2
            
            # Wait for the VM to be reachable over RDP
            do { sleep 3 } until (test-netconnection $VMIPAddress -Port 3389 | ? { $_.TcpTestSucceeded })
        }
    }
    
    # Display message indicating that the jobs have started and wait for them to complete
    write-host "Jobs Started, waiting" -Foregroundcolor Yellow -Backgroundcolor DarkGreen
    Get-Job | Wait-Job -Timeout 300
    write-host "Job Complete, New VDI Machines Should be Ready to Use Now" -Foregroundcolor Yellow -Backgroundcolor DarkGreen
}



}

function Menu {
	do {
		Write-Host "`n`n================ Main Menu ================`n" -Foregroundcolor Yellow -Backgroundcolor DarkGreen
		
		Write-Host "1: Press '1' to Create or Replace one or more VDI Machines.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "2: Press '2' to Manage Existing VDI Machines.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "Q: Press 'Q' to exit." -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "`n"

		$menuselection = Read-Host "Please make a selection"
		switch ($menuselection){
			'1' {Create_Or_Replace_VDI_Machines;}
			'2' {Menu2}
		}
	}
until ($menuselection -eq 'q')
}

function Menu2 {
	do {
		Write-Host "`n`n====== Manage Existing VDI Machines ======`n" -Foregroundcolor Yellow -Backgroundcolor DarkGreen
		
		Write-Host "1: Press '1' to Send a Notification to one or more VDI machines.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "2: Press '2' to Log off users from one or more VDI machines.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "3: Press '3' to Save one or more VDI Machines.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "4: Press '4' to Reboot one or more VDI Machines.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "5: Press '5' to Shut Down one or more VDI Machines.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "6: Press '6' to Change VM Hardware Configuration.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "7: Press '7' to Join one more more VDI Machines to the domain.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "8: Press '8' to Rename and Join one more more VDI Machines.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "9: Press '9' to Remove VDI Machines from the Pool.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "10: Press '10' to Remove VDI Machine Assignments.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "11: Press '11' to Remove VDI Machine Assignments for Sessions that are LOGGED OFF.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "Q: Press 'Q' to exit to main menu.`n" -Foregroundcolor White -Backgroundcolor Blue
		Write-Host "`n"

		$menu2selection = Read-Host "Please make a selection"
		switch ($menu2selection){
			'1' {Manage_Existing_Machines -Mode NotifyOnly}
			'2' {Manage_Existing_Machines -Mode LogOff}
			'3' {Manage_Existing_Machines -Mode Save}
			'4' {Manage_Existing_Machines -Mode Reboot}
			'5' {Manage_Existing_Machines -Mode Shutdown}
			'6' {Manage_Existing_Machines -Mode ChangeHardware}
			'7' {Manage_Existing_Machines -Mode JoinDomain}
			'8' {Manage_Existing_Machines -Mode RenameAndJoinDomain}
			'9' {Manage_Existing_Machines -Mode RemoveFromPool}
			'10' {Manage_Existing_Machines -Mode RemoveVDIAssignment}
			'11' {Manage_Existing_Machines -Mode RemoveVDIAssignments-ThatAreLoggedOff}
		}
	}
until ($menu2selection -eq 'q')
}

Menu;