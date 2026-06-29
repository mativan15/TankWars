defmodule TankWarsWeb.GameChannel do
  use TankWarsWeb, :channel
  alias TankWars.GameServer

  @impl true
  def join("game:lobby", payload, socket) do
    name = Map.get(payload, "name", "Jugador")
    client_id = Map.get(payload, "client_id")

    case GameServer.join_player(name, client_id, self()) do
      {:ok, %{player_id: player_id, state: initial_state}} ->
        socket = assign(socket, :player_id, player_id)
        {:ok, %{player_id: player_id, state: initial_state}, socket}

      {:error, :game_full, state} ->
        {:error, %{reason: "La partida ya tiene todos los jugadores ocupados", state: state}}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if player_id = socket.assigns[:player_id] do
      GameServer.leave_player(player_id, self())
    end

    :ok
  end

  @impl true
  def handle_in("start_game", _payload, socket) do
    GameServer.start_game()
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("toggle_pause", _payload, socket) do
    GameServer.toggle_pause()
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("move_player", %{"dx" => dx, "dy" => dy}, socket) do
    player_id = socket.assigns.player_id
    GameServer.move_player(player_id, dx, dy)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("aim_player", %{"dx" => dx, "dy" => dy}, socket) do
    player_id = socket.assigns.player_id
    GameServer.aim_player(player_id, dx, dy)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("shoot_player", %{"dx" => dx, "dy" => dy}, socket) do
    player_id = socket.assigns.player_id
    GameServer.shoot_player(player_id, dx, dy)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("reset", _payload, socket) do
    GameServer.reset()
    {:reply, :ok, socket}
  end

  def handle_in("set_game_mode", %{"mode" => mode}, socket) do
    state = TankWars.GameServer.set_game_mode(mode)
    {:reply, {:ok, state}, socket}
  end
end
