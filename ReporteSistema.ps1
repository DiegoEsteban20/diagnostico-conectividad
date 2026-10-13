# =========================================================
#  ReporteSistema.ps1
#  Recolecta info del PC (CPU, GPU, RAM, discos, apps instaladas)
#  y la envia por correo (Gmail) para que la recibas en el celu.
# =========================================================

# ---------- CONFIGURACION ----------
# Las credenciales NO van escritas en el script: se leen cifradas desde
# credenciales.xml, que crea GuardarCredenciales.ps1 (DPAPI, solo tu usuario).
$ArchivoCredenciales = Join-Path ([Environment]::GetFolderPath("Desktop")) "ReportesRed\credenciales.xml"
if (-not (Test-Path $ArchivoCredenciales)) {
    Write-Host "Primero ejecuta GuardarCredenciales.ps1 para configurar el correo." -ForegroundColor Yellow
    exit 1
}
$cfg          = Import-Clixml $ArchivoCredenciales
$GmailUser    = $cfg.GmailUser
$Destinatario = $cfg.Destinatario
$Asunto       = "Reporte de sistema - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
# -----------------------------------

function Get-InstalledApps {
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne "" } |
        Select-Object DisplayName, DisplayVersion, Publisher |
        Sort-Object DisplayName -Unique
}

function Get-CpuTemp {
    try {
        $t = Get-CimInstance -Namespace "root/wmi" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        $celsius = ($t | ForEach-Object { ($_.CurrentTemperature / 10) - 273.15 })
        return ($celsius | Measure-Object -Average).Average
    } catch {
        return $null
    }
}

function Get-TopProcesses {
    param([string]$Metric = "CPU", [int]$Top = 5)
    if ($Metric -eq "CPU") {
        Get-Process | Where-Object { $_.CPU -ne $null } | Sort-Object CPU -Descending | Select-Object -First $Top Name, Id, @{N='CPU(s)';E={[math]::Round($_.CPU,1)}}, @{N='RAM(MB)';E={[math]::Round($_.WorkingSet/1MB,1)}}
    } else {
        Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First $Top Name, Id, @{N='CPU(s)';E={[math]::Round($_.CPU,1)}}, @{N='RAM(MB)';E={[math]::Round($_.WorkingSet/1MB,1)}}
    }
}

Write-Host "Recolectando informacion del sistema..."

# ---- Info general del sistema ----
$os        = Get-CimInstance Win32_OperatingSystem
$cs        = Get-CimInstance Win32_ComputerSystem
$cpu       = Get-CimInstance Win32_Processor
$gpu       = Get-CimInstance Win32_VideoController
$ramTotal  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
$discos    = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$apps      = Get-InstalledApps
$cpuTemp   = Get-CpuTemp
$topCpu    = Get-TopProcesses -Metric "CPU" -Top 5
$topRam    = Get-TopProcesses -Metric "RAM" -Top 5

# ---- Uso de red (medido durante 1 segundo) ----
$netAntes = Get-NetAdapterStatistics | Where-Object { $_.ReceivedBytes -gt 0 -or $_.SentBytes -gt 0 }
Start-Sleep -Seconds 1
$netDespues = Get-NetAdapterStatistics | Where-Object { $_.ReceivedBytes -gt 0 -or $_.SentBytes -gt 0 }

# ---- Armar el cuerpo del correo en HTML ----
$html = @"
<h2>Reporte del sistema - $env:COMPUTERNAME</h2>
<p><b>Fecha:</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>

<h3>Sistema Operativo</h3>
<ul>
  <li><b>SO:</b> $($os.Caption) ($($os.OSArchitecture))</li>
  <li><b>Version:</b> $($os.Version)</li>
  <li><b>Ultimo arranque:</b> $($os.LastBootUpTime)</li>
</ul>

