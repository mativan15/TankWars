defmodule TankWarsWeb.GameChannel do
  use TankWarsWeb, :channel
  alias TankWars.GameServer

  @impl true
  def join("game:lobby", payload, socket) do
    client_id = Map.get(payload, "client_id")

    case GameServer.registrar_jugador(client_id, self()) do
      {:ok, %{player_id: player_id, state: estado_inicial}} ->
        socket = assign(socket, :player_id, player_id)
        {:ok, %{player_id: player_id, state: estado_inicial}, socket}

      {:error, :game_full, state} ->
        {:error, %{reason: "La partida ya tiene todos los jugadores ocupados", state: state}}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if player_id = socket.assigns[:player_id] do
      GameServer.desconectar_jugador(player_id, self())
    end

    :ok
  end

  @impl true
  def handle_in("start_game", payload, socket) do
    GameServer.start_game(Map.get(payload, "mode"))
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("toggle_pause", _payload, socket) do
    GameServer.pausa()
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("move_player", %{"dx" => dx, "dy" => dy}, socket) do
    player_id = socket.assigns.player_id
    GameServer.mover_jugador(player_id, dx, dy)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("jump_player", _payload, socket) do
    GameServer.saltar_jugador(socket.assigns.player_id)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("aim_player", %{"dx" => dx, "dy" => dy}, socket) do
    player_id = socket.assigns.player_id
    GameServer.apuntar_jugador(player_id, dx, dy)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("shoot_player", %{"dx" => dx, "dy" => dy}, socket) do
    player_id = socket.assigns.player_id
    GameServer.disparar_jugador(player_id, dx, dy)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("reset", _payload, socket) do
    GameServer.reset()
    {:reply, :ok, socket}
  end
end
