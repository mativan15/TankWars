# Territory Tank Wars - desarrollo

Este repositorio contiene una implementación mínima en Phoenix para validar la
estructura general de la propuesta: backend con estado autoritativo, WebSocket y
frontend Canvas sincronizado.

## Requisitos

- Elixir 1.15 o superior
- Erlang/OTP compatible con la versión de Elixir instalada

## Instalacion en macOS

Si no tienes Homebrew instalado, instalalo desde:

```text
https://brew.sh
```

Luego instala Erlang y Elixir:

```bash
brew update
brew install erlang elixir
```

Verifica que quedaron disponibles:

```bash
elixir -v
mix -v
```

Si `elixir` o `mix` no aparecen, cierra y vuelve a abrir la terminal.

## Instalacion en Windows

Opcion recomendada con `winget`, desde PowerShell:

```powershell
winget install Erlang.Erlang
winget install Elixir.Elixir
```

Si prefieres instaladores graficos:

```text
https://www.erlang.org/downloads
https://elixir-lang.org/install.html#windows
```

Despues de instalar, cierra y vuelve a abrir PowerShell. Verifica:

```powershell
elixir -v
mix -v
```

Si PowerShell no reconoce `elixir` o `mix`, revisa que las carpetas `bin` de
Erlang y Elixir esten en la variable de entorno `PATH`.

## Dependencias del proyecto

Desde la raiz del repositorio:

```bash
mix deps.get
```

Este comando descarga Phoenix, Jason y Plug/Cowboy, que son las dependencias
definidas en `mix.exs`.


## Ejecutar el servidor

```bash
mix phx.server
```

Después de iniciar el servidor, abre:

```text
http://localhost:4000
```

También puedes inspeccionar el estado actual con:

```text
http://localhost:4000/api/state
```

## Flujo recomendado

La primera vez:

```bash
brew install erlang elixir
mix deps.get
mix phx.server
```

Las siguientes veces:

```bash
mix phx.server
```

## Estructura del proyecto actual

El proyecto esta dividido en dos partes principales:

- `TankWars`: logica de dominio del juego.
- `TankWarsWeb`: capa web de Phoenix, es decir HTTP, WebSocket, rutas y
  controladores.

Vista general:

```text
.
├── config/
├── deps/
├── lib/
│   ├── tankwars/
│   ├── tankwars_web/
│   ├── tankwars.ex
│   └── tankwars_web.ex
├── priv/
│   └── static/
├── .formatter.exs
├── .gitignore
├── mix.exs
├── mix.lock
├── README.md
└── README-dev.md
```

### Archivos de raiz

- `mix.exs`: define el proyecto Elixir. Aqui estan el nombre de la app
  (`:tankwars`), la version de Elixir requerida, como arranca la aplicacion y
  las dependencias principales: Phoenix, Jason y Plug/Cowboy.
- `mix.lock`: fija las versiones exactas descargadas por `mix deps.get`. Este
  archivo ayuda a que todos usen las mismas versiones de dependencias.
- `.formatter.exs`: configura el formateador oficial de Elixir. Se usa con
  `mix format`.
- `.gitignore`: indica que carpetas no se deben subir a Git, como `_build/`,
  `deps/` y archivos temporales.
- `README.md`: descripcion general de la propuesta del juego.
- `README-dev.md`: guia tecnica para instalar, ejecutar y entender esta version
  minima.

### Carpeta `config/`

Contiene la configuracion de Phoenix y de la aplicacion por entorno.

- `config/config.exs`: configuracion comun. Define el endpoint web,
  `TankWarsWeb.Endpoint`, el servidor PubSub y la libreria JSON.
- `config/dev.exs`: configuracion para desarrollo. Expone el servidor en
  `127.0.0.1:4000`, activa errores detallados y recarga de codigo.
- `config/test.exs`: configuracion para pruebas. Usa puerto `4002` y no levanta
  el servidor HTTP real.
