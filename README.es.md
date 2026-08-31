# CalendarCountdown · Cuenta atrás del calendario

> Un rastreador nativo de fechas importantes para macOS. Apple Calendar sigue siendo la fuente de verdad, mientras que usuarios, widgets y agentes de IA reciben una capa de cuenta atrás clara y portable.

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

## Capturas de pantalla

<p align="center">
  <img src="Documentation/Images/app-window-demo.png" width="900" alt="Demostración de la ventana principal de CalendarCountdown">
</p>

<p align="center">
  <img src="Documentation/Images/widget-demo.png" width="720" alt="Demostración del widget de escritorio de CalendarCountdown">
</p>

<p align="center">
  <img src="Documentation/Images/menu-bar-demo.png" width="420" alt="Demostración de CalendarCountdown en la barra de menús">
</p>

> Todos los calendarios, nombres y fechas de las imágenes son datos ficticios de demostración; no contienen información de usuarios reales.

## Qué es

CalendarCountdown no es otra base de datos de calendarios. Las cuentas, calendarios, eventos y colores siguen bajo el control de Apple Calendar. El proyecto lee y escribe los calendarios autorizados por el usuario mediante EventKit y se centra en que las fechas importantes sean siempre visibles, calculables, exportables y fáciles de automatizar.

## Funciones principales

- Lee calendarios de Apple autorizados y conserva sus cuentas, categorías y colores nativos.
- Sigue cumpleaños, aniversarios, festivos y fechas importantes no recurrentes.
- Admite reglas anuales del calendario gregoriano y lunar chino, incluidos el mes intercalar y la compensación para meses cortos.
- Calcula «hoy», «mañana» y los días restantes con el calendario local del sistema.
- App nativa para macOS, vista en la barra de menús y widget de escritorio con WidgetKit.
- Un anillo azul permanente permite localizar rápidamente la acción de actualizar tanto en la ventana principal como en el menú emergente.
- Añade eventos normales y cumpleaños gregorianos o lunares a un calendario de Apple elegido explícitamente.
- Exporta con un clic todas las fechas importantes que se están siguiendo.
- Binario universal para Macs Apple Silicon e Intel, con macOS 14 o posterior.

## Diseñado para agentes de IA

`calcount` es una CLI local que puede exponerse directamente como herramienta shell de un agente. Todos los comandos estructurados producen JSON sin texto interactivo, y los códigos de salida distinguen errores de uso, falta de autorización del calendario y fallos de ejecución.

Propiedades pensadas para agentes:

- **Lecturas predecibles:** lista calendarios, consulta eventos, obtiene las próximas cuentas atrás y lee el índice de seguimiento.
- **Envoltorios JSON estables:** éxito con `{ "ok": true, "data": ... }`; error con `{ "ok": false, "error": { "code": ..., "message": ... } }`.
- **Escrituras revisables:** hay que indicar el calendario de Apple y las importaciones masivas admiten `--dry-run`.
- **Importación idempotente:** `externalId` evita duplicados cuando un agente reintenta una petición.
- **Contexto portable:** `tracked-events.json` conserva año inicial, sistema de calendario, mes, día, recurrencia, próxima fecha y referencias de Apple Calendar.
- **Local primero:** no requiere servidor ni copia del calendario en la nube; solo accede a los datos de EventKit autorizados en el Mac actual.

Comandos habituales de lectura y exportación:

```bash
./calcount doctor
./calcount calendars list
./calcount events list --days 365
./calcount next --limit 10 --days 3653
./calcount tracking refresh
./calcount tracking list
./calcount tracking export --output tracked-events.json
```

Un agente puede consumir el resultado directamente con `jq`:

```bash
./calcount next --limit 5 | jq '.data[] | {title, eventDate, calendarTitle}'
```

Previsualiza una importación antes de escribir:

```bash
./calcount import /path/to/import.json --dry-run
```

Actualmente, `calcount` ofrece un contrato CLI local. No pretende ser un servidor MCP ni una API remota, pero cualquier framework de agentes que admita herramientas shell puede envolverlo.

## JSON de fechas seguidas

Apple Calendar siempre es la fuente de verdad del contenido de los eventos. `tracked-events.json` no es una segunda base de datos: es un índice versionado y exportable de los elementos visibles en la cuenta atrás.

Cada registro incluye:

- UUID estable, título y tipo: cumpleaños, aniversario, fecha importante u otro.
- Año inicial, mes, día e indicador gregoriano/lunar.
- Frecuencia, calendario de recurrencia y políticas para casos límite lunares.
- Próxima fecha, hora, zona horaria y estado de día completo.
- Fuente, calendario, color e identificadores de Apple Calendar para volver a enlazar.
- Modo de seguimiento, fecha de inicio y estado fijado.

Consulta el ejemplo anónimo completo en [tracked-events.example.json](Documentation/tracked-events.example.json).

## Instalación

Versión actual: **1.0.0**

1. [Descarga CalendarCountdown-1.0.0-macos-universal.dmg desde GitHub Releases](https://github.com/MyKWK/CalendarCountdown/releases/download/v1.0.0/CalendarCountdown-1.0.0-macos-universal.dmg).
2. Arrastra CalendarCountdown a Aplicaciones.
3. Inicia la app y concede acceso completo a Apple Calendar.

La versión 1.0.0 usa actualmente una firma ad-hoc; no está firmada con Apple Developer ID ni notarizada. En el primer inicio puede ser necesario hacer Control-clic en la app desde Finder y elegir Abrir.

## Compilar desde el código fuente

Requiere macOS 14+, Xcode y [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd Source
./Scripts/bootstrap.sh
./Scripts/build.sh
xcodebuild -project CalendarCountdown.xcodeproj -scheme CalendarCountdown \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
./Scripts/package-dmg.sh
```

## Límites de datos y privacidad

- Los eventos permanecen en Apple Calendar; el proyecto no opera un servicio de calendario propio en la nube.
- Las selecciones y `tracked-events.json` permanecen en el Mac para mostrarse y exportarse por decisión del usuario.
- Las escrituras solo afectan al calendario de Apple elegido explícitamente.
- Los archivos reales de aniversarios del usuario se excluyen mediante `.gitignore` y no deben entrar en el repositorio público ni en la versión distribuida.

## Alcance actual

- Actualmente se admite macOS. La app para iPhone, sus widgets y la sincronización de reglas con CloudKit son trabajo futuro.
- No es un servidor CalDAV ni duplica la jerarquía de cuentas o categorías de Apple Calendar.
- Consulta [Documentation/PRODUCT.md](Documentation/PRODUCT.md) para el contrato detallado de producto y datos.

## Estructura del repositorio

- `Source/`: código Swift, configuración de XcodeGen, pruebas y scripts de compilación.
- `Documentation/`: contrato del producto, instalación y ejemplos JSON anónimos.
- `Releases/1.0.0/`: notas de la versión y suma SHA-256; el DMG se distribuye mediante GitHub Releases.

## Licencia

Este proyecto se publica bajo la [licencia MIT](LICENSE).
