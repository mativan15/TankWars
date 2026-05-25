defmodule TankWars.GameServer do
  @moduledoc """
  Estado autoritativo mínimo de la partida.

  Este GenServer mantiene el estado en memoria y delega las transformaciones a
  funciones puras para que sean fáciles de probar y reemplazar por reglas más
  completas después.
  """

  use GenServer

  @name __MODULE__
  @player_ids ["p1", "p2", "p3"]
  @width 16
  @height 10

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def current_state do
    GenServer.call(@name, :current_state)
  end

  def join_player(name \\ "Jugador") do
    GenServer.call(@name, {:join_player, name})
  end

  def move_player(player_id, dx, dy) do
    GenServer.call(@name, {:move_player, player_id, dx, dy})
  end

  def reset do
    GenServer.call(@name, :reset)
  end

  @impl true
  def init(:ok) do
    {:ok, initial_state()}
  end

  @impl true
  def handle_call(:current_state, _from, state) do
    {:reply, public_state(state), state}
  end

  def handle_call({:join_player, name}, _from, state) do
    player_id = Enum.at(@player_ids, rem(state.next_player_index, length(@player_ids)))

    state =
      state
      |> put_in([:players, player_id, :name], display_name(name, player_id))
      |> Map.update!(:next_player_index, &(&1 + 1))

    {:reply, %{player_id: player_id, state: public_state(state)}, state}
  end

  def handle_call({:move_player, player_id, dx, dy}, _from, state) do
    state = apply_move(state, player_id, dx, dy)
    {:reply, public_state(state), state}
  end

  def handle_call(:reset, _from, _state) do
    state = initial_state()
    {:reply, public_state(state), state}
  end

  def initial_state do
    players = %{
      "p1" => %{id: "p1", name: "Rojo", x: 2, y: 2, color: "#e5484d"},
      "p2" => %{id: "p2", name: "Azul", x: 13, y: 2, color: "#3b82f6"},
      "p3" => %{id: "p3", name: "Verde", x: 7, y: 7, color: "#22c55e"}
    }

    territory =
      Enum.reduce(players, %{}, fn {player_id, player}, acc ->
        Map.put(acc, cell_key(player.x, player.y), player_id)
      end)

    %{
      width: @width,
      height: @height,
      tick: 0,
      players: players,
      territory: territory,
      next_player_index: 0
    }
  end

  def apply_move(state, player_id, dx, dy) do
    case Map.fetch(state.players, player_id) do
      {:ok, player} ->
        dx = normalize_step(dx)
        dy = normalize_step(dy)

        player = %{
          player
          | x: clamp(player.x + dx, 0, state.width - 1),
            y: clamp(player.y + dy, 0, state.height - 1)
        }

        state
        |> put_in([:players, player_id], player)
        |> Map.update!(:tick, &(&1 + 1))
        |> capture_cell(player_id, player.x, player.y)

      :error ->
        state
    end
  end

  def public_state(state) do
    Map.take(state, [:width, :height, :tick, :players, :territory])
  end

  defp capture_cell(state, player_id, x, y) do
    put_in(state, [:territory, cell_key(x, y)], player_id)
  end

  defp cell_key(x, y), do: "#{x},#{y}"

  defp normalize_step(value) when is_integer(value), do: clamp(value, -1, 1)
  defp normalize_step(value) when is_float(value), do: value |> round() |> normalize_step()

  defp normalize_step(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _rest} -> normalize_step(number)
      :error -> 0
    end
  end

  defp normalize_step(_value), do: 0

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value

  defp display_name(name, player_id) when is_binary(name) do
    name = String.trim(name)

    if name == "" do
      default_name(player_id)
    else
      String.slice(name, 0, 24)
    end
  end

  defp display_name(_name, player_id), do: default_name(player_id)

  defp default_name("p1"), do: "Rojo"
  defp default_name("p2"), do: "Azul"
  defp default_name("p3"), do: "Verde"
  defp default_name(player_id), do: player_id
end
