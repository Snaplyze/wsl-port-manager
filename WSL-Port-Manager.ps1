# WSL Port Manager
# Скрипт для открытия портов WSL в локальную сеть
# Использование: запустите скрипт от имени администратора через PowerShell

# Функция для проверки прав администратора
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    $principal = New-Object Security.Principal.WindowsPrincipal $user
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Проверка прав администратора
if (-not (Test-Administrator)) {
    Write-Host "Этот скрипт требует прав администратора!" -ForegroundColor Red
    Write-Host "Пожалуйста, запустите PowerShell от имени администратора и попробуйте снова." -ForegroundColor Yellow
    exit 1
}

# Функция для получения IP-адреса WSL
function Get-WslIpAddress {
    try {
        $wslIP = (wsl -e bash -c "ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'").Trim()
        if ([string]::IsNullOrEmpty($wslIP)) {
            Write-Host "Не удалось получить IP-адрес WSL. Убедитесь, что WSL запущен." -ForegroundColor Red
            exit 1
        }
        return $wslIP
    }
    catch {
        Write-Host "Ошибка при получении IP-адреса WSL: $_" -ForegroundColor Red
        exit 1
    }
}

# Функция для получения списка проксированных портов
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

# Функция для отображения списка портов
function Show-ProxiedPorts {
    $ports = Get-ProxiedPorts
    
    if ($ports.Count -eq 0) {
        Write-Host "Нет проксированных портов для WSL." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Проксированные порты для WSL:" -ForegroundColor Cyan
    Write-Host "------------------------------" -ForegroundColor Cyan
    
    foreach ($port in $ports) {
        Write-Host "Порт $($port.ListenPort) -> $($port.ConnectAddress):$($port.ConnectPort)" -ForegroundColor Green
    }
}

# Функция для добавления проксирования порта
function Add-PortProxy {
    param (
        [Parameter(Mandatory=$true)]
        [int]$Port
    )
    
    $wslIP = Get-WslIpAddress
    $ports = Get-ProxiedPorts
    
    # Проверка существующих правил
    $existingPort = $ports | Where-Object { $_.ListenPort -eq $Port }
    if ($existingPort) {
        Write-Host "Порт $Port уже проксируется на $($existingPort.ConnectAddress):$($existingPort.ConnectPort)" -ForegroundColor Yellow
        
        $updateChoice = Read-Host "Хотите обновить правило для этого порта? (y/n)"
        if ($updateChoice -ne "y") {
            return
        }
        
        # Удаление существующего правила
        netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0
    }
    
    # Добавление нового правила
    try {
        netsh interface portproxy add v4tov4 listenport=$Port listenaddress=0.0.0.0 connectport=$Port connectaddress=$wslIP
        Write-Host "Порт $Port успешно проксирован на WSL ($wslIP)" -ForegroundColor Green
        
        # Проверка правила брандмауэра
        $firewallRule = Get-NetFirewallRule -DisplayName "WSL Port $Port" -ErrorAction SilentlyContinue
        if (-not $firewallRule) {
            New-NetFirewallRule -DisplayName "WSL Port $Port" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
            Write-Host "Добавлено правило брандмауэра для порта $Port" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Ошибка при добавлении порта: $_" -ForegroundColor Red
    }
}

# Функция для удаления проксирования порта
function Remove-PortProxy {
    param (
        [Parameter(Mandatory=$true)]
        [int]$Port
    )
    
    $ports = Get-ProxiedPorts
    
    # Проверка существующих правил
    $existingPort = $ports | Where-Object { $_.ListenPort -eq $Port }
    if (-not $existingPort) {
        Write-Host "Порт $Port не найден в списке проксированных портов" -ForegroundColor Yellow
        return
    }
    
    # Удаление правила
    try {
        netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0
        Write-Host "Проксирование порта $Port удалено" -ForegroundColor Green
        
        # Предложение удалить правило брандмауэра
        $removeFirewall = Read-Host "Хотите также удалить правило брандмауэра для порта $Port? (y/n)"
        if ($removeFirewall -eq "y") {
            Remove-NetFirewallRule -DisplayName "WSL Port $Port" -ErrorAction SilentlyContinue
            Write-Host "Правило брандмауэра для порта $Port удалено" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Ошибка при удалении порта: $_" -ForegroundColor Red
    }
}

# Функция для обновления всех правил проксирования
function Update-AllPortProxies {
    $wslIP = Get-WslIpAddress
    $ports = Get-ProxiedPorts
    
    if ($ports.Count -eq 0) {
        Write-Host "Нет портов для обновления." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Обновление правил проксирования портов для нового IP-адреса WSL: $wslIP" -ForegroundColor Cyan
    
    foreach ($port in $ports) {
        try {
            netsh interface portproxy delete v4tov4 listenport=$($port.ListenPort) listenaddress=$($port.ListenAddress)
            netsh interface portproxy add v4tov4 listenport=$($port.ListenPort) listenaddress=0.0.0.0 connectport=$($port.ConnectPort) connectaddress=$wslIP
            Write-Host "Обновлен порт $($port.ListenPort) -> $wslIP:$($port.ConnectPort)" -ForegroundColor Green
        }
        catch {
            Write-Host "Ошибка при обновлении порта $($port.ListenPort): $_" -ForegroundColor Red
        }
    }
    
    Write-Host "Все порты обновлены!" -ForegroundColor Green
}

# Функция для быстрого добавления набора типичных портов
function Add-CommonPorts {
    $commonPorts = @(80, 443, 3000, 3306, 5000, 5432, 8000, 8080, 8443, 9000, 9443)
    
    Write-Host "Добавление типичных портов для веб-разработки..." -ForegroundColor Cyan
    
    foreach ($port in $commonPorts) {
        Add-PortProxy -Port $port
    }
    
    Write-Host "Все типичные порты добавлены!" -ForegroundColor Green
}

# Главное меню
function Show-Menu {
    Clear-Host
    Write-Host "=== WSL Port Manager ===" -ForegroundColor Cyan
    Write-Host "Текущий IP-адрес WSL: $(Get-WslIpAddress)" -ForegroundColor Green
    Write-Host ""
    Write-Host "1: Показать проксированные порты" -ForegroundColor Yellow
    Write-Host "2: Добавить новый порт" -ForegroundColor Yellow
    Write-Host "3: Удалить порт" -ForegroundColor Yellow
    Write-Host "4: Обновить все правила (после перезапуска WSL)" -ForegroundColor Yellow
    Write-Host "5: Добавить типичные порты (80, 443, 3000, 8080, и др.)" -ForegroundColor Yellow
    Write-Host "Q: Выход" -ForegroundColor Yellow
    Write-Host ""
}

# Основной цикл программы
do {
    Show-Menu
    $choice = Read-Host "Выберите действие"
    
    switch ($choice) {
        "1" {
            Show-ProxiedPorts
            Write-Host "`nНажмите любую клавишу для возврата в меню..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "2" {
            $port = Read-Host "Введите номер порта для проксирования"
            if ($port -match '^\d+$') {
                Add-PortProxy -Port ([int]$port)
            } else {
                Write-Host "Некорректный номер порта" -ForegroundColor Red
            }
            Write-Host "`nНажмите любую клавишу для возврата в меню..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "3" {
            $port = Read-Host "Введите номер порта для удаления"
            if ($port -match '^\d+$') {
                Remove-PortProxy -Port ([int]$port)
            } else {
                Write-Host "Некорректный номер порта" -ForegroundColor Red
            }
            Write-Host "`nНажмите любую клавишу для возврата в меню..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "4" {
            Update-AllPortProxies
            Write-Host "`nНажмите любую клавишу для возврата в меню..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "5" {
            Add-CommonPorts
            Write-Host "`nНажмите любую клавишу для возврата в меню..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
} until ($choice -eq 'q' -or $choice -eq 'Q')

Write-Host "Работа скрипта завершена." -ForegroundColor Cyan
