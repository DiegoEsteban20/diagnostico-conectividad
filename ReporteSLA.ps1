# =========================================================
#  ReporteSLA.ps1
#  Lee el historial.csv generado por DiagnosticoConectividad.ps1
#  y calcula el % de disponibilidad (uptime) de cada host en el
#  periodo, para armar el reporte de SLA facil y rapido.
#
#  USO:
#    .\ReporteSLA.ps1            -> usa todo el historial disponible
#    .\ReporteSLA.ps1 -Dias 7    -> solo los ultimos 7 dias
# =========================================================

param(
    [int]$Dias = 0   # 0 = todo el historial. Si pones un numero, filtra por esos ultimos dias.
)

$Carpeta = Join-Path ([Environment]::GetFolderPath("Desktop")) "ReportesRed"
$ArchivoHistorial = Join-Path $Carpeta "historial.csv"

if (-not (Test-Path $ArchivoHistorial)) {
    Write-Host "Todavia no hay historial (historial.csv). Corre DiagnosticoConectividad.ps1 unas cuantas veces primero." -ForegroundColor Yellow
    exit
}

$datos = Import-Csv $ArchivoHistorial
$datos = $datos | ForEach-Object { $_.FechaHora = [datetime]$_.FechaHora; $_ }

if ($Dias -gt 0) {
    $limite = (Get-Date).AddDays(-$Dias)
    $datos = $datos | Where-Object { $_.FechaHora -ge $limite }
}

$porHost = $datos | Group-Object Host

$filas = ""
foreach ($grupo in $porHost) {
    $total = $grupo.Count
    $ok = ($grupo.Group | Where-Object { $_.Estado -eq "OK" }).Count
    $degradado = ($grupo.Group | Where-Object { $_.Estado -eq "DEGRADADO" }).Count
    $caido = ($grupo.Group | Where-Object { $_.Estado -eq "CAIDO" }).Count
    $uptime = if ($total -gt 0) { [math]::Round(($ok / $total) * 100, 2) } else { 0 }
    $nombre = ($grupo.Group | Select-Object -First 1).Nombre

    $colorUptime = if ($uptime -ge 99) { "#155724" } elseif ($uptime -ge 95) { "#856404" } else { "#721c24" }

    $filas += @"
<tr>
    <td>$nombre</td><td>$($grupo.Name)</td><td>$total</td>
    <td>$ok</td><td>$degradado</td><td>$caido</td>
    <td style="color:$colorUptime; font-weight:bold;">$uptime%</td>
</tr>
"@
}

$periodoTexto = if ($Dias -gt 0) { "Ultimos $Dias dias" } else { "Todo el historial disponible" }

$html = @"
<html><head><meta charset="UTF-8"><style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; }
table { border-collapse: collapse; width: 100%; margin-top: 15px; }
th, td { border: 1px solid #ccc; padding: 8px; text-align: left; font-size: 14px; }
th { background-color: #333; color: white; }
</style></head><body>
<h1>Reporte de Disponibilidad (SLA)</h1>
<p>Periodo: $periodoTexto &nbsp;|&nbsp; Generado: $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>
<table>
<tr><th>Nombre</th><th>Host</th><th>Mediciones</th><th>OK</th><th>Degradado</th><th>Caido</th><th>% Uptime</th></tr>
$filas
</table>
</body></html>
"@

$archivoSalida = Join-Path $Carpeta "SLA_$(Get-Date -Format 'yyyy-MM-dd_HH-mm').html"
$html | Out-File -FilePath $archivoSalida -Encoding UTF8

Write-Host "Reporte SLA generado: $archivoSalida" -ForegroundColor Green
Invoke-Item $archivoSalida
