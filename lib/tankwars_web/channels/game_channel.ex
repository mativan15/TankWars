defmodule TankWarsWeb.GameChannel do
  use TankWarsWeb, :channel
  alias TankWars.GameServer

  @impl true
  def join("game:lobby", payload, socket) do
    name = Map.get(payload, "name", "Jugador")

    case GameServer.join_player(name) do
      %{player_id: player_id, state: initial_state} ->
        socket = assign(socket, :player_id, player_id)
        {:ok, %{player_id: player_id, state: initial_state}, socket}

      _ ->
        {:error, %{reason: "Error de sincronización"}}
    end
  end

  @impl true
  def handle_in("start_game", _payload, socket) do
    new_state = GameServer.start_game()
    broadcast!(socket, "state", new_state)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("move_player", %{"dx" => dx, "dy" => dy}, socket) do
    player_id = socket.assigns.player_id
    new_state = GameServer.move_player(player_id, dx, dy)
    broadcast!(socket, "state", new_state)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("shoot_player", %{"dx" => dx, "dy" => dy}, socket) do
    player_id = socket.assigns.player_id
    new_state = GameServer.shoot_player(player_id, dx, dy)
    broadcast!(socket, "state", new_state)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("reset", _payload, socket) do
    new_state = GameServer.reset()
    broadcast!(socket, "state", new_state)
    {:reply, :ok, socket}
  end
end
