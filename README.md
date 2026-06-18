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
cd /Users/ivansardonmedina/Code/TankWarsFinalLP
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
* **Feedback Visual de Impacto:** Cuando un tanque colisiona con un proyectil, el servidor activa un `hit_timer` que renderiza el tanque en color rojo brillante en el Canvas por fracciones de segundo.

---

## Consideraciones Técnicas para Siguientes Módulos

El diseño actual es altamente modular, permitiendo reutilizar cerca del **80% del código base** para implementar las siguientes mecánicas:

### 1. Implementación de Proyectiles para los Tanques Jugadores
* **Frontend (`app.js`):** Escuchar el evento de teclado `Spacebar` (Barra espaciadora). Al presionarse, capturar la última dirección en la que se movió el tanque (ej. `last_dx`, `last_dy`) y hacer un `push` al canal: `push(topic, "player_shoot", {dx: last_dx, dy: last_dy})`.
* **Backend (`game_server.ex`):** Crear un `handle_call` para `{:player_shoot, player_id, dx, dy}` que añada un mapa a la lista `projectiles`, pero esta vez configurando un `origin_type: :player` para diferenciarlo del de las torres.
* **Reutilización:** La función `update_projectiles/1` actual es idéntica; solo se le debe agregar una regla para que si el proyectil es del jugador, disminuya la vida de las torres o de otros tanques enemigos en lugar de la propia.

### 2. Definición del Sistema de Ganadores
* **Criterio de Victoria:** Actualmente el juego termina si `time_left <= 0` o `any_player_dead?`. 
* **Lógica de Selección:** En la función que evalúa el `:game_over`, se puede procesar la colección de jugadores con un ordenamiento:
  1. El jugador con **más vidas restantes** (`lives`) es el ganador.
  2. En caso de empate en vidas, se puede evaluar el tamaño del territorio pintado en el mapa (`territory`) contando cuántas celdas posee cada ID de jugador.
* **Despliegue:** Pasar la información del ganador dentro del payload del estado final para que el overlay de JS renderice: `"¡GANADOR: JUGADOR AZUL!"`.
