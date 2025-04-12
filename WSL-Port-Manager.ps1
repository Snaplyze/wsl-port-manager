# WSL Port Manager
# Script for opening WSL ports to the local network
# Usage: Run the script as administrator through PowerShell

# Function to check administrator rights
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    $principal = New-Object Security.Principal.WindowsPrincipal $user
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Check for administrator rights
if (-not (Test-Administrator)) {
    Write-Host "This script requires administrator rights!" -ForegroundColor Red
    Write-Host "Please run PowerShell as administrator and try again." -ForegroundColor Yellow
    exit 1
}

# Function to get WSL IP address
function Get-WslIpAddress {
    try {
        $wslIP = (wsl -e bash -c "ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'").Trim()
        if ([string]::IsNullOrEmpty($wslIP)) {
            Write-Host "Failed to get WSL IP address. Make sure WSL is running." -ForegroundColor Red
            exit 1
        }
        return $wslIP
    }
    catch {
        Write-Host "Error getting WSL IP address: $_" -ForegroundColor Red
        exit 1
    }
}

# Function to get list of proxied ports
function Get-ProxiedPorts {
    $portProxyOutput = netsh interface portproxy show v4tov4
    $ports = @()
    
    $lines = $portProxyOutput -split "`r`n" | Where-Object { $_ -match '\d+\.\d+\.\d+\.\d+' }
    
    foreach ($line in $lines) {
        if ($line -match '(\d+\.\d+\.\d+\.\d+):(\d+)\s+(\d+\.\d+\.\d+\.\d+):(\d+)') {
            $listenAddress = $matches[1]
            $listenPort = $matches[2]
            $connectAddress = $matches[3]
            $connectPort = $matches[4]
            
            $ports += [PSCustomObject]@{
                ListenAddress = $listenAddress
                ListenPort = $listenPort
                ConnectAddress = $connectAddress
                ConnectPort = $connectPort
            }
        }
    }
    
    return $ports
}

