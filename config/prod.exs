import Config

config :tankwars, TankWarsWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  server: true,
  secret_key_base:
    System.get_env("SECRET_KEY_BASE") ||
      "replace-me-before-production-replace-me-before-production-replace-me"

config :logger, level: :info