- `config/prod.exs`: configuracion base para produccion. Lee el puerto desde
  `PORT` y usa `SECRET_KEY_BASE`.

### Carpeta `deps/`

Contiene las dependencias descargadas por `mix deps.get`, por ejemplo Phoenix,
Plug, Cowboy y Jason.

No se edita manualmente y no se sube al repositorio. Si falta, se regenera con:

```bash
mix deps.get
```

### Carpeta `lib/`

Es donde vive el codigo fuente de la aplicacion.

#### `lib/tankwars.ex`

Modulo raiz del dominio `TankWars`. Por ahora solo documenta el contexto
principal. Mas adelante podria exponer funciones publicas de alto nivel del
juego.

#### `lib/tankwars/application.ex`

Es el punto de arranque OTP de la aplicacion. Cuando ejecutas
`mix phx.server`, Elixir inicia este modulo y levanta estos procesos:

```elixir
{Phoenix.PubSub, name: TankWars.PubSub}
TankWars.GameServer
TankWarsWeb.Endpoint
```

La relacion es:

- `Phoenix.PubSub`: permite publicar eventos en tiempo real.
- `TankWars.GameServer`: guarda el estado minimo del juego.
- `TankWarsWeb.Endpoint`: recibe HTTP y WebSockets.

#### `lib/tankwars/game_server.ex`

Es el backend minimo del juego. Usa `GenServer`, que es un proceso de Elixir que
mantiene estado y recibe mensajes de forma ordenada.

Responsabilidades actuales:

- crear el estado inicial con 3 jugadores;
- guardar posiciones, colores, territorio y contador `tick`;
- asignar un jugador cuando un cliente entra al canal;
- mover un jugador dentro de los limites del mapa;
- capturar la celda donde cae el tanque;
- devolver un estado publico serializable como JSON.

Este modulo representa el "servidor autoritativo": el frontend no decide el
estado final, solo envia acciones. El backend calcula el nuevo estado.

### Carpeta `lib/tankwars_web/`

Contiene toda la parte web de Phoenix.

#### `lib/tankwars_web.ex`

Define macros compartidas para la capa web. En Phoenix es comun tener este
archivo para declarar como se comportan controladores, routers y channels.

En este proyecto expone:

- `controller`: configuracion comun para controladores HTTP;
- `router`: configuracion comun para el router;
- `channel`: configuracion comun para WebSocket Channels;
- `static_paths`: lista de archivos estaticos servidos desde `priv/static`.

#### `lib/tankwars_web/endpoint.ex`

Es la puerta de entrada web. Recibe todas las conexiones HTTP y WebSocket.

Hace cuatro cosas importantes:

- registra el socket `/socket`;
- sirve archivos estaticos como `/assets/app.js` y `/assets/styles.css`;
- prepara parsers para JSON y formularios;
- envia las peticiones HTTP al router.

#### `lib/tankwars_web/router.ex`

Define las rutas HTTP.

Rutas actuales:

- `GET /`: llama a `PageController.home/2` y entrega la pagina principal.
- `GET /api/state`: llama a `StateController.show/2` y devuelve el estado del
  juego en JSON.

#### `lib/tankwars_web/controllers/page_controller.ex`

Genera el HTML principal de la app. Incluye:

- el panel de estado;
- el elemento `<canvas>`;
- los enlaces a `styles.css` y `app.js`.

No implementa la logica visual; solo entrega la pagina al navegador.

#### `lib/tankwars_web/controllers/state_controller.ex`

Expone el endpoint de diagnostico:

```text
GET /api/state
```

Este controlador consulta `TankWars.GameServer.current_state()` y responde JSON.
Sirve para verificar rapidamente que el backend esta vivo.

#### `lib/tankwars_web/controllers/error_html.ex`

Respuesta basica para errores HTML. Phoenix la usa si ocurre un error en una
ruta que espera HTML.

#### `lib/tankwars_web/controllers/error_json.ex`

Respuesta basica para errores JSON. Phoenix la usa si ocurre un error en una
ruta que espera JSON.