# Function to display list of ports
function Show-ProxiedPorts {
    $ports = Get-ProxiedPorts
    
    if ($ports.Count -eq 0) {
        Write-Host "No proxied ports for WSL." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Proxied ports for WSL:" -ForegroundColor Cyan
    Write-Host "------------------------------" -ForegroundColor Cyan
    
    foreach ($port in $ports) {
        Write-Host "Port $($port.ListenPort) -> $($port.ConnectAddress):$($port.ConnectPort)" -ForegroundColor Green
    }
}

# Function to add port proxy
function Add-PortProxy {
    param (
        [Parameter(Mandatory=$true)]
        [int]$Port
    )
    
    $wslIP = Get-WslIpAddress
    $ports = Get-ProxiedPorts
    
    # Check existing rules
    $existingPort = $ports | Where-Object { $_.ListenPort -eq $Port }
    if ($existingPort) {
        Write-Host "Port $Port is already proxied to $($existingPort.ConnectAddress):$($existingPort.ConnectPort)" -ForegroundColor Yellow
        
        $updateChoice = Read-Host "Do you want to update the rule for this port? (y/n)"
        if ($updateChoice -ne "y") {
            return
        }
        
        # Delete existing rule
        netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0
    }
    
    # Add new rule
    try {
        netsh interface portproxy add v4tov4 listenport=$Port listenaddress=0.0.0.0 connectport=$Port connectaddress=$wslIP
        Write-Host "Port $Port successfully proxied to WSL ($wslIP)" -ForegroundColor Green
        
        # Check firewall rule
        $firewallRule = Get-NetFirewallRule -DisplayName "WSL Port $Port" -ErrorAction SilentlyContinue
        if (-not $firewallRule) {
            New-NetFirewallRule -DisplayName "WSL Port $Port" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
            Write-Host "Firewall rule added for port $Port" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Error adding port: $_" -ForegroundColor Red
    }
}

# Function to remove port proxy
function Remove-PortProxy {
    param (
        [Parameter(Mandatory=$true)]
        [int]$Port
    )
    
    $ports = Get-ProxiedPorts
    
    # Check existing rules
    $existingPort = $ports | Where-Object { $_.ListenPort -eq $Port }
    if (-not $existingPort) {
        Write-Host "Port $Port not found in the list of proxied ports" -ForegroundColor Yellow
        return
    }
    
    # Delete rule
    try {
        netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0
        Write-Host "Port $Port proxy removed" -ForegroundColor Green
        
        # Offer to remove firewall rule
        $removeFirewall = Read-Host "Do you also want to remove the firewall rule for port $Port? (y/n)"
        if ($removeFirewall -eq "y") {
            Remove-NetFirewallRule -DisplayName "WSL Port $Port" -ErrorAction SilentlyContinue
            Write-Host "Firewall rule for port $Port removed" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Error removing port: $_" -ForegroundColor Red
    }
}

# Function to update all port proxy rules
function Update-AllPortProxies {
    $wslIP = Get-WslIpAddress
    $ports = Get-ProxiedPorts
    
    if ($ports.Count -eq 0) {
        Write-Host "No ports to update." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Updating port proxy rules for new WSL IP address: $wslIP" -ForegroundColor Cyan
    
    foreach ($port in $ports) {
        try {
            netsh interface portproxy delete v4tov4 listenport=$($port.ListenPort) listenaddress=$($port.ListenAddress)
            netsh interface portproxy add v4tov4 listenport=$($port.ListenPort) listenaddress=0.0.0.0 connectport=$($port.ConnectPort) connectaddress=$wslIP
            Write-Host "Updated port $($port.ListenPort) -> $wslIP`:$($port.ConnectPort)" -ForegroundColor Green
        }
        catch {
            Write-Host "Error updating port $($port.ListenPort): $_" -ForegroundColor Red
        }
    }
    
    Write-Host "All ports updated!" -ForegroundColor Green
}

# Function to quickly add common ports
function Add-CommonPorts {
    $commonPorts = @(80, 443, 3000, 3306, 5000, 5432, 8000, 8080, 8443, 9000, 9443)
    
    Write-Host "Adding common web development ports..." -ForegroundColor Cyan
    
    foreach ($port in $commonPorts) {
        Add-PortProxy -Port $port
    }
    
    Write-Host "All common ports added!" -ForegroundColor Green
}

# Main menu
function Show-Menu {
    Clear-Host
    Write-Host "=== WSL Port Manager ===" -ForegroundColor Cyan
    Write-Host "Current WSL IP address: $(Get-WslIpAddress)" -ForegroundColor Green
    Write-Host ""
    Write-Host "1: Show proxied ports" -ForegroundColor Yellow
    Write-Host "2: Add new port" -ForegroundColor Yellow
    Write-Host "3: Remove port" -ForegroundColor Yellow
    Write-Host "4: Update all rules (after WSL restart)" -ForegroundColor Yellow
    Write-Host "5: Add common ports (80, 443, 3000, 8080, etc.)" -ForegroundColor Yellow
    Write-Host "Q: Exit" -ForegroundColor Yellow
    Write-Host ""
}

# Main program loop
do {
    Show-Menu
    $choice = Read-Host "Select action"
    
    switch ($choice) {
        "1" {
            Show-ProxiedPorts
            Write-Host "`nPress any key to return to menu..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "2" {
            $port = Read-Host "Enter port number to proxy"
            if ($port -match '^\d+$') {
                Add-PortProxy -Port ([int]$port)
            } else {
                Write-Host "Invalid port number" -ForegroundColor Red
            }
            Write-Host "`nPress any key to return to menu..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "3" {
            $port = Read-Host "Enter port number to remove"
            if ($port -match '^\d+$') {
                Remove-PortProxy -Port ([int]$port)
            } else {
                Write-Host "Invalid port number" -ForegroundColor Red
            }
            Write-Host "`nPress any key to return to menu..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "4" {
            Update-AllPortProxies
            Write-Host "`nPress any key to return to menu..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "5" {
            Add-CommonPorts
            Write-Host "`nPress any key to return to menu..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
} until ($choice -eq 'q' -or $choice -eq 'Q')

Write-Host "Script execution completed." -ForegroundColor Cyan
