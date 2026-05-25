import Config

config :tankwars, TankWarsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: "3eqHESFaJjVdAr86qS9mzZP0Xt7EaclmJ9B1U6U4yoZdMVXEg1JQVDqZ9AkZNu2g"

config :logger, level: :warning
