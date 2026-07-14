# Automated Local Printer Deployment Script (Generic PCL 4 Model)

[![Platform: Windows](https://shields.io)](https://microsoft.com)
[![Language: PowerShell](https://shields.io)](https://github.com)
[![License: MIT](https://shields.io)](LICENSE)

An enterprise-grade PowerShell script that automates migrating Windows endpoints from legacy, shared network print sessions to a resilient, local TCP/IP execution model. This variant completely bypasses third-party driver installations, explicitly matching the target queue to the native, pre-installed Windows Generic / Text Only (PCL 4 compatible) print processing stack.

---

## Technical Architecture

The script executes the printer migration pipeline sequentially:

```text
[Spooler Purge] ➔ [Network Session Cleanup] ➔ [TCP/IP Port Configuration]
                      ➔ [Native Driver Call] ➔ [Local Mapping] ➔ [Diagnostics]
```

1. **Spooler Flush and Purge**: Force-stops the Print Spooler service, aggressively wipes out the local spool queue cache (`C:\Windows\System32\spool\PRINTERS\*`), and boots up the service clean to free locked print processing contexts.
2. **Network Connection Cleanup**: Scans user and system spaces for network printers matching the target name containing remote endpoints or print server linkages (`Type -eq 'Connection'`). It drops conflicting objects to prevent Windows print subsystem routing identity issues.
3. **Standard TCP/IP Porting**: Checks for the existence of a dedicated network port (`IP_X.X.X.X`). It either constructs a brand new hardware endpoint via `Add-PrinterPort` or safely reuses the legacy port mapping definition.
4. **Native Driver Selection**: Bypasses external driver store downloads, Active Directory `print$` paths, and localized `.inf` files. It directly invokes the OS native `"Generic / Text Only"` configuration array.
5. **Local Mapping Isolation**: Registers the endpoint to prioritize local execution logic over print server policies using `Add-Printer` or `Set-Printer`.
6. **Diagnostic Verification Loop**: Executes the hardware self-test method (`PrintTestPage`) directly via the local Windows CIM wrapper object model (`Win32_Printer`).

---

## Features

* **Zero-Driver Dependencies**: Operates with absolute insulation against external file source vulnerabilities by executing exclusively against native Windows driver system catalogs.
* **Legacy Session Destruction**: Automatically targets and strips away `Type -eq 'Connection'` network print mappings to prevent name collision errors.
* **Native CIM Self-Testing**: Triggers the official graphic Windows Test Page sequence down to the printer processor layer using low-level WMI/CIM method pipelines.
* **Enterprise Log Auditing**: Writes timestamped operation step traces out to a dedicated configuration text log for centralized auditing.

---

## Prerequisites and Requirements

* **Operating System**: Windows 10, Windows 11, Windows Server 2016, or newer editions.
* **Execution Privileges**: PowerShell must be launched with Elevated Administrator permissions to allow service manipulations, driver store updates, and network drive attachments.
* **Network Infrastructure Paths**: Workstation to Printer requires ICMP (Ping) and Port 9100 (RAW).

---

## Installation and Deployment

### 1. Clone the Repository
```bash
git clone https://github.com
cd automated-printer-deployment
```

### 2. Execution Run Command
Launch an elevated PowerShell console (Run as Administrator) and execute the script path:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
.\Deploy-LocalPrinter.ps1
```

---

## Production Source Code

Save this core logic segment directly as `Deploy-LocalPrinter.ps1`:

```powershell
# 1. Initialize Log File
\$LogPath = "C:\Windows\Temp\Printer_Installation_Log.txt"

function Write-Log (Message, Color = "White") {
    \$TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    \$LogEntry = "[\(TimeStamp]\)Message"
    LogEntry | Out-File -FilePath LogPath -Append
    Write-Host Message -ForegroundColor Color
}

Write-Log "=== Starting Native Generic Printer Deployment Script ===" "Magenta"

# 2. Input Environment Gathering & Validation
\$PrinterModel = Read-Host -Prompt "Enter the Printer Make or Model (e.g., Trux Pro 400)"
Write-Log "Target Printer Queue Name set to: \$PrinterModel"

while (\$true) {
    PrinterIP = Read-Host -Prompt "Enter the PrinterModel IP address"
    
    if (\(PrinterIP -match '^((25[0-5]\vert{}2[0-4][0-9]\vert{}[0-1]?[0-9][0-9]?)\.){3}(25[0-5]\vert{}2[0-4][0-9]\vert{}[0-1]?[0-9][0-9]?)\)') {
        Write-Log "Valid IP format detected for \$PrinterIP." "Green"
        Write-Log "Pinging \$PrinterIP to verify network connection..." "Cyan"
        
        if (Test-Connection -ComputerName \$PrinterIP -Count 3 -Quiet) {
            Write-Log "Printer at \$PrinterIP is online and responding to pings." "Green"
            break
        } else {
            Write-Log "WARNING: Printer at \$PrinterIP did not respond to pings." "Red"
            \$Choice = Read-Host -Prompt "The printer appears offline. Continue anyway? (Y/N)"
            if (Choice -eq 'Y' -or Choice -eq 'y') {
                Write-Log "User bypassed ping failure. Proceeding with offline IP." "Yellow"
                break
            }
        }
    } else {
        Write-Log "Invalid IP address format. Please try again (e.g., 192.168.1.50)." "Red"
    }
}

\(PortName = "IP_\)PrinterIP"

# 3. Direct Native Driver Core Definition
# Bypasses installation steps by referencing the pre-baked Windows PCL 4 text catalog
\$DriverName = "Generic / Text Only"
Write-Log "Driver selection locked to native store index: \$DriverName" "Green"

# 4. Clear and Restart Print Spooler
Write-Log "`n[1/5] Restarting Print Spooler..." "Cyan"
try {
    Stop-Service Spooler -Force
    Remove-Item -Path "C:\Windows\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
    Start-Service Spooler -ErrorAction Stop
    Write-Log "Spooler successfully cleared and restarted." "Green"
} catch {
    Write-Log "CRITICAL: Failed to reset Print Spooler: $_" "Red"
}

# 5. Check and Remove Conflicting Shared/Network Printer Sessions
Write-Log "`n[2/5] Scanning for conflicting network or shared print sessions..." "Cyan"
try {
    \$ConflictingPrinters = Get-Printer | Where-Object { \(_.Name -like "*\)PrinterModel*" -and (\(_.Type -eq 'Connection' -or\)_.ComputerName) }
    if (\$ConflictingPrinters) {
        foreach (OldPrinter in ConflictingPrinters) {
            Write-Log "Found conflicting network/shared printer session: (OldPrinter.Name). Removing it..." "Yellow"
            Remove-Printer -Name \$OldPrinter.Name -ErrorAction Stop
            Write-Log "Successfully removed shared connection '(OldPrinter.Name)'." "Green"
        }
    } else {
        Write-Log "No conflicting network or shared print sessions found." "Green"
    }
} catch {
    Write-Log "WARNING: Failed to fully clear old network queues, proceeding anyway: \$_" "Yellow"
}

# 6. Check and Update Printer IP Port
Write-Log "`n[3/5] Configuring Printer Network Port..." "Cyan"
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

# 7. Reconnect or Add the Printer Object Locally using Generic Catalog
Write-Log "`n[4/5] Finalizing Local Printer Mapping..." "Cyan"
try {
    if (Get-Printer -Name \$PrinterModel -ErrorAction SilentlyContinue) {
        Set-Printer -Name \$PrinterModel -PortName PortName -DriverName DriverName -ErrorAction Stop
        Write-Log "Existing local '\$PrinterModel' queue updated with new IP and driver patch." "Green"
    } else {
        Add-Printer -Name \$PrinterModel -DriverName DriverName -PortName PortName -ErrorAction Stop
        Write-Log "New local '\$PrinterModel' queue added successfully." "Green"
    }
} catch {
    Write-Log "CRITICAL: Failed to map or update the local printer object: \$_" "Red"
}

# 8. Send Automated Test Page
Write-Log "`n[5/5] Initializing Automated Diagnostic Test Page..." "Cyan"
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

Write-Log "`nScript complete. Session log saved to: \$LogPath" "Magenta"
```

---

## Troubleshooting and Logs

Logs are updated line-by-line during runtime and written to:
`C:\Windows\Temp\Printer_Installation_Log.txt`

---

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.
