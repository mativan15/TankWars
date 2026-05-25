defmodule TankWarsWeb.StateControllerTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint TankWarsWeb.Endpoint

  setup do
    TankWars.GameServer.reset()
    :ok
  end

  test "GET /api/state returns the public game state" do
    conn = build_conn() |> get("/api/state")
    body = Jason.decode!(conn.resp_body)

    assert conn.status == 200
    assert body["width"] == 16
    assert map_size(body["players"]) == 3
    assert body["territory"]["2,2"] == "p1"
  end
end
