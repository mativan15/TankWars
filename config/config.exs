import Config

config :tankwars, TankWarsWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: TankWarsWeb.ErrorHTML, json: TankWarsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TankWars.PubSub

config :phoenix, :json_library, Jason

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