#### `lib/tankwars_web/channels/user_socket.ex`

Define el socket principal de Phoenix Channels.

Relaciona el topic:

```text
game:lobby
```

con el modulo:

```elixir
TankWarsWeb.GameChannel
```

Esto significa que cualquier cliente conectado a `/socket` puede intentar unirse
al canal `game:lobby`.

#### `lib/tankwars_web/channels/game_channel.ex`

Maneja los mensajes WebSocket del juego.

Cuando el cliente entra al canal:

```text
phx_join -> game:lobby
```

el canal llama a `TankWars.GameServer.join_player/1`, asigna un `player_id` y
devuelve el estado actual.

Cuando el cliente envia:

```json
{ "dx": 1, "dy": 0 }
```

como evento `move`, el canal llama a:

```elixir
TankWars.GameServer.move_player(player_id, dx, dy)
```

Luego hace `broadcast!` del nuevo estado para que todos los navegadores
conectados redibujen la misma arena.

### Carpeta `priv/static/`

Contiene archivos que Phoenix sirve directamente al navegador.

#### `priv/static/assets/styles.css`

Define la apariencia de la pagina:

- layout principal;
- panel de estado;
- contenedor de la arena;
- tamanos responsivos para desktop y mobile.

#### `priv/static/assets/app.js`

Es el frontend minimo del juego.

Responsabilidades:

- abrir un WebSocket contra `/socket/websocket`;
- unirse al topic `game:lobby`;
- guardar `player_id` y `state`;
- capturar teclado con `WASD` y flechas;
- enviar eventos `move` al backend;
- recibir eventos `state`;
- dibujar grid, territorio y tanques en Canvas.

No calcula reglas de juego. Solo envia acciones y renderiza el estado que manda
el servidor.

### Carpeta `test/`

Contiene pruebas automaticas con ExUnit.

- `test/test_helper.exs`: inicia ExUnit.
- `test/tankwars/game_server_test.exs`: prueba el estado inicial, movimiento y
  captura de territorio.
- `test/tankwars_web/channels/game_channel_test.exs`: prueba conexion al canal,
  asignacion de jugador y broadcast de estado.
- `test/tankwars_web/controllers/state_controller_test.exs`: prueba el endpoint
  `GET /api/state`.

Se ejecutan con:

```bash
mix test
```

## Como se relacionan las piezas

Flujo al abrir la pagina:

```text
Navegador
  -> GET /
  -> TankWarsWeb.Endpoint
  -> TankWarsWeb.Router
  -> TankWarsWeb.PageController
  -> HTML con Canvas, CSS y JS
```

Flujo al conectarse en tiempo real:

```text
priv/static/assets/app.js
  -> WebSocket /socket/websocket
  -> TankWarsWeb.UserSocket
  -> TankWarsWeb.GameChannel join game:lobby
  -> TankWars.GameServer.join_player
  -> respuesta con player_id y state
```

Flujo al mover un tanque:

```text
Teclado WASD/flechas
  -> app.js envia evento move
  -> GameChannel.handle_in("move", ...)
  -> GameServer.move_player(...)
  -> GameServer actualiza posicion, tick y territorio
  -> GameChannel broadcast!("state", state)
  -> todos los navegadores redibujan el Canvas
```

Resumen de responsabilidades:

- Phoenix recibe conexiones y organiza rutas/canales.
- `GameChannel` traduce mensajes WebSocket a llamadas de backend.
- `GameServer` mantiene y transforma el estado oficial.
- `app.js` dibuja la arena y envia acciones del usuario.
- `styles.css` solo se encarga de la presentacion visual.

## Alcance implementado

- Tres tanques iniciales.
- Estado de partida en `TankWars.GameServer`.
- Movimiento básico por WebSocket con `WASD` o flechas.
- Captura de territorio al mover un tanque.
- Canvas que dibuja territorio y tanques.

No incluye combate, disparos, daño, torretas, eventos globales ni persistencia.
