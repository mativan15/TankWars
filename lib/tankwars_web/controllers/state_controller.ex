defmodule TankWarsWeb.StateController do
  use TankWarsWeb, :controller

  def show(conn, _params) do
    json(conn, TankWars.GameServer.estado_actual())
  end
end
