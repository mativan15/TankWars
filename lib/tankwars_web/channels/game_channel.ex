defmodule TankWarsWeb.GameChannel do
  use TankWarsWeb, :channel

  @impl true
  def join("game:lobby", payload, socket) do
    name = Map.get(payload, "name", "Jugador")
    %{player_id: player_id, state: state} = TankWars.GameServer.join_player(name)

    socket = assign(socket, :player_id, player_id)

    {:ok, %{player_id: player_id, state: state}, socket}
  end

  @impl true
  def handle_in("move", %{"dx" => dx, "dy" => dy}, socket) do
    state = TankWars.GameServer.move_player(socket.assigns.player_id, dx, dy)
    broadcast!(socket, "state", state)
    {:noreply, socket}
  end

  def handle_in("move", _payload, socket) do
    {:reply, {:error, %{reason: "payload invalido"}}, socket}
  end
end
