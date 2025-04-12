# WSL Port Manager - Basic Version
# Run as administrator

# Check admin rights
$currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Please run this script as Administrator" -ForegroundColor Red
    exit
}

# Get WSL IP Address
function Get-WSLIPAddress {
    try {
        $wslIP = (wsl -e bash -c "ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'").Trim()
        if ($wslIP -eq $null -or $wslIP -eq "") {
            Write-Host "Could not get WSL IP address. Is WSL running?" -ForegroundColor Red
            exit
        }
        return $wslIP
    }
    catch {
        Write-Host "Error getting WSL IP" -ForegroundColor Red
        exit
    }
}

# Show current port forwards
function Show-Ports {
    $output = netsh interface portproxy show all
    $hasEntries = $false
    
    Write-Host ""
    Write-Host "Current WSL Port Forwards:" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------" -ForegroundColor Cyan
    
    foreach ($line in $output) {
        if ($line -match "\d+\.\d+\.\d+\.\d+") {
            Write-Host $line -ForegroundColor Green
            $hasEntries = $true
        }
    }
    
    if (-not $hasEntries) {
        Write-Host "No port forwards found." -ForegroundColor Yellow
    }
    
    Write-Host "--------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
}

# Add a port forward
function Add-Port {
    param(
        [int]$Port
    )
    
    $wslIP = Get-WSLIPAddress
    
    try {
        # Add port forwarding
        netsh interface portproxy add v4tov4 listenport=$Port listenaddress=0.0.0.0 connectport=$Port connectaddress=$wslIP | Out-Null
        
        # Add firewall rule
        $ruleName = "WSL Port $Port"
        $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        
        if (-not $existingRule) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
            Write-Host "Added port $Port forwarding to WSL ($wslIP) with firewall rule" -ForegroundColor Green
        } else {
            Write-Host "Added port $Port forwarding to WSL ($wslIP) - firewall rule already exists" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Error adding port $Port" -ForegroundColor Red
    }
}

# Remove a port forward
function Remove-Port {
    param(
        [int]$Port
    )
    
    try {
        # Remove port forwarding
        netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 | Out-Null
        Write-Host "Removed port $Port forwarding" -ForegroundColor Green
        
        # Ask about firewall rule
        $response = Read-Host "Do you want to remove the firewall rule too? (y/n)"
        
        if ($response -eq "y") {
            Remove-NetFirewallRule -DisplayName "WSL Port $Port" -ErrorAction SilentlyContinue | Out-Null
            Write-Host "Removed firewall rule for port $Port" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Error removing port $Port" -ForegroundColor Red
    }
}

# Update all port forwards to current WSL IP
function Update-Ports {
    $wslIP = Get-WSLIPAddress
    $output = netsh interface portproxy show all
    $updatedCount = 0
    
    Write-Host "Updating port forwards to WSL IP: $wslIP" -ForegroundColor Cyan
    
    foreach ($line in $output) {
        if ($line -match "0\.0\.0\.0\s+(\d+)\s+") {
            $port = $matches[1]
            
            try {
                netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 | Out-Null
                netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$wslIP | Out-Null
                Write-Host "Updated port $port" -ForegroundColor Green
                $updatedCount++
            }
            catch {
                Write-Host "Failed to update port $port" -ForegroundColor Red
            }
        }
    }
    
    if ($updatedCount -eq 0) {
        Write-Host "No ports found to update" -ForegroundColor Yellow
    }
    else {
        Write-Host "Updated $updatedCount port forwards to $wslIP" -ForegroundColor Green
    }
}

# Add common ports
function Add-CommonPorts {
    $ports = @(80, 443, 3000, 3306, 5000, 5432, 8000, 8080, 8443, 9000, 9443)
    $wslIP = Get-WSLIPAddress
    
    Write-Host "Adding common ports for WSL ($wslIP)..." -ForegroundColor Cyan
    
    foreach ($port in $ports) {
        Add-Port -Port $port
    }
    
    Write-Host "Finished adding common ports" -ForegroundColor Green
}

# Main menu
function Show-Menu {
    $wslIP = Get-WSLIPAddress
    Clear-Host
    Write-Host "WSL Port Manager - Current WSL IP: $wslIP" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------" -ForegroundColor Cyan
    Write-Host "1. Show current port forwards" -ForegroundColor Yellow
    Write-Host "2. Add a new port forward" -ForegroundColor Yellow
    Write-Host "3. Remove a port forward" -ForegroundColor Yellow
    Write-Host "4. Update all port forwards (after WSL restart)" -ForegroundColor Yellow
    Write-Host "5. Add common ports (80, 443, 3000, 8080, etc)" -ForegroundColor Yellow
    Write-Host "Q. Exit" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------" -ForegroundColor Cyan
}

# Main loop
do {
    Show-Menu
    $choice = Read-Host "Select an option"
    
    switch ($choice) {
        "1" {
            Show-Ports
            Read-Host "Press Enter to continue"
        }
        "2" {
            $port = Read-Host "Enter port number to forward"
            if ($port -match "^\d+$") {
                Add-Port -Port ([int]$port)
            } else {
                Write-Host "Invalid port number" -ForegroundColor Red
            }
            Read-Host "Press Enter to continue"
        }
        "3" {
            $port = Read-Host "Enter port number to remove"
            if ($port -match "^\d+$") {
                Remove-Port -Port ([int]$port)
            } else {
                Write-Host "Invalid port number" -ForegroundColor Red
            }
            Read-Host "Press Enter to continue"
        }
        "4" {
            Update-Ports
            Read-Host "Press Enter to continue"
        }
        "5" {
            Add-CommonPorts
            Read-Host "Press Enter to continue"
        }
    }
} until ($choice -eq "q" -or $choice -eq "Q")

Write-Host "WSL Port Manager closed" -ForegroundColor Cyan
