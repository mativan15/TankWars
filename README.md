# Tactical Tank Wars - Arcade Update

Este repositorio contiene la evolución del prototipo de Tank Wars desde un sistema estático/por turnos hacia un entorno **Arcade en tiempo Real** síncrono utilizando Elixir (GenServer) y Phoenix Channels.

## Instalación y ejecución local

### Requisitos

Este proyecto usa Phoenix sobre Elixir y no requiere una base de datos ni dependencias de npm. El frontend está en `priv/static/assets` como JavaScript y CSS estáticos.

Necesitas tener instalado:

* **Erlang/OTP**
* **Elixir 1.15 o superior** (el proyecto declara `elixir: "~> 1.15"` en `mix.exs`)

Opciones rápidas de instalación:

```bash
# macOS con Homebrew
brew install erlang elixir
```

```powershell
# Windows con winget
winget install Erlang.Erlang
winget install Elixir.Elixir
```

Después de instalar, verifica que ambos comandos existan:

```bash
elixir --version
mix --version
```

### Instalar dependencias del proyecto

Desde la carpeta raíz del repositorio:

```bash
cd /TankWarsFinalLP
mix deps.get
```

`mix deps.get` descarga las dependencias declaradas en `mix.exs`, principalmente Phoenix, Jason y Plug Cowboy. La carpeta `deps/` es generada por Mix y no se debe editar manualmente.

### Compilar

```bash
mix compile
```

### Ejecutar el servidor

```bash
mix phx.server
```

O alternativamente, para tener acceso a la consola interactiva de Elixir:
```bash
iex -S mix phx.server
```

```bash
recompile()
TankWars.GameServer.reset()
```

Cuando el servidor esté levantado, abre:

* Juego: `http://localhost:4000`
* Estado en JSON: `http://localhost:4000/api/state`

Para detener el servidor, presiona `Ctrl+C` dos veces en la terminal.

### Archivos principales durante el desarrollo

* `lib/tankwars/game_server.ex`: estado autoritativo del juego, jugadores, torres, proyectiles y ciclo de actualización.
* `lib/tankwars_web/channels/game_channel.ex`: canal WebSocket que conecta el frontend con el servidor.
* `lib/tankwars_web/controllers/state_controller.ex`: endpoint HTTP para consultar el estado actual.
* `priv/static/assets/app.js`: frontend del juego en Canvas y cliente WebSocket.
* `priv/static/assets/styles.css`: estilos visuales del juego.

## Cambios Introducidos en esta Versión

* **Físicas y Proyectiles Fluidos:** El pulso del servidor (`tick_rate`) se redujo de 1000ms a **100ms**. Los proyectiles ahora se mueven usando cálculos flotantes en el servidor, eliminando el movimiento "cuadro por cuadro".
* **Lógica de Torres Hostiles (Cara Amarilla):** * Spawn infinito y aleatorio en celdas vacías al iniciar o reiniciarse el mapa.
  * Inteligencia artificial con limitación de munición: cada torre solo puede tener **un proyectil activo** viajando por la pantalla. No vuelve a disparar hasta que su bala previa impacte o salga del tablero.
  * Diseño estético pixel art optimizado sin bordes excedentes para denotar furia pura.
* **Sistema de Salud Integrado:** Se añadieron **5 vidas (corazones)** dinámicos en la barra superior de estado del HUD.
* **Feedback Visual de Impacto:** Cuando un tanque colisiona con un proyectil, el servidor activa un `hit_timer` que hace parpadear el tanque en el Canvas por fracciones de segundo.
* **Retroceso por Ráfaga:** Si un jugador vacía las 5 balas en un máximo de **1 segundo**, el tanque retrocede una casilla. El desplazamiento respeta los límites de la arena, los obstáculos y la posición de otros tanques.
* **Salto:** Al presionar `Espacio`, el tanque salta dos casillas en la dirección del cañón. Puede superar la casilla intermedia, pero debe aterrizar dentro de la arena y en una casilla sin obstáculos ni otros tanques. La habilidad tiene un cooldown de **5 segundos** y el HUD indica cuándo vuelve a estar lista.
