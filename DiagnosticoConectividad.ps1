# =========================================================
#  DiagnosticoConectividad.ps1
#
#  - Lee la lista de hosts desde Objetivos.csv (editable sin tocar el script)
#  - Prueba ping + puerto (si corresponde) a cada uno
#  - Si un host no responde, corre traceroute automaticamente
#  - Genera reporte HTML con semaforo de colores
#  - Guarda historial en CSV (para calcular % uptime / SLA despues)
#  - Compara contra la corrida anterior: si algo cambio de estado
#    (se cayo o se recupero), manda un correo de alerta SOLO con
#    los cambios (no spamea si todo sigue igual)
#  - Se puede instalar como tarea programada para correr solo
#
#  USO:
#    .\DiagnosticoConectividad.ps1                 -> corre una vez
#    .\DiagnosticoConectividad.ps1 -InstallTask 15 -> se instala para
#                                                      correr cada 15 min
# =========================================================

param(
    [int]$InstallTask = 0   # Minutos de intervalo. Si es 0, no instala nada.
)

$EscritorioReal = [Environment]::GetFolderPath("Desktop")
$Carpeta = Join-Path $EscritorioReal "ReportesRed"
$ArchivoObjetivos = "$PSScriptRoot\Objetivos.csv"
$ArchivoEstadoAnterior = Join-Path $Carpeta "estado_anterior.json"
$ArchivoHistorial      = Join-Path $Carpeta "historial.csv"
$ArchivoCredenciales   = Join-Path $Carpeta "credenciales.xml"

if (-not (Test-Path $Carpeta)) { New-Item -ItemType Directory -Path $Carpeta | Out-Null }

# ---------- Auto-instalacion como tarea programada ----------
if ($InstallTask -gt 0) {
    $accion    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $disparador = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $InstallTask) -RepetitionDuration ([TimeSpan]::MaxValue)
    $config    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName "DiagnosticoConectividad" -Action $accion -Trigger $disparador -Settings $config -Force `
        -Description "Monitoreo de conectividad automatico cada $InstallTask minutos"
    Write-Host "Tarea programada instalada: se va a ejecutar cada $InstallTask minutos, incluso si cerras sesion." -ForegroundColor Green
    Write-Host "Para desinstalarla despues: Unregister-ScheduledTask -TaskName 'DiagnosticoConectividad'"
    exit
}

# ---------- Cargar objetivos ----------
if (-not (Test-Path $ArchivoObjetivos)) {
    Write-Host "No se encontro Objetivos.csv. Tiene que estar en la misma carpeta que este script." -ForegroundColor Red
    exit
}
$Objetivos = Import-Csv $ArchivoObjetivos

# ---------- Cargar credenciales (si existen) ----------
$credencialesDisponibles = $false
if (Test-Path $ArchivoCredenciales) {
    $cfg = Import-Clixml $ArchivoCredenciales
    $credencialesDisponibles = $true
}

Write-Host "Iniciando diagnostico de conectividad - $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Cyan

$resultados = @()
$fechaCorrida = Get-Date

foreach ($obj in $Objetivos) {
    $puertoNum = [int]$obj.Puerto
    Write-Host "Probando $($obj.Nombre) ($($obj.Host))..."

    $ping = Test-Connection -ComputerName $obj.Host -Count 2 -ErrorAction SilentlyContinue
    $pingOk = $null -ne $ping
    $latencia = if ($pingOk) { [math]::Round(($ping | Measure-Object ResponseTime -Average).Average, 0) } else { $null }

    $puertoOk = $null
    if ($puertoNum -gt 0) {
        $testPuerto = Test-NetConnection -ComputerName $obj.Host -Port $puertoNum -WarningAction SilentlyContinue
        $puertoOk = $testPuerto.TcpTestSucceeded
    }

    $traceroute = $null
    if (-not $pingOk) {
        Write-Host "  -> Sin respuesta, corriendo traceroute..." -ForegroundColor Yellow
        $traceroute = (tracert -h 15 -w 500 $obj.Host) -join "`n"
    }

    if ($pingOk -and ($puertoNum -eq 0 -or $puertoOk)) {
        $estado = "OK"
    } elseif ($pingOk -and -not $puertoOk) {
        $estado = "DEGRADADO"
    } else {
        $estado = "CAIDO"
    }

    $resultados += [PSCustomObject]@{
        Nombre     = $obj.Nombre
        Host       = $obj.Host
        Puerto     = if ($puertoNum -gt 0) { $puertoNum } else { "-" }
        Ping       = if ($pingOk) { "OK ($latencia ms)" } else { "Sin respuesta" }
        Latencia   = $latencia
        PuertoTest = if ($puertoNum -gt 0) { if ($puertoOk) { "Abierto" } else { "Cerrado/Filtrado" } } else { "N/A" }
        Estado     = $estado
        Traceroute = $traceroute
    }
}

# ---------- Guardar en historial CSV (para SLA / uptime) ----------
foreach ($r in $resultados) {
    [PSCustomObject]@{
        FechaHora = $fechaCorrida.ToString("yyyy-MM-dd HH:mm:ss")
        Nombre    = $r.Nombre
        Host      = $r.Host
        Estado    = $r.Estado
        Latencia  = $r.Latencia
    } | Export-Csv -Path $ArchivoHistorial -Append -NoTypeInformation -Encoding UTF8
}

