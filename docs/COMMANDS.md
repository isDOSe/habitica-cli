# Referencia de comandos

Guía completa de `h` / `habitica`. Los índices (`<ref>`) siempre apuntan a la **última lista mostrada**; también aceptan UUID, alias o un fragmento único del texto.

```powershell
h                      # dashboard
h help                 # ayuda rapida
h help tasks           # ayuda por tema
h <comando> --help     # ayuda del comando
```

---

## Referencias de tarea

```text
3                       índice de la última lista
11111111-1111-...       UUID
leche                   alias
"comprar leche"         texto exacto o fragmento único
```

---

## Tareas

| Comando | Acción |
|---|---|
| `h` / `h today` | Dashboard de hoy |
| `h ls` | Todas las tareas, agrupadas (solo diarias activas hoy) |
| `h ls --all` | Todas, incluidas las diarias que no tocan hoy |
| `h todo` | Tareas pendientes |
| `h dailies` | Diarias activas hoy |
| `h dailies --all` | Todas las diarias, incluidas las que no tocan hoy |
| `h habits` | Hábitos |
| `h rewards` | Recompensas |
| `h completed` | To-Dos completados |
| `h show <ref>` | Detalle |
| `h add "texto"` | Crear |
| `h edit <ref>` | Editar |
| `h done <ref>` | Completar / score up |
| `h done 1,2,3` | Completar varias en un solo comando (también `h done 1 2 3`) |
| `h done <ref> --dry-run` | Ver cuál se completaría sin tocarla |
| `h which <ref>` | Ver a qué tarea resuelve una referencia |
| `h undo <ref>` | Deshacer / score down |
| `h up <ref>` / `h down <ref>` | Puntuar hábito |
| `h buy <ref>` | Comprar recompensa |
| `h move <ref> <pos>` | Reordenar (`0` = principio, `-1` = final) |
| `h rm <ref> --yes` | Eliminar |
| `h clear --yes` | Borrar To-Dos completados |

### Crear

```powershell
h add "Comprar leche"
h add "Comprar leche" --notes "Entera" --priority media
h add "Comprar leche" --due hoy|manana|+3d|2026-12-31|31/12
h add "Comprar leche" --tag casa --tag compras
h add "Comprar leche" --check "Revisar nevera" --check "Llevar bolsa"
h add "Comprar leche" --alias leche

h add "Ejercicio" --daily --frequency daily --every 2
h add "Ejercicio" --daily --frequency weekly --days lun,mie,vie
h add "Ejercicio" --daily --frequency monthly
h add "Ejercicio" --daily --frequency yearly

h add "Beber agua" --habit --up
h add "Procrastinar" --habit --down
h add "Beber agua" --habit            # ambas direcciones

h add "Ver una pelicula" --reward --cost 20
```

Azúcar dentro del texto:

```powershell
h add "Comprar leche #casa !!"     # etiqueta casa + prioridad media
h add "Pagar la luz due:manana"
```

### Editar

```powershell
h edit 3 --text "Nuevo titulo"
h edit 3 --notes "Nuevas notas"
h edit 3 --priority dificil
h edit 3 --due +5d
h edit 3 --clear-due
h edit 3 --completed
h edit 3 --reopen
h edit 3 --cost 30
h edit 3 --frequency weekly --days lun,vie
h edit 3 --up
```

### Prioridades

`trivial`, `facil`, `media`, `dificil` (también `easy`, `medium`, `hard`, `0.1`, `1`, `1.5`, `2`).

---

## Checklists

```powershell
h check 3                         # ver
h check add 3 "Revisar anexos"    # agregar
h tick 3 2                        # alternar item #2 (da XP)
h untick 3 2                      # desmarcar
h check edit 3 2 "Texto nuevo"    # editar
h check rm 3 2                    # eliminar
```

---

## Etiquetas

```powershell
h tag                             # listar
h tag add "Trabajo"
h tag rename "Trabajo" "Oficina"
h tag rm "Oficina" --yes
h tag attach 3 "Oficina"
h tag detach 3 "Oficina"
h tag move "Oficina" 0
```

---

## Estadísticas y cuenta

```powershell
h stats
h profile
h notify
h notify see                      # todas como vistas
h notify read                     # todas como leídas
h inbox
h inbox send <uuid> "Hola"
```

---

## Poderes de clase

```powershell
h skills                          # lista poderes, coste, nivel y estado
h cast 1                          # lanza el poder #1
h cast 1 --target 3               # sobre la tarea #3 de la última lista
h cast smash 3                    # por clave y tarea
h cast herramientas               # poder de equipo (sin objetivo)
h cast 1 --times 2                # repetir el lanzamiento
```

| Clase | Poderes |
|---|---|
| Guerrero | Golpe Brutal, Postura defensiva, Presencia Valerosa, Mirada intimidante |
| Pícaro | Hurtar, Puñalada, Herramientas del Oficio, Sigilo |
| Mago | Estallido de llamas, Corriente etérea, Terremoto, Frío escalofriante |
| Sanador | Luz Sanadora, Claridad Abrasadora, Aura Protectora, Bendición |

