# Diagnóstico de conectividad (PowerShell)

Monitoreo liviano de red para Windows. Revisa una lista de hosts y servicios cada cierto tiempo, guarda el historial, calcula la disponibilidad (SLA) y avisa por correo **solo cuando algo cambia de estado**, para no llenarte de alertas. Pensado para soporte TI y tareas de operación de red.

Funciona en Windows PowerShell 5.1 (el que trae Windows) o PowerShell 7. No necesita instalar nada.

---

## Tabla de contenidos
- [Para qué sirve](#para-qué-sirve)
- [Qué hace, paso a paso](#qué-hace-paso-a-paso)
- [Instalación](#instalación)
- [Uso](#uso)
- [La lista de hosts (Objetivos.csv)](#la-lista-de-hosts-objetivoscsv)
- [Alertas por correo y credenciales](#alertas-por-correo-y-credenciales)
- [Reporte de disponibilidad (SLA)](#reporte-de-disponibilidad-sla)
- [Dejarlo corriendo solo](#dejarlo-corriendo-solo)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Preguntas frecuentes](#preguntas-frecuentes)
- [Conceptos aplicados](#conceptos-aplicados)
- [Aviso](#aviso)

---

## Para qué sirve

Cuando administras una red necesitas saber **si los equipos importantes están arriba** (el router, el servidor, el firewall, la VPN) y enterarte apenas uno se cae, no horas después. Este script revisa esa lista a intervalos regulares, deja un reporte visual, lleva el historial para calcular cuánto tiempo estuvo disponible cada equipo y te manda un correo solo cuando un host **cambia** de estado (se cayó o volvió). Así tienes un monitoreo simple sin montar un servidor dedicado.

---

## Qué hace, paso a paso

1. **Lee los equipos** a revisar desde `Objetivos.csv` (nombre, host, puerto), sin tocar el código.
2. **Prueba cada uno**:
   - **Ping** (ICMP) para medir si responde y con qué latencia.
   - **Puerto TCP** para confirmar que el servicio está escuchando (por ejemplo 80, 443, 587).
3. **Clasifica el estado**:
   - `OK` → responde ping y el puerto está abierto.
   - `DEGRADADO` → responde ping pero el puerto no (o el ping está bloqueado pero el servicio sí responde).
   - `CAIDO` → no responde.
4. Si un host falla, ejecuta **traceroute automáticamente** para ver en qué salto se corta la ruta.
5. Genera un **reporte HTML** con semáforo de colores (verde / amarillo / rojo).
6. Guarda un **historial CSV** de cada revisión.
7. Compara con la revisión anterior y **envía correo solo con los cambios** (sin repetir lo que sigue igual).

---

## Instalación

No hay instalación. Solo necesitas la carpeta con los archivos y Windows (ya trae PowerShell).

> Si Windows bloquea el script (SmartScreen o la política de ejecución), ábrelo desde una consola de PowerShell con `-ExecutionPolicy Bypass`, como se muestra abajo. Son archivos de texto que puedes revisar con el Bloc de notas.

---

## Uso

```powershell
.\GuardarCredenciales.ps1                 # una sola vez: correo y App Password de Gmail
.\DiagnosticoConectividad.ps1             # ejecuta una revisión ahora
.\DiagnosticoConectividad.ps1 -InstallTask 15   # se programa cada 15 minutos
.\ReporteSLA.ps1                          # muestra el % de uptime por host
```

Al terminar una revisión abre el reporte HTML con el estado de todos los equipos.

---

## La lista de hosts (Objetivos.csv)

Ábrelo con Excel o el Bloc de notas. Una fila por equipo:

```csv
Nombre,Host,Puerto
Gateway / Router,192.168.1.1,0
DNS Google,8.8.8.8,0
Servidor Web interno,192.168.1.10,80
Servidor Correo,smtp.gmail.com,587
VPN / Firewall,192.168.1.254,443
```

- **Nombre:** cómo quieres ver el equipo en el reporte.
- **Host:** IP o nombre de dominio.
- **Puerto:** el puerto TCP a revisar. Pon **0** para probar solo ping (sin puerto).

---

## Alertas por correo y credenciales

El correo de la App Password **no se guarda en texto plano**. `GuardarCredenciales.ps1` lo guarda cifrado con **DPAPI** (`Export-Clixml`), atado a tu usuario de Windows, en un archivo que no se sube al repositorio.

Para Gmail necesitas una **App Password** (contraseña de aplicación), no tu clave normal: se genera en la configuración de seguridad de tu cuenta de Google con la verificación en dos pasos activada. El script usa el SMTP de Gmail (`smtp.gmail.com`, puerto 587).

> Si alguna vez una App Password queda escrita en texto plano por error, revócala desde tu cuenta de Google y genera otra.

---

## Reporte de disponibilidad (SLA)

`ReporteSLA.ps1` lee el historial CSV y calcula el **porcentaje de tiempo que cada host estuvo disponible** (lo que en empresas se llama SLA o uptime). Sirve para mostrar, por ejemplo, que un enlace estuvo arriba el 99,8 % del mes.

---

## Dejarlo corriendo solo

`.\DiagnosticoConectividad.ps1 -InstallTask 15` crea una **tarea programada** de Windows que ejecuta la revisión cada 15 minutos (puedes poner otro número). Desde ahí trabaja solo: revisa, actualiza el historial y te avisa si algo cambió.

---

## Estructura del proyecto

| Archivo | Para qué sirve |
| --- | --- |
| `DiagnosticoConectividad.ps1` | Diagnóstico, reporte HTML, historial, alertas y auto-instalación |
| `Objetivos.csv` | Lista editable de hosts y puertos a monitorear |
| `GuardarCredenciales.ps1` | Guarda el correo y la App Password cifrados con DPAPI |
| `ReporteSLA.ps1` | Calcula la disponibilidad (uptime) por host desde el historial |
| `ReporteSistema.ps1` | Reporte del PC (CPU, GPU, RAM, discos, procesos, red) enviado por correo |

---

## Preguntas frecuentes

**Me marca DEGRADADO pero el equipo funciona.** Algunos equipos bloquean el ping (ICMP) por seguridad aunque el servicio TCP esté bien. El estado considera ambas cosas; revisa si el puerto que pusiste es el correcto.

**No me llegan los correos.** Verifica que guardaste una App Password (no tu clave normal) y que la verificación en dos pasos de Google esté activa.

**No quiero alertas, solo el reporte.** No configures las credenciales; igual se genera el reporte HTML y el historial.

---

## Conceptos aplicados

Monitoreo ICMP y TCP, troubleshooting con traceroute, cálculo de SLA/uptime, alertas por cambio de estado (evita el spam), manejo seguro de credenciales (DPAPI / `Export-Clixml`), reportes HTML y automatización con el Programador de tareas de Windows.

---

## Aviso

Úsalo solo en tu propia red o donde tengas autorización. Antes de monitorear infraestructura de producción, pide permiso al responsable de la red: un sondeo no autorizado puede tratarse como un incidente de seguridad.
