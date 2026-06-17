defmodule TankWars.GameServer do
  @moduledoc """
  Gestiona la posición fluida de los proyectiles, las 5 vidas de los jugadores,
  y el respawn aleatorio e infinito de las torres doradas al morir.
  """
  use GenServer

  @name __MODULE__
  @player_ids ["p1", "p2", "p3"]
  @width 16
  @height 10
  @tick_rate 100 
  @game_duration 60 

  # API
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: @name)
  def current_state, do: GenServer.call(@name, :current_state)
  def join_player(name \\ "Jugador"), do: GenServer.call(@name, {:join_player, name})
  def move_player(player_id, dx, dy), do: GenServer.call(@name, {:move_player, player_id, dx, dy})
  def start_game, do: GenServer.call(@name, :start_game)
  def reset, do: GenServer.call(@name, :reset)

  @impl true
  def init(:ok), do: {:ok, initial_state()}

  @impl true
  def handle_call(:current_state, _from, state), do: {:reply, public_state(state), state}

  @impl true
  def handle_call({:join_player, name}, _from, state) do
    player_id = Enum.at(@player_ids, rem(state.next_player_index, length(@player_ids)))
    new_state = state 
                |> put_in([:players, player_id, :name], display_name(name, player_id))
                |> Map.update!(:next_player_index, &(&1 + 1))
    broadcast_state(new_state)
    {:reply, %{player_id: player_id, state: public_state(new_state)}, new_state}
  end

  @impl true
  def handle_call({:move_player, player_id, dx, dy}, _from, state) do
    if state.game_state == :playing do
      new_state = apply_move(state, player_id, dx, dy)
      broadcast_state(new_state)
      {:reply, public_state(new_state), new_state}
    else
      {:reply, public_state(state), state}
    end
  end

  @impl true
  def handle_call(:start_game, _from, state) do
    if state.game_state == :menu do
      new_state = %{state | game_state: :playing, last_time_check: System.monotonic_time(:millisecond)}
      schedule_tick()
      broadcast_state(new_state)
      {:reply, public_state(new_state), new_state}
    else
      {:reply, public_state(state), state}
    end
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = initial_state()
    broadcast_state(new_state)
    {:reply, public_state(new_state), new_state}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.game_state == :playing do
      current_time = System.monotonic_time(:millisecond)
      elapsed = current_time - state.last_time_check

      # 1. Manejo del Cronómetro real
      {time_left, last_time} = if elapsed >= 1000 do
        {max(0, state.time_left - 1), current_time}
      else
        {state.time_left, state.last_time_check}
      end

      # BUGFIX CLAVE: Re-inyectar las transformaciones de estado acumulativas
      state = %{state | time_left: time_left, last_time_check: last_time}
      state = spawn_tower_projectiles(state)
      state = update_projectiles(state)
      state = update_hit_animations(state)

      state = if time_left <= 0 or any_player_dead?(state) do
        %{state | game_state: :game_over}
      else
        schedule_tick()
        state
      end

      broadcast_state(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def initial_state do
    players = %{
      "p1" => %{id: "p1", name: "Rojo", x: 1, y: 1, color: "#e5484d", lives: 5, hit_timer: 0},
      "p2" => %{id: "p2", name: "Azul", x: 14, y: 1, color: "#3b82f6", lives: 5, hit_timer: 0},
      "p3" => %{id: "p3", name: "Verde", x: 7, y: 8, color: "#22c55e", lives: 5, hit_timer: 0}
    }
    territory = Map.new(players, fn {id, p} -> {"#{p.x},#{p.y}", id} end)

    state_init = %{
      width: @width, height: @height, tick: 0,
      players: players, territory: territory,
      obstacles: %{}, projectiles: [],
      next_player_index: 0, time_left: @game_duration,
      game_state: :menu, last_time_check: 0
    }

    generate_initial_map(state_init)
  end

  defp generate_initial_map(state) do
    state = spawn_random_tower(state)
    state = spawn_random_tower(state)
    Enum.reduce(1..4, state, fn _, acc -> spawn_cobertura_muro(acc) end)
  end

  defp spawn_random_tower(state) do
    key = find_empty_coordinate(state)
    unique_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    put_in(state, [:obstacles, key], %{type: "torre_vida", health: 100, id: unique_id})
  end

  defp spawn_cobertura_muro(state) do
    dir = Enum.random([:h, :v])
    rx = Enum.random(2..12)
    ry = Enum.random(2..6)

    coords = case dir do
      :h -> ["#{rx},#{ry}", "#{rx+1},#{ry}", "#{rx+2},#{ry}"]
      :v -> ["#{rx},#{ry}", "#{rx},#{ry+1}", "#{rx},#{ry+2}"]
    end

    collision = Enum.any?(coords, fn k -> Map.has_key?(state.obstacles, k) end)

    if collision do
      spawn_cobertura_muro(state)
    else
      Enum.reduce(coords, state, fn k, acc -> 
        put_in(acc, [:obstacles, k], %{type: "muro_gris", health: 50})
      end)
    end
  end

  defp apply_move(state, player_id, dx, dy) do
    case Map.fetch(state.players, player_id) do
      {:ok, player} ->
        nx = clamp(player.x + normalize_step(dx), 0, @width - 1)
        ny = clamp(player.y + normalize_step(dy), 0, @height - 1)
        key = "#{nx},#{ny}"

        if Map.has_key?(state.obstacles, key) do
          state
        else
          state
          |> put_in([:players, player_id, :x], nx)
          |> put_in([:players, player_id, :y], ny)
          |> Map.update!(:tick, &(&1 + 1))
          |> put_in([:territory, key], player_id)
        end
      :error -> state
    end
  end

  defp spawn_tower_projectiles(state) do
    torres = Enum.filter(state.obstacles, fn {_, v} -> v.type == "torre_vida" end)
    
    Enum.reduce(torres, state, fn {pos, torre}, acc ->
      tiene_bala_activa = Enum.any?(acc.projectiles, fn p -> p.origin_id == torre.id end)

      if tiene_bala_activa do
        acc
      else
        [x, y] = String.split(pos, ",") |> Enum.map(&String.to_integer/1)
        {dx, dy} = Enum.random([{0, -0.4}, {0, 0.4}, {-0.4, 0}, {0.4, 0}])
        
        nuevo_proyectile = %{
          x: x + 0.5, y: y + 0.5,
          dx: dx, dy: dy, 
          origin_id: torre.id
        }
        Map.update!(acc, :projectiles, &([nuevo_proyectile | &1]))
      end
    end)
  end

  defp update_projectiles(state) do
    projectiles = Enum.map(state.projectiles, fn p -> 
      %{p | x: p.x + p.dx, y: p.y + p.dy} 
    end)

    {en_pantalla, _fuera} = Enum.split_with(projectiles, fn p -> 
      p.x >= 0 and p.x <= @width and p.y >= 0 and p.y <= @height
    end)

    Enum.reduce(en_pantalla, %{state | projectiles: []}, fn p, acc ->
      cell_x = floor(p.x)
      cell_y = floor(p.y)
      key = "#{cell_x},#{cell_y}"

      hit_player = Enum.find(acc.players, fn {_, player} -> player.x == cell_x and player.y == cell_y end)
      hit_obstacle = Map.has_key?(acc.obstacles, key) and Map.get(acc.obstacles, key).type == "muro_gris"

      cond do
        hit_player ->
          {pid, player} = hit_player
          acc = put_in(acc, [:players, pid, :lives], max(0, player.lives - 1))
          put_in(acc, [:players, pid, :hit_timer], 4)

        hit_obstacle ->
          acc # Rompe la bala contra muros grises de cobertura

        true ->
          Map.update!(acc, :projectiles, &([p | &1]))
      end
    end)
  end

  defp update_hit_animations(state) do
    players = Map.new(state.players, fn {id, p} ->
      {id, %{p | hit_timer: max(0, p.hit_timer - 1)}}
    end)
    %{state | players: players}
  end

  defp any_player_dead?(state) do
    Enum.any?(state.players, fn {_, p} -> p.lives <= 0 end)
  end

  defp find_empty_coordinate(state) do
    rx = Enum.random(0..(@width - 1))
    ry = Enum.random(0..(@height - 1))
    key = "#{rx},#{ry}"

    collision = Map.has_key?(state.obstacles, key) or 
                Enum.any?(state.players, fn {_, p} -> p.x == rx and p.y == ry end)

    if collision, do: find_empty_coordinate(state), else: key
  end

  def public_state(state) do
    Map.take(state, [:width, :height, :tick, :players, :territory, :obstacles, :projectiles, :time_left, :game_state])
  end

  defp normalize_step(v), do: clamp(round(v), -1, 1)
  defp clamp(v, min, max), do: max(min, min(v, max))
  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_rate)
  defp broadcast_state(state), do: TankWarsWeb.Endpoint.broadcast("game:lobby", "state", public_state(state))
  defp display_name(n, id), do: if(String.trim(n) == "", do: %{"p1"=>"Rojo","p2"=>"Azul","p3"=>"Verde"}[id], else: String.slice(n,0,24))
end