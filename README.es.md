[English](README.md) · **Español** · [Français](README.fr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [한국어](README.ko.md) · [中文](README.zh.md)

# Open Steps

*Traducción breve del [README en inglés](README.md). Última actualización: 30 de septiembre de 2026. Las mediciones, el funcionamiento interno y las notas para contribuidores están solo en la versión en inglés. Se tradujo con ayuda de IA y todavía no la ha revisado un hablante nativo. Si ve un error, corríjalo con un pull request.*

**Habilidades que mantienen el desarrollo abierto para la persona que lo dirige: las sesiones, las decisiones, los siguientes pasos, el panorama completo, todo en lenguaje claro.**

Habilidades de agente en lenguaje claro para Claude Code, Codex, Cursor y Gemini CLI.

Por [Pavlo Kharmanskyi](https://github.com/kharmanskyi).

## Por qué existe

No soy ingeniero. Llevo veinte años haciendo productos desde el lado del producto, y hoy mi empresa tiene más de 50 desarrolladores. En paralelo empecé a construir un producto por mi cuenta, con un agente y sin ingenieros. Casi enseguida me topé con un muro. El agente trabaja bien, y luego me cuenta lo que hizo con hashes de commits y jerga, y yo no puedo saber si terminamos o no. El trabajo en sí está bien hecho. Lo que pasa es que nadie le enseñó al agente a hablar con alguien que no lee código.

Este paquete se lo enseña. No escribe código por el agente ni revisa el código en su lugar. Cambia lo que el agente le dice a usted en unos pocos momentos importantes, y le pide pruebas donde antes bastaba con decir "listo".

## Qué hacen las habilidades

| Habilidad | Qué hace | Cuándo se activa |
|---|---|---|
| `os-done-or-not` | Un informe de una pantalla con veredicto: hecho o no, qué se necesita de usted, si hay deudas nuevas, si se puede cerrar. Cada "sí" viene con su prueba | El trabajo termina, o usted pregunta cómo fue |
| `os-step-by-step` | Pasos numerados que puede seguir una persona sin formación técnica. Primero el agente tiene que intentarlo todo por su cuenta y pedir solo lo que de verdad necesita de usted | El agente necesita que usted ejecute, pegue, haga clic, apruebe o pruebe algo |
| `os-ask-simple` | La pregunta en palabras claras, lo que costará más adelante y una recomendación destacada | El agente tiene una pregunta u opciones para usted |
| `os-what-could-go-wrong` | Da por hecho que la decisión ya fracasó y busca por qué. Lo hace un agente nuevo que no participó en la decisión. Termina con un solo veredicto | Está a punto de decidirse algo difícil de deshacer: un contrato, una compra, una migración, un lanzamiento |
| `os-whats-next` | Fusiona (merge) lo que está verificado y listo, luego recomienda la siguiente tarea y explica por qué en palabras claras | Usted pregunta qué falta o qué hacer ahora |
| `os-check-work` | No se fía del informe de otra sesión. Comprueba cada afirmación con lo que pasó de verdad y dice qué hacer al respecto | Otra sesión dice que terminó |
| `os-say-simple` | Reescribe cualquier texto en palabras claras sin perder hechos ni malas noticias. Pida un número y recibirá exactamente esa cantidad de puntos | Cualquier texto suena a ingeniería: un informe, un comentario, un error, la propia respuesta del agente |
| `os-big-picture` | Mantiene un archivo, `BIG-PICTURE.md`: qué es el producto, cada función y hasta dónde llegó, qué partes nadie toca desde hace tiempo, qué está en cola. Si usted ya usa un gestor de tareas, ofrece abrir la cola como tareas allí | Usted pregunta en qué punto está el proyecto, o se acaba de escribir un informe de sesión |

Las habilidades piden al agente que responda en el idioma en que usted le habla. El código, los nombres de archivo y los comandos quedan en inglés.

## Instalación

**Antes de instalar, sepa esto: el paquete fusiona (merge) por su cuenta un pull request si sus comprobaciones están en verde y su revisión está aprobada.** Antes de fusionarlo, el agente lo verifica una vez más. En Claude Code la fusión ocurre sin pedir permiso. En Codex, Cursor y Gemini CLI el comando de fusión pasa por los ajustes de permisos de cada herramienta, según su documentación. Dos cosas detienen una fusión: una afirmación que no supera la verificación, o una nota en la tarea que diga que solo se fusiona por orden. Si quiere fusiones solo por orden suya, escríbalo en su archivo de instrucciones permanentes: `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md` o el `AGENTS.md` del proyecto en Cursor.

El paquete se instala en Claude Code, Codex, Cursor y Gemini CLI. En Claude Code un plugin conecta las habilidades y los dos hooks con un comando. En Codex, Cursor y Gemini CLI un comando de copia instala las habilidades, y los hooks se configuran a mano en cada herramienta. Qué se ejecutó en cada herramienta, y qué viene de su documentación, está en la [tabla del README en inglés](README.md#what-was-run-on-each-tool).

### Primero, para cualquier herramienta

Descargue el repositorio:

```bash
git clone https://github.com/kharmanskyi/open-steps.git
```

Todos los comandos siguientes se ejecutan desde la carpeta donde lo descargó, la que ahora contiene `open-steps/`, no desde dentro de ella.

En las cuatro herramientas conviene añadir una pieza a mano: el bloque de reglas, en el archivo que la herramienta lee como instrucciones permanentes. Las habilidades son algo que el modelo decide usar. Los hooks se lo recuerdan; en Claude Code el bloque convierte el recordatorio en regla. Más abajo se indica dónde va el bloque en cada herramienta.

Los informes se guardan fuera de sus repositorios, en `~/.claude/open-steps/reports/<project>/`, así que no entran en sus commits.

### Claude Code

Instale el paquete como plugin:

```bash
claude plugin marketplace add ./open-steps && claude plugin install open-steps@open-steps
```

Listo: las habilidades y los dos hooks quedan conectados. Para ver qué se instaló:

```bash
claude plugin details open-steps
```

El bloque de reglas va en su `~/.claude/CLAUDE.md`, donde sobrevive a las conversaciones largas. Un comando, seguro de repetir:

```bash
grep -q 'os-done-or-not' ~/.claude/CLAUDE.md 2>/dev/null || cat open-steps/docs/routing-block.md >> ~/.claude/CLAUDE.md
```

Más adelante, para revisar toda la instalación y no solo el plugin, escriba `/open-steps:os-install-check` en Claude Code. Dice qué está conectado y qué no, y escribe "no comprobado" donde no pudo mirar.

### Codex CLI, Cursor CLI y Gemini CLI

Estas tres herramientas leen las habilidades de `~/.agents/skills/`. Un comando las instala para las tres:

```bash
mkdir -p ~/.agents/skills && cp -R open-steps/skills/os-* ~/.agents/skills/
```

El bloque de reglas va en el archivo que cada herramienta lee como instrucciones permanentes:

| Herramienta | Dónde va el bloque |
|---|---|
| Codex | `~/.codex/AGENTS.md` |
| Cursor | `AGENTS.md` en la raíz del proyecto |
| Gemini CLI | `~/.gemini/GEMINI.md` |

El comando para cada archivo, seguro de repetir, está en [docs/other-agents.md](docs/other-agents.md#the-routing-block) (en inglés). Allí está también la configuración de los hooks: cada herramienta tiene la suya y se hace a mano.

Para revisar la instalación: `bash open-steps/doctor.sh`. Mira las carpetas de habilidades, el bloque de reglas y los ajustes de hooks de cada herramienta que encuentra, y escribe "no comprobado" donde no pudo mirar. Todavía no comprueba en qué evento está cada hook.

## Actualizar y quitar

**Claude Code.** Para actualizar: `git pull` dentro de `open-steps/`, luego `claude plugin update open-steps@open-steps`. Hacen falta las dos mitades: el plugin se actualiza desde su carpeta, no desde GitHub, y los archivos llegan a la copia instalada solo cuando cambia el número de versión. Para quitarlo: `claude plugin uninstall open-steps`, y luego borre el bloque de su `CLAUDE.md`.

**Codex CLI, Cursor CLI y Gemini CLI.** Para actualizar: `git pull` dentro de `open-steps/`, luego repita el comando de copia. Es una copia, así que las habilidades instaladas no cambian hasta que lo repita. Para quitarlas (estos pasos aún no se han ejecutado): borre las carpetas `os-*` de `~/.agents/skills/`, quite el bloque del archivo de instrucciones de la herramienta y las dos entradas de hooks de su archivo de ajustes (`~/.codex/config.toml`, `~/.cursor/hooks.json` o `~/.gemini/settings.json`).

## Licencia

MIT. El paquete es público y las contribuciones son bienvenidas: las reglas están en [CONTRIBUTING.md](CONTRIBUTING.md) (en inglés).

Open Steps is an independent open-source project, not affiliated with or endorsed by the makers of the tools it runs on. Claude and Claude Code are trademarks of Anthropic. All other trademarks, including Codex, Cursor and Gemini, are the property of their respective owners.
