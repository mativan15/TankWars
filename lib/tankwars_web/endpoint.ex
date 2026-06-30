defmodule TankWarsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :tankwars

  socket "/socket", TankWarsWeb.UserSocket,
    websocket: true,
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :tankwars,
    gzip: false,
    only: TankWarsWeb.static_paths()

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Head
  plug TankWarsWeb.Router
end
