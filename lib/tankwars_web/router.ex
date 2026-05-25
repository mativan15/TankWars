defmodule TankWarsWeb.Router do
  use TankWarsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TankWarsWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api", TankWarsWeb do
    pipe_through :api

    get "/state", StateController, :show
  end
end
