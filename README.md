# Diagnóstico de conectividad (PowerShell)

Monitoreo liviano de red para Windows: revisa una lista de hosts y servicios, guarda el historial y avisa por correo **solo cuando algo cambia de estado**.

## Qué hace

- Lee los equipos a revisar desde `Objetivos.csv` (nombre, host, puerto), sin tocar el código.
- Prueba **ping** (latencia) y **puerto TCP** de cada uno y los clasifica como `OK`, `DEGRADADO` (responde ping pero el puerto no) o `CAIDO`.
- Si un host no responde, ejecuta **traceroute** automáticamente para ver dónde se corta.
- Genera un **reporte HTML** con semáforo de colores.
- Guarda un **historial CSV** y `ReporteSLA.ps1` calcula el **% de uptime (SLA)** por host.
- Compara con la ejecución anterior y envía **alerta por correo** solo con los cambios (sin spam).
- Se instala solo como **tarea programada** cada N minutos.

## Archivos

| Archivo | Para qué sirve |
| --- | --- |
| `DiagnosticoConectividad.ps1` | Diagnóstico, reporte HTML, historial, alertas y auto-instalación |
| `Objetivos.csv` | Lista editable de hosts y puertos a monitorear |
| `GuardarCredenciales.ps1` | Guarda el correo y la App Password **cifrados con DPAPI** (no en texto plano) |
| `ReporteSLA.ps1` | Calcula disponibilidad por host a partir del historial |
| `ReporteSistema.ps1` | Reporte del PC (CPU, GPU, RAM, discos, procesos, red) enviado por correo |

## Uso

```powershell
.\GuardarCredenciales.ps1              # una vez: correo y App Password de Gmail
.\DiagnosticoConectividad.ps1          # ejecuta una revisión
.\DiagnosticoConectividad.ps1 -InstallTask 15   # se programa cada 15 minutos
.\ReporteSLA.ps1                       # % de uptime por host
```

## Conceptos aplicados

Monitoreo ICMP y TCP, troubleshooting con traceroute, cálculo de SLA, alertas por cambio de estado, manejo seguro de credenciales (DPAPI / `Export-Clixml`) y automatización con el Programador de tareas de Windows.

> Antes de usarlo contra infraestructura de producción, pide autorización al responsable de la red.
