# 1. Initialize Log File
$LogPath = "C:\Windows\Temp\Printer_Installation_Log.txt"

function Write-Log ($Message, $Color = "White") {
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] $Message"
    $LogEntry | Out-File -FilePath $LogPath -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "=== Starting Hybrid Local/AD Printer Deployment Script ===" "Magenta"

# 2. Input Environment Gathering & Validation
$PrinterModel = Read-Host -Prompt "Enter the Printer Make or Model (e.g., Trux Pro 400)"
Write-Log "Target Printer Queue Name set to: $PrinterModel"

while ($true) {
    $PrinterIP = Read-Host -Prompt "Enter the $PrinterModel IP address"
    
    if ($PrinterIP -match '^((25[0-5]|2[0-4][0-9]|[0-1]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[0-1]?[0-9][0-9]?)$') {
        Write-Log "Valid IP format detected for $PrinterIP." "Green"
        Write-Log "Pinging $PrinterIP to verify network connection..." "Cyan"
        
        if (Test-Connection -ComputerName $PrinterIP -Count 3 -Quiet) {
            Write-Log "Printer at $PrinterIP is online and responding to pings." "Green"
            break
        } else {
            Write-Log "WARNING: Printer at $PrinterIP did not respond to pings." "Red"
            $Choice = Read-Host -Prompt "The printer appears offline. Continue anyway? (Y/N)"
            if ($Choice -eq 'Y' -or $Choice -eq 'y') {
                Write-Log "User bypassed ping failure. Proceeding with offline IP." "Yellow"
                break
            }
        }
    } else {
        Write-Log "Invalid IP address format. Please try again (e.g., 192.168.1.50)." "Red"
    }
}

$PortName = "IP_$PrinterIP"

# 3. Driver Source Decision Logic (AD Print Server vs Local Store)
Write-Log "`n[Driver Source Configuration] Select your deployment methodology..." "Cyan"
Write-Log "1) Extract driver from AD Print Server over the network"
Write-Log "2) Use a local driver path (.inf file on this machine)"
$SourceChoice = Read-Host -Prompt "Select choice (1 or 2)"

$DriverPath = $null
$DriverName = $null
$UseAuthenticatedDrive = $false
$DriveName = "ADPrintShare"

if ($SourceChoice -eq "1") {
    $PrintServerIP = Read-Host -Prompt "Enter the Active Directory Print Server IP address or Hostname"
    $DriverPath = "\\$PrintServerIP\print$\x64\PCC" 
    
    Write-Log "Verifying domain authentication status..." "Cyan"
    $ComputerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    
    if ($ComputerInfo.PartInDomain) {
        Write-Log "Device is joined to domain: $($ComputerInfo.Domain). Testing access to server share..." "Green"
        
        if (-not (Test-Path -Path $DriverPath -ErrorAction SilentlyContinue)) {
            Write-Log "Access denied to $DriverPath using current user context." "Yellow"
            $UseAuthenticatedDrive = $true
        }
    } else {
        Write-Log "Device is not joined to an Active Directory domain (Workgroup detected)." "Yellow"
        $UseAuthenticatedDrive = $true
    }
    
    if ($UseAuthenticatedDrive) {
        Write-Log "Requesting AD Domain Credentials to authenticate against print server..." "Cyan"
        $Credential = Get-Credential -UserName "DOMAIN\Username" -Message "Enter domain credentials to access the Print Server Share"
        
        try {
            Write-Log "Mapping temporary authenticated network drive to print server..." "Cyan"
            New-PSDrive -Name $DriveName -PSProvider FileSystem -Root $DriverPath -Credential $Credential -ErrorAction Stop | Out-Null
            Write-Log "Securely authenticated and mounted print share." "Green"
            $DriverPath = "$($DriveName):\"
        } catch {
            Write-Log "CRITICAL: Failed to authenticate against AD Print Server: $_" "Red"
            Write-Log "Switching back to local backup strategy..." "Yellow"
            $SourceChoice = "2"
            $DriverPath = Read-Host -Prompt "Enter the full path to your local driver .inf file (e.g., C:\Drivers\Trux\driver.inf)"
        }
    } else {
        Write-Log "Configured to source driver payloads from AD Target via Pass-Through Auth: $DriverPath" "Green"
    }
    
    if ($SourceChoice -eq "1") {
        $DriverName = Read-Host -Prompt "Enter the exact Driver Name registered on the AD Print Server"
    }
} else {
    $DriverPath = Read-Host -Prompt "Enter the full path to your local driver .inf file (e.g., C:\Drivers\Trux\driver.inf)"
}

# 4. Clear and Restart Print Spooler
Write-Log "`n[1/6] Restarting Print Spooler..." "Cyan"
try {
    Stop-Service Spooler -Force
    Remove-Item -Path "C:\Windows\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
    Start-Service Spooler -ErrorAction Stop
    Write-Log "Spooler successfully cleared and restarted." "Green"
} catch {
    Write-Log "CRITICAL: Failed to reset Print Spooler: $_" "Red"
}

