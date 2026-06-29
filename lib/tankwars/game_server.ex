defmodule TankWars.GameServer do
  @moduledoc """
  Gestiona la posición fluida de los proyectiles, las vidas de los jugadores,
  la munición y las torres automáticas.
  """
  use GenServer

  @name __MODULE__
  @player_ids ["p1", "p2", "p3"]
  @width 24
  @height 14
  @tick_rate 100
  @game_duration 200
  @projectile_speed 0.4
  @max_ammo 5
  @reload_duration_ms 1_800
  @movement_idle_ms 180
  # Velocidad relativa: propio 100%, sin capturar 70%, enemigo 45%.
  @movement_scale 100
  @unclaimed_speed_weight 60
  @enemy_speed_weight 40
  @hit_effect_ticks 6
  @tower_max_lives 6

  @danger_phase_time 120
  @boss_max_lives 12
  @spike_wall_ratio 0.20

  @boss_shoot_delay_ticks 30
  @boss_projectile_speed 0.4

  # power-up
  @powerup_spawn_ticks 30
  @shield_duration_ticks 50

  # API
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: @name)
  def current_state, do: GenServer.call(@name, :current_state)

  def join_player(name \\ "Jugador", client_id \\ nil, connection_id \\ nil),
    do: GenServer.call(@name, {:join_player, name, client_id, connection_id})

  def leave_player(player_id, connection_id),
    do: GenServer.cast(@name, {:leave_player, player_id, connection_id})

  def move_player(player_id, dx, dy), do: GenServer.call(@name, {:move_player, player_id, dx, dy})

  def aim_player(player_id, dx, dy), do: GenServer.call(@name, {:aim_player, player_id, dx, dy})

  def shoot_player(player_id, dx, dy),
    do: GenServer.call(@name, {:shoot_player, player_id, dx, dy})

  def start_game, do: GenServer.call(@name, :start_game)
  def set_game_mode(mode), do: GenServer.call(@name, {:set_game_mode, mode})
  def toggle_pause, do: GenServer.call(@name, :toggle_pause)
  def reset, do: GenServer.call(@name, :reset)

  @impl true
  def init(:ok), do: {:ok, initial_state()}

  @impl true
  def handle_call(:current_state, _from, state), do: {:reply, public_state(state), state}

  @impl true
  def handle_call({:join_player, name, client_id, connection_id}, _from, state) do
    client_key = client_key(client_id, connection_id)

    case reserved_player_for_client(state, client_key) || available_player_id(state) do
      nil ->
        {:reply, {:error, :game_full, public_state(state)}, state}

      player_id ->
        connections =
          state
          |> player_connections()
          |> Map.put(player_id, %{client_id: client_key, connection_id: connection_id})

        new_state =
          state
          |> put_in([:players, player_id, :name], display_name(name, player_id))
          |> Map.put(:player_connections, connections)

        broadcast_state(new_state)
        {:reply, {:ok, %{player_id: player_id, state: public_state(new_state)}}, new_state}
    end
  end

  @impl true
  def handle_call({:set_game_mode, mode}, _from, state) do
    new_mode =
      case mode do
        "sudden_death" -> :sudden_death
        :sudden_death -> :sudden_death
        _ -> :time_attack
      end

    new_state = Map.put(state, :game_mode, new_mode)

    broadcast_state(new_state)
    {:reply, public_state(new_state), new_state}
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
  def handle_call({:aim_player, player_id, dx, dy}, _from, state) do
    if state.game_state == :playing do
      new_state = apply_aim(state, player_id, dx, dy)
      broadcast_state(new_state)
      {:reply, public_state(new_state), new_state}
    else
      {:reply, public_state(state), state}
    end
  end

  @impl true
  def handle_call({:shoot_player, player_id, dx, dy}, _from, state) do
    if state.game_state == :playing do
      new_state = apply_player_shot(state, player_id, dx, dy)
      broadcast_state(new_state)
      {:reply, public_state(new_state), new_state}
    else
      {:reply, public_state(state), state}
    end
  end

  @impl true
  def handle_call(:start_game, _from, state) do
    if state.game_state == :menu do
      new_state = %{
        state
        | game_state: :playing,
          last_time_check: System.monotonic_time(:millisecond)
      }

      schedule_tick()
      broadcast_state(new_state)
      {:reply, public_state(new_state), new_state}
    else
      {:reply, public_state(state), state}
    end
  end

  @impl true
  def handle_call(:toggle_pause, _from, %{game_state: :playing} = state) do
    new_state = %{
      state
      | game_state: :paused,
        paused_at: System.monotonic_time(:millisecond)
    }

    broadcast_state(new_state)
    {:reply, public_state(new_state), new_state}
  end

  def handle_call(:toggle_pause, _from, %{game_state: :paused} = state) do
    current_time = System.monotonic_time(:millisecond)
    paused_duration = max(0, current_time - state.paused_at)

    new_state =
      state
      |> shift_reload_deadlines(paused_duration)
      |> Map.merge(%{
        game_state: :playing,
        paused_at: nil,
        last_time_check: state.last_time_check + paused_duration
      })

    broadcast_state(new_state)
    {:reply, public_state(new_state), new_state}
  end

  def handle_call(:toggle_pause, _from, state),
    do: {:reply, public_state(state), state}

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = %{initial_state() | player_connections: player_connections(state)}
    broadcast_state(new_state)
    {:reply, public_state(new_state), new_state}
  end

  @impl true
  def handle_cast({:leave_player, player_id, connection_id}, state) do
    connections = player_connections(state)

    new_connections =
      case Map.get(connections, player_id) do
        %{connection_id: ^connection_id} -> Map.delete(connections, player_id)
        _ -> connections
      end

    {:noreply, Map.put(state, :player_connections, new_connections)}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.game_state == :playing do
      current_time = System.monotonic_time(:millisecond)
      elapsed = current_time - state.last_time_check

      # 1. Manejo del Cronómetro real
      {time_left, last_time} =
        if elapsed >= 1000 do
          {max(0, state.time_left - 1), current_time}
        else
          {state.time_left, state.last_time_check}
        end

      # BUGFIX CLAVE: Re-inyectar las transformaciones de estado acumulativas
      state = %{state | time_left: time_left, last_time_check: last_time}
      state = update_reloads(state, current_time)
      state = spawn_tower_projectiles(state)
      state = spawn_boss_projectiles(state)
      state = update_projectiles(state)
      state = update_hit_animations(state)
      state = update_powerups(state)
      state = update_player_effects(state)
      state = activate_danger_phase(state)

      state =
        if game_over?(state) do
          %{state | game_state: :game_over}
        else
          schedule_tick()
          state
        end

      broadcast_state(state)
      {:noreply, state}
    else
      if state.game_state == :paused, do: schedule_tick()
      {:noreply, state}
    end
  end

  def initial_state do
    players = %{
      "p1" => %{
        id: "p1",
        name: "Rojo",
        x: 1,
        y: 1,
        spawn_x: 1,
        spawn_y: 1,
        color: "#FF315D",
        lives: 5,
        hit_timer: 0,
        ammo: @max_ammo,
        max_ammo: @max_ammo,
        reload_ends_at: nil,
        reload_remaining_ms: @reload_duration_ms,
        reload_paused: false,
        moving_until: 0,
        movement_terrain: nil,
        movement_credit: 0,
        aim_dx: 1.0,
        aim_dy: 0.0
      },
      "p2" => %{
        id: "p2",
        name: "Azul",
        x: 23,
        y: 1,
        spawn_x: 23,
        spawn_y: 1,
        color: "#2979FF",
        lives: 5,
        hit_timer: 0,
        ammo: @max_ammo,
        max_ammo: @max_ammo,
        reload_ends_at: nil,
        reload_remaining_ms: @reload_duration_ms,
        reload_paused: false,
        moving_until: 0,
        movement_terrain: nil,
        movement_credit: 0,
        aim_dx: -1.0,
        aim_dy: 0.0
      },
      "p3" => %{
        id: "p3",
        name: "Verde",
        x: 12,
        y: 13,
        spawn_x: 12,
        spawn_y: 13,
        color: "#39FF88",
        lives: 5,
        hit_timer: 0,
        ammo: @max_ammo,
        max_ammo: @max_ammo,
        reload_ends_at: nil,
        reload_remaining_ms: @reload_duration_ms,
        reload_paused: false,
        moving_until: 0,
        movement_terrain: nil,
        movement_credit: 0,
        aim_dx: 0.0,
        aim_dy: -1.0
      }
    }

    territory = Map.new(players, fn {id, p} -> {"#{p.x},#{p.y}", id} end)

    state_init = %{
      width: @width,
      height: @height,
      tick: 0,
      players: players,
      territory: territory,
      obstacles: %{},
      projectiles: [],
      hit_effects: [],
      powerups: [],
      powerup_timer: @powerup_spawn_ticks,
      next_player_index: 0,
      player_connections: %{},
      time_left: @game_duration,
      game_state: :menu,
      game_mode: :time_attack,
      paused_at: nil,
      last_time_check: 0,
      danger_phase_started: false,
      spikes_activated: false
    }

    generate_initial_map(state_init)
  end

  defp generate_initial_map(state) do
    state = spawn_random_tower(state)
    state = spawn_random_tower(state)
    state = spawn_random_tower(state)
    state = spawn_random_tower(state)
    Enum.reduce(1..11, state, fn _, acc -> spawn_cobertura_muro(acc) end)
  end

  defp activate_danger_phase(state) do
    if state.time_left <= @danger_phase_time and not Map.get(state, :danger_phase_started, false) do
      state
      |> Map.put(:danger_phase_started, true)
      |> spawn_red_boss()
      |> activate_spike_walls()
    else
      state
    end
  end

  defp spawn_red_boss(state) do
    key = find_empty_coordinate(state)
    unique_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    put_in(state, [:obstacles, key], %{
      type: "boss_rojo",
      id: unique_id,
      lives: @boss_max_lives,
      max_lives: @boss_max_lives,
      shoot_timer: 0
    })
  end

  defp activate_spike_walls(state) do
    walls =
      state.obstacles
      |> Enum.filter(fn {_, obs} -> obs.type == "muro_gris" end)

    amount =
      walls
      |> length()
      |> Kernel.*(@spike_wall_ratio)
      |> Float.ceil()
      |> trunc()

    selected =
      walls
      |> Enum.shuffle()
      |> Enum.take(amount)

    Enum.reduce(selected, state, fn {key, wall}, acc ->
      put_in(acc, [:obstacles, key], Map.put(wall, :type, "muro_pincho"))
    end)
  end

  defp spawn_random_tower(state) do
    key = find_empty_coordinate(state)
    unique_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    put_in(state, [:obstacles, key], %{
      type: "torre_vida",
      health: 100,
      id: unique_id,
      lives: @tower_max_lives,
      max_lives: @tower_max_lives
    })
  end

  defp spawn_cobertura_muro(state) do
    dir = Enum.random([:h, :v])
    rx = Enum.random(2..(@width - 3))
    ry = Enum.random(2..(@height - 3))

    coords =
      case dir do
        :h -> ["#{rx},#{ry}", "#{rx + 1},#{ry}", "#{rx + 2},#{ry}"]
        :v -> ["#{rx},#{ry}", "#{rx},#{ry + 1}", "#{rx},#{ry + 2}"]
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
      {:ok, %{lives: lives}} when lives <= 0 ->
        state

      {:ok, player} ->
        nx = clamp(player.x + normalize_step(dx), 0, @width - 1)
        ny = clamp(player.y + normalize_step(dy), 0, @height - 1)
        key = "#{nx},#{ny}"

        occupied_by_player =
          Enum.any?(state.players, fn {other_id, other} ->
            other_id != player_id and other.lives > 0 and other.x == nx and other.y == ny
          end)

        obstacle = Map.get(state.obstacles, key)

        cond do
          nx == player.x and ny == player.y ->
            state

          occupied_by_player ->
            state

          obstacle && obstacle.type == "boss_rojo" ->
            damage_player(state, player_id, player, nx, ny)

          obstacle && obstacle.type == "muro_pincho" ->
            damage_player(state, player_id, player, nx, ny)

          obstacle ->
            state

          true ->
            now = System.monotonic_time(:millisecond)
            terrain = destination_terrain(state.territory, key, player_id)
            {can_advance, player} = apply_movement_weight(player, terrain)

            player =
              player
              |> Map.put(:moving_until, now + @movement_idle_ms)
              |> pause_player_reload(now)

            state = put_in(state, [:players, player_id], player)

            if can_advance do
              state
              |> put_in([:players, player_id, :x], nx)
              |> put_in([:players, player_id, :y], ny)
              |> Map.update!(:tick, &(&1 + 1))
              |> put_in([:territory, key], player_id)
              |> collect_powerup(player_id, nx, ny)
            else
              state
            end
        end

      :error ->
        state
    end
  end

  defp collect_powerup(state, player_id, x, y) do
    {collected, remaining} =
      state.powerups
      |> Enum.split_with(fn p -> p.x == x and p.y == y end)

    state = %{state | powerups: remaining}

    Enum.reduce(collected, state, fn powerup, acc ->
      apply_powerup(acc, player_id, powerup.type)
    end)
  end

  defp apply_powerup(state, player_id, "life") do
    state
    |> update_in([:players, player_id, :lives], fn lives ->
      min(5, lives + 1)
    end)
    |> put_in([:players, player_id, :life_effect_timer], 25)
  end

  defp apply_powerup(state, player_id, "shield") do
    put_in(state, [:players, player_id, :shield_timer], @shield_duration_ticks)
  end

  defp apply_powerup(state, player_id, "speed") do
    put_in(state, [:players, player_id, :speed_timer], 50)
  end

  defp apply_aim(state, player_id, dx, dy) do
    case Map.fetch(state.players, player_id) do
      {:ok, %{lives: lives}} when lives <= 0 ->
        state

      {:ok, _player} ->
        case normalize_direction(dx, dy) do
          nil ->
            state

          {nx, ny} ->
            state
            |> put_in([:players, player_id, :aim_dx], nx)
            |> put_in([:players, player_id, :aim_dy], ny)
        end

      :error ->
        state
    end
  end

  defp apply_player_shot(state, player_id, dx, dy) do
    case Map.fetch(state.players, player_id) do
      {:ok, %{lives: lives}} when lives <= 0 ->
        state

      {:ok, player} ->
        ammo = player |> Map.get(:ammo, @max_ammo) |> min(@max_ammo)

        if ammo <= 0 do
          state
        else
          case normalize_direction(dx, dy) do
            nil ->
              state

            {nx, ny} ->
              now = System.monotonic_time(:millisecond)
              remaining_ammo = ammo - 1
              reload_paused = remaining_ammo == 0 and player_moving?(player, now)

              reload_ends_at =
                cond do
                  remaining_ammo > 0 -> Map.get(player, :reload_ends_at)
                  reload_paused -> nil
                  true -> now + @reload_duration_ms
                end

              projectile = %{
                x: player.x + 0.5,
                y: player.y + 0.5,
                dx: nx * @projectile_speed,
                dy: ny * @projectile_speed,
                origin_id: player_id,
                origin_type: "player"
              }

              state
              |> put_in([:players, player_id, :ammo], remaining_ammo)
              |> put_in([:players, player_id, :max_ammo], @max_ammo)
              |> put_in([:players, player_id, :reload_ends_at], reload_ends_at)
              |> put_in([:players, player_id, :reload_remaining_ms], @reload_duration_ms)
              |> put_in([:players, player_id, :reload_paused], reload_paused)
              |> put_in([:players, player_id, :aim_dx], nx)
              |> put_in([:players, player_id, :aim_dy], ny)
              |> Map.update!(:projectiles, &[projectile | &1])
          end
        end

      :error ->
        state
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

        {dx, dy} =
          Enum.random([
            {0, -@projectile_speed},
            {0, @projectile_speed},
            {-@projectile_speed, 0},
            {@projectile_speed, 0}
          ])

        nuevo_proyectile = %{
          x: x + 0.5,
          y: y + 0.5,
          dx: dx,
          dy: dy,
          origin_id: torre.id,
          origin_type: "tower"
        }

        Map.update!(acc, :projectiles, &[nuevo_proyectile | &1])
      end
    end)
  end

  defp spawn_boss_projectiles(state) do
    Enum.reduce(state.obstacles, state, fn {pos, obs}, acc ->
      if obs.type == "boss_rojo" do
        timer = Map.get(obs, :shoot_timer, 0)

        if timer > 0 do
          put_in(acc, [:obstacles, pos, :shoot_timer], timer - 1)
        else
          [x, y] = String.split(pos, ",") |> Enum.map(&String.to_integer/1)

          directions = [
            {-1, -1},
            {0, -1},
            {1, -1},
            {-1, 0},
            {1, 0},
            {-1, 1},
            {0, 1},
            {1, 1}
          ]

          bullets =
            Enum.map(directions, fn {dx, dy} ->
              %{
                x: x + 0.5,
                y: y + 0.5,
                dx: dx * @boss_projectile_speed,
                dy: dy * @boss_projectile_speed,
                origin_id: obs.id,
                origin_type: "boss"
              }
            end)

          acc
          |> Map.update!(:projectiles, &(bullets ++ &1))
          |> put_in([:obstacles, pos, :shoot_timer], @boss_shoot_delay_ticks)
        end
      else
        acc
      end
    end)
  end

  defp update_projectiles(state) do
    projectiles =
      Enum.map(state.projectiles, fn p ->
        %{p | x: p.x + p.dx, y: p.y + p.dy}
      end)

    {en_pantalla, _fuera} =
      Enum.split_with(projectiles, fn p ->
        p.x >= 0 and p.x <= @width and p.y >= 0 and p.y <= @height
      end)

    Enum.reduce(en_pantalla, %{state | projectiles: []}, fn p, acc ->
      cell_x = floor(p.x)
      cell_y = floor(p.y)
      key = "#{cell_x},#{cell_y}"

      hit_player =
        Enum.find(acc.players, fn {pid, player} ->
          pid != p.origin_id and player.x == cell_x and player.y == cell_y
        end)

      obstacle = Map.get(acc.obstacles, key)

      cond do
        hit_player ->
          {pid, player} = hit_player
          damage_player(acc, pid, player, cell_x, cell_y)

        obstacle && obstacle.type == "torre_vida" && p.origin_type == "player" ->
          damage_tower(acc, key, obstacle, cell_x, cell_y)

        obstacle && obstacle.type == "boss_rojo" && p.origin_type == "player" ->
          damage_boss(acc, key, obstacle, cell_x, cell_y)

        obstacle && obstacle.type == "muro_gris" ->
          # rompe la bala contra muros grises de cobertura
          acc

        true ->
          Map.update!(acc, :projectiles, &[p | &1])
      end
    end)
  end

  defp update_reloads(state, now) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id, update_player_reload(player, now)}
      end)

    %{state | players: players}
  end

  defp update_player_reload(player, now) do
    ammo = Map.get(player, :ammo, @max_ammo)
    reload_ends_at = Map.get(player, :reload_ends_at)

    cond do
      ammo > 0 ->
        Map.put(player, :reload_paused, false)

      player_moving?(player, now) ->
        pause_player_reload(player, now)

      reload_ends_at && now >= reload_ends_at ->
        Map.merge(player, %{
          ammo: @max_ammo,
          max_ammo: @max_ammo,
          reload_ends_at: nil,
          reload_remaining_ms: @reload_duration_ms,
          reload_paused: false
        })

      is_nil(reload_ends_at) ->
        remaining = Map.get(player, :reload_remaining_ms, @reload_duration_ms)

        player
        |> Map.put(:reload_ends_at, now + remaining)
        |> Map.put(:reload_paused, false)

      true ->
        Map.put(player, :reload_paused, false)
    end
  end

  defp pause_player_reload(player, now) do
    if Map.get(player, :ammo, @max_ammo) <= 0 do
      remaining =
        case Map.get(player, :reload_ends_at) do
          nil -> Map.get(player, :reload_remaining_ms, @reload_duration_ms)
          reload_ends_at -> max(0, reload_ends_at - now)
        end

      player
      |> Map.put(:reload_ends_at, nil)
      |> Map.put(:reload_remaining_ms, remaining)
      |> Map.put(:reload_paused, true)
    else
      player
    end
  end

  defp player_moving?(player, now),
    do: now < Map.get(player, :moving_until, 0)

  defp destination_terrain(territory, key, player_id) do
    case Map.get(territory, key) do
      ^player_id -> :own
      nil -> :unclaimed
      _other_player -> :enemy
    end
  end

  defp apply_movement_weight(player, terrain) do
    if Map.get(player, :speed_timer, 0) > 0 do
      {true, Map.merge(player, %{movement_terrain: :speed, movement_credit: 0})}
    else
      apply_movement_weight_normal(player, terrain)
    end
  end

  defp apply_movement_weight_normal(player, :own) do
    {true, Map.merge(player, %{movement_terrain: :own, movement_credit: 0})}
  end

  defp apply_movement_weight_normal(player, terrain) do
    if Map.get(player, :movement_terrain) != terrain do
      {true, Map.merge(player, %{movement_terrain: terrain, movement_credit: 0})}
    else
      weight = if terrain == :enemy, do: @enemy_speed_weight, else: @unclaimed_speed_weight
      credit = Map.get(player, :movement_credit, 0) + weight

      if credit >= @movement_scale do
        {true, Map.put(player, :movement_credit, credit - @movement_scale)}
      else
        {false, Map.put(player, :movement_credit, credit)}
      end
    end
  end

  defp shift_reload_deadlines(state, paused_duration) do
    players =
      Map.new(state.players, fn {id, player} ->
        reload_ends_at =
          case Map.get(player, :reload_ends_at) do
            nil -> nil
            timestamp -> timestamp + paused_duration
          end

        {id, Map.put(player, :reload_ends_at, reload_ends_at)}
      end)

    %{state | players: players}
  end

  defp update_hit_animations(state) do
    players =
      Map.new(state.players, fn {id, p} ->
        {id, %{p | hit_timer: max(0, p.hit_timer - 1)}}
      end)

    hit_effects =
      state
      |> Map.get(:hit_effects, [])
      |> Enum.map(fn effect -> %{effect | timer: effect.timer - 1} end)
      |> Enum.filter(fn effect -> effect.timer > 0 end)

    %{state | players: players, hit_effects: hit_effects}
  end

  defp damage_tower(state, key, tower, hit_x, hit_y) do
    lives = tower |> Map.get(:lives, @tower_max_lives) |> max(0)
    max_lives = Map.get(tower, :max_lives, @tower_max_lives)
    new_lives = max(0, lives - 1)

    effect = %{
      x: hit_x,
      y: hit_y,
      color: "#f5c542",
      timer: @hit_effect_ticks,
      max_timer: @hit_effect_ticks
    }

    state = Map.update(state, :hit_effects, [effect], fn effects -> [effect | effects] end)

    if new_lives == 0 do
      state
      |> update_in([:obstacles], &Map.delete(&1, key))
      |> spawn_random_tower()
    else
      put_in(state, [:obstacles, key], %{tower | lives: new_lives, max_lives: max_lives})
    end
  end

  defp damage_boss(state, key, boss, hit_x, hit_y) do
    lives = boss |> Map.get(:lives, @boss_max_lives) |> max(0)
    max_lives = Map.get(boss, :max_lives, @boss_max_lives)
    new_lives = max(0, lives - 1)

    effect = %{
      x: hit_x,
      y: hit_y,
      color: "#ff0000",
      timer: @hit_effect_ticks,
      max_timer: @hit_effect_ticks
    }

    state = Map.update(state, :hit_effects, [effect], fn effects -> [effect | effects] end)

    if new_lives == 0 do
      state
      |> put_in([:obstacles, key], %{
        type: "muro_pincho",
        health: 50
      })
      |> spawn_red_boss()
    else
      put_in(state, [:obstacles, key], %{boss | lives: new_lives, max_lives: max_lives})
    end
  end

  defp damage_player(state, player_id, player, hit_x, hit_y) do
    if Map.get(player, :shield_timer, 0) > 0 do
      state
    else
      lives = max(0, player.lives - 1)

      player =
        player
        |> Map.put(:lives, lives)
        |> Map.put(:hit_timer, 0)
        |> Map.put(:moving_until, 0)
        |> Map.put(:movement_terrain, nil)
        |> Map.put(:movement_credit, 0)

      player =
        if lives > 0 do
          player
          |> Map.put(:x, Map.get(player, :spawn_x, player.x))
          |> Map.put(:y, Map.get(player, :spawn_y, player.y))
        else
          player
          |> Map.put(:x, hit_x)
          |> Map.put(:y, hit_y)
        end

      effect = hit_effect(player, hit_x, hit_y)

      state
      |> Map.update(:hit_effects, [effect], fn effects -> [effect | effects] end)
      |> put_in([:players, player_id], player)
    end
  end

  defp update_powerups(state) do
    timer = Map.get(state, :powerup_timer, @powerup_spawn_ticks)

    cond do
      timer > 0 ->
        %{state | powerup_timer: timer - 1}

      length(Map.get(state, :powerups, [])) >= 3 ->
        %{state | powerup_timer: @powerup_spawn_ticks}

      true ->
        key = find_empty_coordinate(state)
        [x, y] = String.split(key, ",") |> Enum.map(&String.to_integer/1)

        powerup = %{
          id: :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower),
          x: x,
          y: y,
          type: Enum.random(["life", "shield", "speed"])
        }

        state
        |> Map.update(:powerups, [powerup], fn list -> [powerup | list] end)
        |> Map.put(:powerup_timer, @powerup_spawn_ticks)
    end
  end

  defp update_player_effects(state) do
    players =
      Map.new(state.players, fn {id, player} ->
        shield_timer = max(0, Map.get(player, :shield_timer, 0) - 1)
        speed_timer = max(0, Map.get(player, :speed_timer, 0) - 1)
        life_effect_timer = max(0, Map.get(player, :life_effect_timer, 0) - 1)

        player =
          player
          |> Map.put(:shield_timer, shield_timer)
          |> Map.put(:speed_timer, speed_timer)
          |> Map.put(:life_effect_timer, life_effect_timer)

        {id, player}
      end)

    %{state | players: players}
  end

  defp hit_effect(player, x, y) do
    %{x: x, y: y, color: player.color, timer: @hit_effect_ticks, max_timer: @hit_effect_ticks}
  end

  defp alive_players_count(state) do
    Enum.count(state.players, fn {_, p} -> p.lives > 0 end)
  end

  defp game_over?(state) do
    case Map.get(state, :game_mode, :time_attack) do
      :time_attack ->
        state.time_left <= 0 or all_players_dead?(state)

      :sudden_death ->
        alive_players_count(state) <= 1
    end
  end

  defp all_players_dead?(state) do
    players = Map.values(state.players)

    players != [] and
      Enum.all?(players, fn player ->
        player.lives <= 0
      end)
  end

  defp find_empty_coordinate(state) do
    rx = Enum.random(0..(@width - 1))
    ry = Enum.random(0..(@height - 1))
    key = "#{rx},#{ry}"

    collision =
      Map.has_key?(state.obstacles, key) or
        Enum.any?(state.players, fn {_, p} -> p.x == rx and p.y == ry end)

    if collision, do: find_empty_coordinate(state), else: key
  end

  def public_state(state) do
    state
    |> Map.take([
      :width,
      :height,
      :tick,
      :players,
      :territory,
      :obstacles,
      :projectiles,
      :hit_effects,
      :powerups,
      :time_left,
      :game_state,
      :game_mode
    ])
    |> Map.update!(:players, fn players ->
      Map.new(players, fn {id, player} -> {id, normalize_public_player(player)} end)
    end)
  end

  defp normalize_public_player(player) do
    ammo = Map.get(player, :ammo, @max_ammo)
    ammo = if is_number(ammo), do: min(ammo, @max_ammo), else: @max_ammo

    player
    |> Map.put(:ammo, ammo)
    |> Map.put(:max_ammo, @max_ammo)
  end

  defp player_connections(state), do: Map.get(state, :player_connections, %{})

  defp client_key(nil, connection_id), do: {:connection, connection_id}
  defp client_key("", connection_id), do: {:connection, connection_id}
  defp client_key(client_id, _connection_id), do: {:client, client_id}

  defp reserved_player_for_client(state, client_key) do
    state
    |> player_connections()
    |> Enum.find_value(fn {player_id, connection} ->
      if connection.client_id == client_key, do: player_id
    end)
  end

  defp available_player_id(state) do
    connections = player_connections(state)
    Enum.find(@player_ids, fn player_id -> !Map.has_key?(connections, player_id) end)
  end

  defp normalize_step(v), do: clamp(round(v), -1, 1)
  defp clamp(v, min, max), do: max(min, min(v, max))

  defp normalize_direction(dx, dy) when is_number(dx) and is_number(dy) do
    length = :math.sqrt(dx * dx + dy * dy)

    if length > 0 do
      {dx / length, dy / length}
    else
      nil
    end
  end

  defp normalize_direction(_, _), do: nil
  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_rate)

  defp broadcast_state(state),
    do: TankWarsWeb.Endpoint.broadcast("game:lobby", "state", public_state(state))

  defp display_name(n, id) do
    name = n |> to_string() |> String.trim()

    if name == "" or String.downcase(name) == "jugador" do
      default_player_name(id)
    else
      String.slice(name, 0, 24)
    end
  end

  defp default_player_name(id), do: %{"p1" => "Rojo", "p2" => "Azul", "p3" => "Verde"}[id]
end