Los poderes de tarea aceptan `--target` con un número de la última lista, UUID, alias o texto. Los poderes de equipo, de tareas y sobre ti no necesitan objetivo. El coste se valida antes de llamar a la API y se descuentan los PM al lanzarlo.

---

## Party y grupos

```powershell
h party
h party create "Nombre"
h party invite <uuid> [uuid2 ...]
h party kick <uuid> --yes
h party leave --yes
h party join <group-id>
h groups
```

---

## Chat

```powershell
h chat                            # últimos mensajes
h chat "Mensaje"
h chat like 2
h chat seen
h chat rm 2 --yes
```

---

## Quests

```powershell
h quest                           # estado
h quest list                      # pergaminos disponibles
h quest invite <clave>
h quest accept
h quest reject
h quest start
h quest abort --yes
h quest cancel --yes
h quest leave --yes
```

---

## Retos

```powershell
h challenges
h challenges --mine
h challenges --owned
h challenges --search "lectura"
h challenges --page 1

h challenge show 1
h challenge join 1
h challenge leave 1 --yes
h challenge members 1
h challenge clone 1
h challenge export 1 reto.csv
h challenge update 1 --summary "Nuevo resumen"
h challenge create --name "Reto" --group <group-id> --prize 5 --summary "Resumen"
```

---

## Configuración

```powershell
h config
h config init
h config test
h config path
h config reset --yes
h config cache
h config set --user <id> --token <token> --client <id>
```

Variables de entorno:

```powershell
$env:HABITICA_USER_ID
$env:HABITICA_API_TOKEN
$env:HABITICA_CLIENT_ID
$env:HABITICA_BASE_URL
$env:HABITICA_TIMEOUT
$env:HABITICA_CLI_HOME
$env:HABITICA_CLI_WIDTH
$env:HABITICA_CLI_HEIGHT
```

---

## API genérica

```powershell
h api GET tasks/user
h api GET "user?userFields=stats,profile,party"
h api POST tasks/user '{"text":"Nueva tarea","type":"todo"}'
h api PUT tasks/<id> '{"notes":"Actualizado"}'
h api DELETE tasks/<id>
h api GET challenges/user --full
```

La ruta es relativa a `https://habitica.com/api/v3`. Documentación oficial: <https://habitica.com/apidoc>.

---

## Fechas

```text
hoy, today
manana, tomorrow
ayer
+3d, +2w, +1m
2026-12-31
31/12/2026
31/12
lunes, martes, miercoles, jueves, viernes, sabado, domingo
```

---

## Teclas de la TUI

| Tecla | Acción |
|---|---|
| `↑` `↓` / `j` `k` | Mover selección |
| `Tab` / `Shift+Tab` | Cambiar pestaña |
| `1`..`9`, `0` | Ir a pestaña |
| `r` | Recargar |
| `p` | Ir a Poderes |
| `/` | Filtrar |
| `?` | Ayuda |
| `q` / `Esc` | Salir |

### Tareas, diarias, hábitos y recompensas

| Tecla | Acción |
|---|---|
| `Enter` | Completar / comprar |
| `b` | Comprar recompensa |
| `x` | Deshacer |
| `a` | Agregar |
| `e` | Editar título |
| `d` | Eliminar |
| `c` | Checklist |
| `t` | Etiqueta |
| `m` | Mover al principio |
| `v` | Detalle |

### Social

| Contexto | Teclas |
|---|---|
| Party | `i` invitar, `l` salir, `c` chat |
| Chat | `m` escribir, `l` like, `s` leído |
| Quest | `a` aceptar, `n` rechazar, `s` iniciar, `b` abortar, `c` cancelar, `l` salir, `i` invitar |
| Retos | `j` unirse, `l` salir, `c` crear, `Enter`/`v` detalle |
| Poderes | `Enter` lanzar, `v` detalle |

---

## Cmdlets

El módulo también expone funciones para scripts:

```powershell
Get-HabiticaTask -Type Todo
New-HabiticaTask -Type Todo -Text "Comprar leche" -Priority Media -DueDate (Get-Date).AddDays(1)
Set-HabiticaTask -Id <id> -Text "Nuevo titulo"
Complete-HabiticaTask -Id <id>
Invoke-HabiticaTaskScore -Id <id> -Direction Up
Remove-HabiticaTask -Id <id> -Force

Get-HabiticaStats
Get-HabiticaUser
Get-HabiticaSkill
Get-HabiticaSkill -Class rogue
Invoke-HabiticaSkillCast -Skill smash -Target 3
Get-HabiticaTag
Get-HabiticaParty
Get-HabiticaChat
Get-HabiticaQuest
Get-HabiticaChallengeList

Invoke-HabiticaApi -Method GET -Path 'tasks/user'
```

Todas las operaciones destructivas soportan confirmación y `-Force`/`--yes`.
