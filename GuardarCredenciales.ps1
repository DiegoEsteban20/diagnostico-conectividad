# =========================================================
#  GuardarCredenciales.ps1
#  Corre esto UNA SOLA VEZ para guardar tu Gmail y App Password
#  de forma cifrada (no en texto plano). Queda ligado a tu usuario
#  de Windows en esta PC: nadie mas puede leerlo, ni siquiera copiando
#  el archivo a otra PC.
# =========================================================

$carpeta = Join-Path ([Environment]::GetFolderPath("Desktop")) "ReportesRed"
if (-not (Test-Path $carpeta)) { New-Item -ItemType Directory -Path $carpeta | Out-Null }

$gmailUser = Read-Host "Ingresa tu correo de Gmail (el que envia los reportes)"
$destinatario = Read-Host "Ingresa el correo que va a RECIBIR las alertas"
$appPass = Read-Host "Ingresa tu App Password de Gmail" -AsSecureString

$config = [PSCustomObject]@{
    GmailUser    = $gmailUser
    Destinatario = $destinatario
    AppPass      = $appPass
}

$rutaArchivo = Join-Path $carpeta "credenciales.xml"
$config | Export-Clixml -Path $rutaArchivo

Write-Host ""
Write-Host "Credenciales guardadas de forma cifrada en: $rutaArchivo" -ForegroundColor Green
Write-Host "Ya podes correr DiagnosticoConectividad.ps1 normalmente." -ForegroundColor Green
