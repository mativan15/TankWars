import Config

config :tankwars, TankWarsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "nXz0E9UWuuFKiUq4nL2XlHShx9abD8kzMSvFHVwP4ZrGZzSsZ4axU5EoBlAq6r9r",
  watchers: []

config :logger, level: :debug