# ---------- Comparar con la corrida anterior para detectar cambios ----------
$cambios = @()
$estadoAnterior = @{}
if (Test-Path $ArchivoEstadoAnterior) {
    $tmp = Get-Content $ArchivoEstadoAnterior -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($tmp) {
        $tmp.PSObject.Properties | ForEach-Object { $estadoAnterior[$_.Name] = $_.Value }
    }
}

$estadoActual = @{}
foreach ($r in $resultados) {
    $estadoActual[$r.Host] = $r.Estado
    if ($estadoAnterior.ContainsKey($r.Host) -and $estadoAnterior[$r.Host] -ne $r.Estado) {
        $cambios += [PSCustomObject]@{
            Nombre = $r.Nombre
            Host   = $r.Host
            De     = $estadoAnterior[$r.Host]
            A      = $r.Estado
        }
    }
}
$estadoActual | ConvertTo-Json | Out-File -FilePath $ArchivoEstadoAnterior -Encoding UTF8

# ---------- Armar HTML del reporte ----------
$totalOk = ($resultados | Where-Object { $_.Estado -eq "OK" }).Count
$totalDeg = ($resultados | Where-Object { $_.Estado -eq "DEGRADADO" }).Count
$totalCaido = ($resultados | Where-Object { $_.Estado -eq "CAIDO" }).Count

$filas = ""
foreach ($r in $resultados) {
    $color = switch ($r.Estado) {
        "OK"        { "#d4edda" }
        "DEGRADADO" { "#fff3cd" }
        "CAIDO"     { "#f8d7da" }
    }
    $traceHtml = ""
    if ($r.Traceroute) {
        $traceEscaped = $r.Traceroute -replace "<", "&lt;" -replace ">", "&gt;"
        $traceHtml = "<pre style='background:#f5f5f5; padding:8px; font-size:12px;'>$traceEscaped</pre>"
    }
    $filas += @"
<tr style="background-color:$color;">
    <td>$($r.Nombre)</td><td>$($r.Host)</td><td>$($r.Puerto)</td>
    <td>$($r.Ping)</td><td>$($r.PuertoTest)</td><td><b>$($r.Estado)</b></td>
</tr>
$(if ($traceHtml) { "<tr style='background-color:$color;'><td colspan='6'><b>Traceroute:</b>$traceHtml</td></tr>" })
"@
}

$fecha = Get-Date -Format "yyyy-MM-dd_HH-mm"
$archivoSalida = Join-Path $Carpeta "Diagnostico_$fecha.html"

$html = @"
<html><head><meta charset="UTF-8"><style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; }
table { border-collapse: collapse; width: 100%; margin-top: 15px; }
th, td { border: 1px solid #ccc; padding: 8px; text-align: left; font-size: 14px; }
th { background-color: #333; color: white; }
.resumen { margin-top: 5px; font-size: 15px; }
.ok { color: #155724; font-weight: bold; } .deg { color: #856404; font-weight: bold; } .caido { color: #721c24; font-weight: bold; }
</style></head><body>
<h1>Diagnostico de Conectividad</h1>
<p class="resumen">Fecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm') &nbsp;|&nbsp;
<span class="ok">OK: $totalOk</span> &nbsp;|&nbsp;
<span class="deg">Degradado: $totalDeg</span> &nbsp;|&nbsp;
<span class="caido">Caido: $totalCaido</span></p>
<table><tr><th>Nombre</th><th>Host</th><th>Puerto</th><th>Ping</th><th>Test Puerto</th><th>Estado</th></tr>
$filas</table></body></html>
"@
$html | Out-File -FilePath $archivoSalida -Encoding UTF8

Write-Host ""
Write-Host "Reporte guardado en: $archivoSalida" -ForegroundColor Green
Write-Host "OK: $totalOk | Degradado: $totalDeg | Caido: $totalCaido"

# ---------- Alertar solo si hubo cambios de estado ----------
if ($cambios.Count -gt 0) {
    Write-Host ""
    Write-Host "CAMBIOS DETECTADOS:" -ForegroundColor Magenta
    foreach ($c in $cambios) { Write-Host "  $($c.Nombre) ($($c.Host)): $($c.De) -> $($c.A)" -ForegroundColor Magenta }

    if ($credencialesDisponibles) {
        $filasCambio = ""
        foreach ($c in $cambios) {
            $filasCambio += "<li><b>$($c.Nombre)</b> ($($c.Host)): $($c.De) &rarr; <b>$($c.A)</b></li>"
        }
        $htmlAlerta = "<h2>Cambios de estado detectados</h2><ul>$filasCambio</ul><p>Ver reporte completo adjunto o en el equipo.</p>"

        $securePass = $cfg.AppPass
        $cred = New-Object System.Management.Automation.PSCredential($cfg.GmailUser, $securePass)
        try {
            Send-MailMessage -From $cfg.GmailUser -To $cfg.Destinatario `
                -Subject "[ALERTA RED] Cambios de estado - $(Get-Date -Format 'dd/MM HH:mm')" `
                -Body $htmlAlerta -BodyAsHtml -SmtpServer "smtp.gmail.com" -Port 587 -UseSsl `
                -Credential $cred -Attachments $archivoSalida
            Write-Host "Alerta enviada por correo." -ForegroundColor Green
        } catch {
            Write-Host "Error al enviar la alerta: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "(No hay credenciales configuradas - correr GuardarCredenciales.ps1 para habilitar alertas por correo)" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "Sin cambios respecto a la corrida anterior. No se envia alerta." -ForegroundColor DarkGray
}
