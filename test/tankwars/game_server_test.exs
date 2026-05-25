defmodule TankWars.GameServerTest do
  use ExUnit.Case, async: false

  setup do
    TankWars.GameServer.reset()
    :ok
  end

  test "starts with three players and initial territory" do
    state = TankWars.GameServer.current_state()

    assert map_size(state.players) == 3
    assert state.width == 16
    assert state.height == 10
    assert state.territory["2,2"] == "p1"
    assert state.territory["13,2"] == "p2"
    assert state.territory["7,7"] == "p3"
  end

  test "moving a player updates position and captures territory" do
    state = TankWars.GameServer.move_player("p1", 1, 0)

    assert state.players["p1"].x == 3
    assert state.players["p1"].y == 2
    assert state.territory["3,2"] == "p1"
    assert state.tick == 1
  end

  test "movement is clamped to arena bounds" do
    state =
      Enum.reduce(1..10, TankWars.GameServer.current_state(), fn _step, _state ->
        TankWars.GameServer.move_player("p1", -1, -1)
      end)

    assert state.players["p1"].x == 0
    assert state.players["p1"].y == 0
    assert state.territory["0,0"] == "p1"
  end
end