<h3>Procesador (CPU)</h3>
<ul>
"@
foreach ($c in $cpu) {
    $html += "<li>$($c.Name) - $($c.NumberOfCores) nucleos / $($c.NumberOfLogicalProcessors) hilos</li>"
}

$html += "</ul><h3>Tarjeta grafica (GPU)</h3><ul>"
foreach ($g in $gpu) {
    $vram = if ($g.AdapterRAM) { [math]::Round($g.AdapterRAM / 1GB, 2) } else { "N/D" }
    $html += "<li>$($g.Name) - VRAM aprox: $vram GB</li>"
}

$html += "</ul><h3>Temperatura</h3><ul>"
if ($cpuTemp) {
    $html += "<li>Promedio zonas termicas: $([math]::Round($cpuTemp,1)) &deg;C</li>"
} else {
    $html += "<li>No disponible en este equipo (Windows no expone el sensor por WMI en la mayoria de las PCs/laptops modernas). Para temperatura real de CPU/GPU se necesita un programa como LibreHardwareMonitor - si queres te ayudo a integrarlo.</li>"
}
$html += "</ul>"

$html += "<h3>Memoria RAM</h3><ul><li>Total: $ramTotal GB</li></ul>"

$html += "<h3>Discos</h3><ul>"
foreach ($d in $discos) {
    $libre  = [math]::Round($d.FreeSpace / 1GB, 2)
    $total  = [math]::Round($d.Size / 1GB, 2)
    $html += "<li>$($d.DeviceID) - Libre: $libre GB / Total: $total GB</li>"
}
$html += "</ul>"

$html += "<h3>Aplicaciones instaladas ($($apps.Count))</h3><ul>"
foreach ($a in $apps) {
    $html += "<li>$($a.DisplayName) $($a.DisplayVersion)</li>"
}
$html += "</ul>"

$html += "<h3>Uso de red (ultimo segundo)</h3><ul>"
foreach ($n1 in $netDespues) {
    $n0 = $netAntes | Where-Object { $_.Name -eq $n1.Name }
    if ($n0) {
        $rxKBs = [math]::Round(($n1.ReceivedBytes - $n0.ReceivedBytes) / 1KB, 1)
        $txKBs = [math]::Round(($n1.SentBytes - $n0.SentBytes) / 1KB, 1)
        $html += "<li>$($n1.Name) - Descarga: $rxKBs KB/s | Subida: $txKBs KB/s</li>"
    }
}
$html += "</ul>"

$html += "<h3>Top 5 procesos por CPU</h3><table border='1' cellpadding='4' cellspacing='0'><tr><th>Proceso</th><th>PID</th><th>CPU(s)</th><th>RAM(MB)</th></tr>"
foreach ($p in $topCpu) {
    $html += "<tr><td>$($p.Name)</td><td>$($p.Id)</td><td>$($p.'CPU(s)')</td><td>$($p.'RAM(MB)')</td></tr>"
}
$html += "</table>"

$html += "<h3>Top 5 procesos por RAM</h3><table border='1' cellpadding='4' cellspacing='0'><tr><th>Proceso</th><th>PID</th><th>CPU(s)</th><th>RAM(MB)</th></tr>"
foreach ($p in $topRam) {
    $html += "<tr><td>$($p.Name)</td><td>$($p.Id)</td><td>$($p.'CPU(s)')</td><td>$($p.'RAM(MB)')</td></tr>"
}
$html += "</table>"

# ---- Enviar el correo ----
Write-Host "Enviando correo..."

$cred       = New-Object System.Management.Automation.PSCredential($GmailUser, $cfg.AppPass)

try {
    Send-MailMessage -From $GmailUser `
        -To $Destinatario `
        -Subject $Asunto `
        -Body $html `
        -BodyAsHtml `
        -SmtpServer "smtp.gmail.com" `
        -Port 587 `
        -UseSsl `
        -Credential $cred

    Write-Host "Correo enviado correctamente a $Destinatario"
}
catch {
    Write-Host "Error al enviar el correo: $_"
}