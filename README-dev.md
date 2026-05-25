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

## Ejecutar pruebas

```bash
mix test
```

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
mix test
mix phx.server
```

Las siguientes veces:

```bash
mix phx.server
```

## Alcance implementado

- Tres tanques iniciales.
- Estado de partida en `TankWars.GameServer`.
- Movimiento básico por WebSocket con `WASD` o flechas.
- Captura de territorio al mover un tanque.
- Canvas que dibuja territorio y tanques.

No incluye combate, disparos, daño, torretas, eventos globales ni persistencia.
