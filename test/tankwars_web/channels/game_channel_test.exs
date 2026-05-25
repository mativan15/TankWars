defmodule TankWarsWeb.GameChannelTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  @endpoint TankWarsWeb.Endpoint

  setup do
    TankWars.GameServer.reset()
    :ok
  end

  test "join assigns a player and returns the current state" do
    {:ok, socket} = connect(TankWarsWeb.UserSocket, %{})

    {:ok, response, _socket} =
      subscribe_and_join(socket, TankWarsWeb.GameChannel, "game:lobby", %{"name" => "Tester"})

    assert response.player_id == "p1"
    assert response.state.players["p1"].name == "Tester"
    assert response.state.territory["2,2"] == "p1"
  end

  test "move broadcasts updated state" do
    {:ok, socket} = connect(TankWarsWeb.UserSocket, %{})

    {:ok, _response, socket} =
      subscribe_and_join(socket, TankWarsWeb.GameChannel, "game:lobby", %{})

    push(socket, "move", %{"dx" => 1, "dy" => 0})

    assert_broadcast "state", %{players: players, territory: territory, tick: 1}
    assert players["p1"].x == 3
    assert territory["3,2"] == "p1"
  end
end