# 5. Check and Remove Conflicting Shared/Network Printer Sessions
Write-Log "`n[2/6] Scanning for conflicting network or shared print sessions..." "Cyan"
try {
    $ConflictingPrinters = Get-Printer | Where-Object { $_.Name -like "*$PrinterModel*" -and ($_.Type -eq 'Connection' -or $_.ComputerName) }
    if ($ConflictingPrinters) {
        foreach ($OldPrinter in $ConflictingPrinters) {
            Write-Log "Found conflicting network/shared printer session: $($OldPrinter.Name). Removing it..." "Yellow"
            Remove-Printer -Name $OldPrinter.Name -ErrorAction Stop
            Write-Log "Successfully removed shared connection '$($OldPrinter.Name)'." "Green"
        }
    } else {
        Write-Log "No conflicting network or shared print sessions found." "Green"
    }
} catch {
    Write-Log "WARNING: Failed to fully clear old network queues, proceeding anyway: $_" "Yellow"
}

# 6. Check and Update Printer IP Port
Write-Log "`n[3/6] Configuring Printer Network Port..." "Cyan"
try {
    if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)) {
        Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIP -ErrorAction Stop
        Write-Log "Network port '$PortName' created successfully." "Green"
    } else {
        Write-Log "Network port '$PortName' already exists. Reusing it." "Yellow"
    }
} catch {
    Write-Log "CRITICAL: Failed to create printer port: $_" "Red"
}

# 7. Add, Parse, and Inject Driver Into Local Engine Store
Write-Log "`n[4/6] Injecting Driver into Windows Driver Store..." "Cyan"
try {
    if ($SourceChoice -eq "1") {
        Write-Log "Pulling structural file descriptors down from AD Print Server catalog..." "Cyan"
        Add-PrinterDriver -Name $DriverName -ComputerName $env:COMPUTERNAME -ErrorAction Stop
        Write-Log "AD Server Driver '$DriverName' compiled into local system definitions successfully." "Green"
    } else {
        if (Test-Path -Path $DriverPath) {
            $DriverName = (Get-Content $DriverPath | Select-String -Pattern '.*?=\s*.*?.dll' | Select-Object -First 1).Line.Split('=').Trim() -replace '"', ''
            if (-not $DriverName) {
                $DriverName = Read-Host -Prompt "Could not auto-parse INF. Please manually enter the exact Driver Name"
            } else {
                Write-Log "Automatically detected Local Driver Name: $DriverName" "Green"
            }
            pnputil.exe /add-driver $DriverPath /install | Out-Null
            Add-PrinterDriver -Name $DriverName -ErrorAction Stop
            Write-Log "Local Driver '$DriverName' successfully added and registered." "Green"
        } else {
            throw "Driver path error. INF file not found at '$DriverPath'."
        }
    }
} catch {
    Write-Log "CRITICAL: Failed to register driver with Windows: $_" "Red"
} finally {
    if ($UseAuthenticatedDrive -and (Get-PSDrive -Name $DriveName -ErrorAction SilentlyContinue)) {
        Remove-PSDrive -Name $DriveName -Force | Out-Null
        Write-Log "Dismounted temporary authenticated AD share connection safely." "Green"
    }
}

# 8. Reconnect or Add the Printer Object Locally
Write-Log "`n[5/6] Finalizing Local Printer Mapping..." "Cyan"
try {
    if (Get-Printer -Name $PrinterModel -ErrorAction SilentlyContinue) {
        Set-Printer -Name $PrinterModel -PortName $PortName -DriverName $DriverName -ErrorAction Stop
        Write-Log "Existing local '$PrinterModel' queue updated with new IP and driver patch." "Green"
    } else {
        Add-Printer -Name $PrinterModel -DriverName $DriverName -PortName $PortName -ErrorAction Stop
        Write-Log "New local '$PrinterModel' queue added successfully." "Green"
    }
} catch {
    Write-Log "CRITICAL: Failed to map or update the local printer object: $_" "Red"
}

# 9. Send Automated Test Page
Write-Log "`n[6/6] Initializing Automated Diagnostic Test Page..." "Cyan"
$TestPageChoice = Read-Host -Prompt "Would you like to print a physical test page now? (Y/N)"
if ($TestPageChoice -eq 'Y' -or $TestPageChoice -eq 'y') {
    try {
        Write-Log "Sending hardware diagnostic print instruction to: $PrinterModel..." "Cyan"
        $PrinterObject = Get-CimInstance -ClassName Win32_Printer -Filter "Name = '$PrinterModel'"
        $Result = Invoke-CimMethod -InputObject $PrinterObject -MethodName PrintTestPage
        
        if ($Result.ReturnValue -eq 0) {
            Write-Log "Test page sent successfully! Check the tray on $PrinterModel." "Green"
        } else {
            Write-Log "WARNING: Driver returned non-zero status code ($($Result.ReturnValue)). Spooler might be jammed." "Yellow"
        }
    } catch {
        Write-Log "Failed to trigger test page command sequence: $_" "Red"
    }
} else {
    Write-Log "User bypassed diagnostic test page execution." "Yellow"
}

Write-Log "`nScript complete. Session log saved to: $LogPath" "Magenta"
