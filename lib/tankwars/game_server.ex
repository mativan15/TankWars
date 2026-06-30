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
  @duracion_partida 200
  @velocidad_proyectil 0.4
  @municion_maxima 5
  @duracion_recarga_ms 1_800
  @umbral_reposo_ms 180
  # Velocidad relativa: propio 100%, sin capturar 70%, enemigo 45%.
  @escala_movimiento 100
  @velocidad_sin_capturar 60
  @velocidad_enemigo 40
  @pulsos_efecto_impacto 6
  @vidas_maximas_torre 6

  @tiempo_fase_peligro 120
  @vidas_maximas_jefe 12
  @proporcion_muros_pinchos 0.20

  @espera_disparo_jefe_pulsos 30
  @velocidad_proyectil_jefe 0.4

  # power-up
  @pulsos_potenciador 30
  @duracion_escudo 50

  # API
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: @name)
  def estado_actual, do: GenServer.call(@name, :estado_actual)

  def registrar_jugador(client_id, connection_id),
    do: GenServer.call(@name, {:registrar_jugador, client_id, connection_id})

  def desconectar_jugador(player_id, connection_id),
    do: GenServer.cast(@name, {:desconectar_jugador, player_id, connection_id})

  def mover_jugador(player_id, dx, dy),
    do: GenServer.call(@name, {:mover_jugador, player_id, dx, dy})

  def apuntar_jugador(player_id, dx, dy),
    do: GenServer.call(@name, {:apuntar_jugador, player_id, dx, dy})

  def disparar_jugador(player_id, dx, dy),
    do: GenServer.call(@name, {:disparar_jugador, player_id, dx, dy})

  def start_game(mode \\ nil), do: GenServer.call(@name, {:start_game, mode})
  def pausa, do: GenServer.call(@name, :pausa)
  def reset, do: GenServer.call(@name, :reset)

  @impl true
  def init(:ok), do: {:ok, estado_inicial()}

  @impl true
  def handle_call(:estado_actual, _from, state), do: {:reply, estado_publico(state), state}

  @impl true
  def handle_call({:registrar_jugador, client_id, connection_id}, _from, state) do
    client_key = client_key(client_id, connection_id)

    case jugador_reservado_cliente(state, client_key) || id_jugador_disponible(state) do
      nil ->
        {:reply, {:error, :game_full, estado_publico(state)}, state}

      player_id ->
        connections =
          state
          |> conexiones_jugadores()
          |> Map.put(player_id, %{client_id: client_key, connection_id: connection_id})

        new_state = Map.put(state, :player_connections, connections)

        {:reply, {:ok, %{player_id: player_id, state: estado_publico(new_state)}}, new_state}
    end
  end

  @impl true
  def handle_call({:mover_jugador, player_id, dx, dy}, _from, state) do
    if state.game_state == :playing do
      new_state = aplicar_movimiento(state, player_id, dx, dy)
      broadcast_state(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:apuntar_jugador, player_id, dx, dy}, _from, state) do
    if state.game_state == :playing do
      new_state = aplicar_apuntado(state, player_id, dx, dy)
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:disparar_jugador, player_id, dx, dy}, _from, state) do
    if state.game_state == :playing do
      new_state = aplicar_disparo_jugador(state, player_id, dx, dy)
      broadcast_state(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:start_game, mode}, _from, state) do
    if state.game_state == :menu do
      game_mode =
        case mode do
          "sudden_death" -> :sudden_death
          :sudden_death -> :sudden_death
          "time_attack" -> :time_attack
          :time_attack -> :time_attack
          _ -> state.game_mode
        end

      new_state = %{
        state
        | game_state: :playing,
          game_mode: game_mode,
          last_time_check: System.monotonic_time(:millisecond)
      }

      programar_pulso()
      broadcast_state(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:pausa, _from, %{game_state: :playing} = state) do
    new_state = %{
      state
      | game_state: :paused,
        paused_at: System.monotonic_time(:millisecond)
    }

    broadcast_state(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:pausa, _from, %{game_state: :paused} = state) do
    current_time = System.monotonic_time(:millisecond)
    paused_duration = max(0, current_time - state.paused_at)

    new_state =
      state
      |> ajustar_fin_recargas(paused_duration)
      |> Map.merge(%{
        game_state: :playing,
        paused_at: nil,
        last_time_check: state.last_time_check + paused_duration
      })

    broadcast_state(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:pausa, _from, state),
    do: {:reply, :ok, state}

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = %{estado_inicial() | player_connections: conexiones_jugadores(state)}
    broadcast_state(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:desconectar_jugador, player_id, connection_id}, state) do
    connections = conexiones_jugadores(state)

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
      state = actualizar_recargas(state, current_time)
      state = generar_proyectiles_torres(state)
      state = generar_proyectiles_jefe(state)
      state = actualizar_proyectiles(state)
      state = actualizar_animaciones_impacto(state)
      state = actualizar_potenciadores(state)
      state = actualizar_efectos_jugadores(state)
      state = activar_fase_peligro(state)

      state =
        if partida_terminada?(state) do
          %{state | game_state: :game_over}
        else
          programar_pulso()
          state
        end

      broadcast_state(state)
      {:noreply, state}
    else
      if state.game_state == :paused, do: programar_pulso()
      {:noreply, state}
    end
  end

  defp estado_inicial do
    players = %{
      "p1" => nuevo_jugador("p1", "Rojo", 1, 1, "#FF315D", {1.0, 0.0}),
      "p2" => nuevo_jugador("p2", "Azul", 23, 1, "#2979FF", {-1.0, 0.0}),
      "p3" => nuevo_jugador("p3", "Verde", 12, 13, "#39FF88", {0.0, -1.0})
    }

    territory = Map.new(players, fn {id, p} -> {"#{p.x},#{p.y}", id} end)

    state_init = %{
      width: @width,
      height: @height,
      players: players,
      territory: territory,
      obstacles: %{},
      projectiles: [],
      hit_effects: [],
      powerups: [],
      powerup_timer: @pulsos_potenciador,
      player_connections: %{},
      time_left: @duracion_partida,
      game_state: :menu,
      game_mode: :time_attack,
      paused_at: nil,
      last_time_check: 0,
      danger_phase_started: false
    }

    generar_mapa_inicial(state_init)
  end

  defp nuevo_jugador(id, name, x, y, color, {aim_dx, aim_dy}) do
    %{
      id: id,
      name: name,
      x: x,
      y: y,
      spawn_x: x,
      spawn_y: y,
      color: color,
      lives: 5,
      hit_timer: 0,
      ammo: @municion_maxima,
      reload_ends_at: nil,
      reload_remaining_ms: @duracion_recarga_ms,
      reload_paused: false,
      moving_until: 0,
      movement_terrain: nil,
      movement_credit: 0,
      aim_dx: aim_dx,
      aim_dy: aim_dy
    }
  end

  defp generar_mapa_inicial(state) do
    state = generar_torre_aleatoria(state)
    state = generar_torre_aleatoria(state)
    state = generar_torre_aleatoria(state)
    state = generar_torre_aleatoria(state)
    Enum.reduce(1..11, state, fn _, acc -> generar_muro_cobertura(acc) end)
  end

  defp activar_fase_peligro(state) do
    if state.time_left <= @tiempo_fase_peligro and
         not Map.get(state, :danger_phase_started, false) do
      state
      |> Map.put(:danger_phase_started, true)
      |> generar_jefe_rojo()
      |> activar_muros_pinchos()
    else
      state
    end
  end

  defp generar_jefe_rojo(state) do
    key = buscar_coordenada_vacia(state)

    put_in(state, [:obstacles, key], %{
      type: "boss_rojo",
      lives: @vidas_maximas_jefe,
      max_lives: @vidas_maximas_jefe,
      shoot_timer: 0
    })
  end

  defp activar_muros_pinchos(state) do
    walls =
      state.obstacles
      |> Enum.filter(fn {_, obs} -> obs.type == "muro_gris" end)

    amount =
      walls
      |> length()
      |> Kernel.*(@proporcion_muros_pinchos)
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

  defp generar_torre_aleatoria(state) do
    key = buscar_coordenada_vacia(state)
    unique_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    put_in(state, [:obstacles, key], %{
      type: "torre_vida",
      id: unique_id,
      lives: @vidas_maximas_torre,
      max_lives: @vidas_maximas_torre
    })
  end

  defp generar_muro_cobertura(state) do
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
      generar_muro_cobertura(state)
    else
      Enum.reduce(coords, state, fn k, acc ->
        put_in(acc, [:obstacles, k], %{type: "muro_gris"})
      end)
    end
  end

  defp aplicar_movimiento(state, player_id, dx, dy) do
    case Map.fetch(state.players, player_id) do
      {:ok, %{lives: lives}} when lives <= 0 ->
        state

      {:ok, player} ->
        nx = limitar(player.x + normalizar_paso(dx), 0, @width - 1)
        ny = limitar(player.y + normalizar_paso(dy), 0, @height - 1)
        key = "#{nx},#{ny}"

        obstacle = Map.get(state.obstacles, key)

        cond do
          nx == player.x and ny == player.y ->
            state

          casilla_ocupada_por_otro?(state.players, player_id, nx, ny) ->
            state

          obstacle && obstacle.type == "boss_rojo" ->
            causar_danho_jugador(state, player_id, player, nx, ny)

          obstacle && obstacle.type == "muro_pincho" ->
            causar_danho_jugador(state, player_id, player, nx, ny)

          obstacle ->
            state

          true ->
            now = System.monotonic_time(:millisecond)
            terrain = terreno_destino(state.territory, key, player_id)
            {can_advance, player} = aplicar_factor_movimiento(player, terrain)

            player =
              player
              |> Map.put(:moving_until, now + @umbral_reposo_ms)
              |> pausar_recarga_jugador(now)

            state = put_in(state, [:players, player_id], player)

            if can_advance do
              state
              |> put_in([:players, player_id, :x], nx)
              |> put_in([:players, player_id, :y], ny)
              |> put_in([:territory, key], player_id)
              |> recoger_potenciador(player_id, nx, ny)
            else
              state
            end
        end

      :error ->
        state
    end
  end

  defp recoger_potenciador(state, player_id, x, y) do
    {collected, remaining} =
      state.powerups
      |> Enum.split_with(fn p -> p.x == x and p.y == y end)

    state = %{state | powerups: remaining}

    Enum.reduce(collected, state, fn powerup, acc ->
      aplicar_potenciador(acc, player_id, powerup.type)
    end)
  end

  defp aplicar_potenciador(state, player_id, "life") do
    state
    |> update_in([:players, player_id, :lives], fn lives ->
      min(5, lives + 1)
    end)
    |> put_in([:players, player_id, :life_effect_timer], 25)
  end

  defp aplicar_potenciador(state, player_id, "shield") do
    put_in(state, [:players, player_id, :shield_timer], @duracion_escudo)
  end

  defp aplicar_potenciador(state, player_id, "speed") do
    put_in(state, [:players, player_id, :speed_timer], 50)
  end

  defp aplicar_apuntado(state, player_id, dx, dy) do
    case Map.fetch(state.players, player_id) do
      {:ok, %{lives: lives}} when lives <= 0 ->
        state

      {:ok, _player} ->
        case normalizar_direccion(dx, dy) do
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

  defp aplicar_disparo_jugador(state, player_id, dx, dy) do
    case Map.fetch(state.players, player_id) do
      {:ok, %{lives: lives}} when lives <= 0 ->
        state

      {:ok, player} ->
        ammo = player |> Map.get(:ammo, @municion_maxima) |> min(@municion_maxima)

        if ammo <= 0 do
          state
        else
          case normalizar_direccion(dx, dy) do
            nil ->
              state

            {nx, ny} ->
              now = System.monotonic_time(:millisecond)
              remaining_ammo = ammo - 1
              reload_paused = remaining_ammo == 0 and jugador_en_movimiento?(player, now)

              reload_ends_at =
                cond do
                  remaining_ammo > 0 -> Map.get(player, :reload_ends_at)
                  reload_paused -> nil
                  true -> now + @duracion_recarga_ms
                end

              projectile = %{
                x: player.x + 0.5,
                y: player.y + 0.5,
                dx: nx * @velocidad_proyectil,
                dy: ny * @velocidad_proyectil,
                origin_id: player_id,
                origin_type: "player"
              }

              state
              |> put_in([:players, player_id, :ammo], remaining_ammo)
              |> put_in([:players, player_id, :reload_ends_at], reload_ends_at)
              |> put_in([:players, player_id, :reload_remaining_ms], @duracion_recarga_ms)
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

  defp generar_proyectiles_torres(state) do
    torres = Enum.filter(state.obstacles, fn {_, v} -> v.type == "torre_vida" end)

    Enum.reduce(torres, state, fn {pos, torre}, acc ->
      tiene_bala_activa = Enum.any?(acc.projectiles, fn p -> p.origin_id == torre.id end)

      if tiene_bala_activa do
        acc
      else
        [x, y] = String.split(pos, ",") |> Enum.map(&String.to_integer/1)

        {dx, dy} =
          Enum.random([
            {0, -@velocidad_proyectil},
            {0, @velocidad_proyectil},
            {-@velocidad_proyectil, 0},
            {@velocidad_proyectil, 0}
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

  defp generar_proyectiles_jefe(state) do
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
                dx: dx * @velocidad_proyectil_jefe,
                dy: dy * @velocidad_proyectil_jefe,
                origin_id: "boss:#{pos}",
                origin_type: "boss"
              }
            end)

          acc
          |> Map.update!(:projectiles, &(bullets ++ &1))
          |> put_in([:obstacles, pos, :shoot_timer], @espera_disparo_jefe_pulsos)
        end
      else
        acc
      end
    end)
  end

  defp actualizar_proyectiles(state) do
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
          causar_danho_jugador(acc, pid, player, cell_x, cell_y)

        obstacle && obstacle.type == "torre_vida" && p.origin_type == "player" ->
          causar_danho_torre(acc, key, obstacle, cell_x, cell_y)

        obstacle && obstacle.type == "boss_rojo" && p.origin_type == "player" ->
          causar_danho_jefe(acc, key, obstacle, cell_x, cell_y)

        obstacle && obstacle.type == "muro_gris" ->
          # rompe la bala contra muros grises de cobertura
          acc

        true ->
          Map.update!(acc, :projectiles, &[p | &1])
      end
    end)
  end

  defp actualizar_recargas(state, now) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id, actualizar_recarga_jugador(player, now)}
      end)

    %{state | players: players}
  end

  defp actualizar_recarga_jugador(player, now) do
    ammo = Map.get(player, :ammo, @municion_maxima)
    reload_ends_at = Map.get(player, :reload_ends_at)

    cond do
      ammo > 0 ->
        Map.put(player, :reload_paused, false)

      jugador_en_movimiento?(player, now) ->
        pausar_recarga_jugador(player, now)

      reload_ends_at && now >= reload_ends_at ->
        Map.merge(player, %{
          ammo: @municion_maxima,
          reload_ends_at: nil,
          reload_remaining_ms: @duracion_recarga_ms,
          reload_paused: false
        })

      is_nil(reload_ends_at) ->
        remaining = Map.get(player, :reload_remaining_ms, @duracion_recarga_ms)

        player
        |> Map.put(:reload_ends_at, now + remaining)
        |> Map.put(:reload_paused, false)

      true ->
        Map.put(player, :reload_paused, false)
    end
  end

  defp pausar_recarga_jugador(player, now) do
    if Map.get(player, :ammo, @municion_maxima) <= 0 do
      remaining =
        case Map.get(player, :reload_ends_at) do
          nil -> Map.get(player, :reload_remaining_ms, @duracion_recarga_ms)
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

  defp jugador_en_movimiento?(player, now),
    do: now < Map.get(player, :moving_until, 0)

  defp terreno_destino(territory, key, player_id) do
    case Map.get(territory, key) do
      ^player_id -> :own
      nil -> :unclaimed
      _other_player -> :enemy
    end
  end

  defp aplicar_factor_movimiento(player, terrain) do
    if Map.get(player, :speed_timer, 0) > 0 do
      {true, Map.merge(player, %{movement_terrain: :speed, movement_credit: 0})}
    else
      aplicar_factor_movimiento_normal(player, terrain)
    end
  end

  defp aplicar_factor_movimiento_normal(player, :own) do
    {true, Map.merge(player, %{movement_terrain: :own, movement_credit: 0})}
  end

  defp aplicar_factor_movimiento_normal(player, terrain) do
    if Map.get(player, :movement_terrain) != terrain do
      {true, Map.merge(player, %{movement_terrain: terrain, movement_credit: 0})}
    else
      weight =
        if terrain == :enemy, do: @velocidad_enemigo, else: @velocidad_sin_capturar

      credit = Map.get(player, :movement_credit, 0) + weight

      if credit >= @escala_movimiento do
        {true, Map.put(player, :movement_credit, credit - @escala_movimiento)}
      else
        {false, Map.put(player, :movement_credit, credit)}
      end
    end
  end

  defp ajustar_fin_recargas(state, paused_duration) do
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

  defp actualizar_animaciones_impacto(state) do
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

  defp causar_danho_torre(state, key, tower, hit_x, hit_y) do
    lives = tower |> Map.get(:lives, @vidas_maximas_torre) |> max(0)
    max_lives = Map.get(tower, :max_lives, @vidas_maximas_torre)
    new_lives = max(0, lives - 1)

    effect = %{
      x: hit_x,
      y: hit_y,
      color: "#f5c542",
      timer: @pulsos_efecto_impacto,
      max_timer: @pulsos_efecto_impacto
    }

    state = Map.update(state, :hit_effects, [effect], fn effects -> [effect | effects] end)

    if new_lives == 0 do
      state
      |> update_in([:obstacles], &Map.delete(&1, key))
      |> generar_torre_aleatoria()
    else
      put_in(state, [:obstacles, key], %{tower | lives: new_lives, max_lives: max_lives})
    end
  end

  defp causar_danho_jefe(state, key, boss, hit_x, hit_y) do
    lives = boss |> Map.get(:lives, @vidas_maximas_jefe) |> max(0)
    max_lives = Map.get(boss, :max_lives, @vidas_maximas_jefe)
    new_lives = max(0, lives - 1)

    effect = %{
      x: hit_x,
      y: hit_y,
      color: "#ff0000",
      timer: @pulsos_efecto_impacto,
      max_timer: @pulsos_efecto_impacto
    }

    state = Map.update(state, :hit_effects, [effect], fn effects -> [effect | effects] end)

    if new_lives == 0 do
      state
      |> put_in([:obstacles, key], %{type: "muro_pincho"})
      |> generar_jefe_rojo()
    else
      put_in(state, [:obstacles, key], %{boss | lives: new_lives, max_lives: max_lives})
    end
  end

  defp causar_danho_jugador(state, player_id, player, hit_x, hit_y) do
    if Map.get(player, :shield_timer, 0) > 0 do
      state
    else
      lives = max(0, player.lives - 1)

      player =
        player
        |> Map.put(:lives, lives)
        |> Map.put(:hit_timer, @pulsos_efecto_impacto)
        |> Map.put(:moving_until, 0)
        |> Map.put(:movement_terrain, nil)
        |> Map.put(:movement_credit, 0)

      {x, y} =
        if lives > 0 do
          posicion_reaparicion(state, player_id, player)
        else
          {player.x, player.y}
        end

      player = Map.merge(player, %{x: x, y: y})

      effect = efecto_impacto(player, hit_x, hit_y)

      state
      |> Map.update(:hit_effects, [effect], fn effects -> [effect | effects] end)
      |> put_in([:players, player_id], player)
    end
  end

  defp actualizar_potenciadores(state) do
    timer = Map.get(state, :powerup_timer, @pulsos_potenciador)

    cond do
      timer > 0 ->
        %{state | powerup_timer: timer - 1}

      length(Map.get(state, :powerups, [])) >= 3 ->
        %{state | powerup_timer: @pulsos_potenciador}

      true ->
        key = buscar_coordenada_vacia(state)
        [x, y] = String.split(key, ",") |> Enum.map(&String.to_integer/1)

        powerup = %{
          x: x,
          y: y,
          type: Enum.random(["life", "shield", "speed"])
        }

        state
        |> Map.update(:powerups, [powerup], fn list -> [powerup | list] end)
        |> Map.put(:powerup_timer, @pulsos_potenciador)
    end
  end

  defp actualizar_efectos_jugadores(state) do
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

  defp efecto_impacto(player, x, y) do
    %{
      x: x,
      y: y,
      color: player.color,
      timer: @pulsos_efecto_impacto,
      max_timer: @pulsos_efecto_impacto
    }
  end

  defp contar_jugadores_vivos(state) do
    Enum.count(state.players, fn {_, p} -> p.lives > 0 end)
  end

  defp partida_terminada?(state) do
    case Map.get(state, :game_mode, :time_attack) do
      :time_attack ->
        state.time_left <= 0 or todos_jugadores_muertos?(state)

      :sudden_death ->
        contar_jugadores_vivos(state) <= 1
    end
  end

  defp todos_jugadores_muertos?(state) do
    players = Map.values(state.players)

    players != [] and
      Enum.all?(players, fn player ->
        player.lives <= 0
      end)
  end

  defp buscar_coordenada_vacia(state) do
    rx = Enum.random(0..(@width - 1))
    ry = Enum.random(0..(@height - 1))
    key = "#{rx},#{ry}"

    collision =
      Map.has_key?(state.obstacles, key) or
        Enum.any?(state.players, fn {_, p} -> p.x == rx and p.y == ry end)

    if collision, do: buscar_coordenada_vacia(state), else: key
  end

  defp posicion_reaparicion(state, player_id, player) do
    spawn_x = Map.get(player, :spawn_x, player.x)
    spawn_y = Map.get(player, :spawn_y, player.y)

    positions =
      for y <- 0..(@height - 1),
          x <- 0..(@width - 1),
          not Map.has_key?(state.obstacles, "#{x},#{y}"),
          not casilla_ocupada_por_otro?(state.players, player_id, x, y),
          do: {x, y}

    Enum.min_by(
      positions,
      fn {x, y} -> abs(x - spawn_x) + abs(y - spawn_y) end,
      fn -> {player.x, player.y} end
    )
  end

  defp casilla_ocupada_por_otro?(players, player_id, x, y) do
    Enum.any?(players, fn {other_id, other} ->
      other_id != player_id and other.x == x and other.y == y
    end)
  end

  defp estado_publico(state) do
    %{
      width: state.width,
      height: state.height,
      players: Map.new(state.players, fn {id, player} -> {id, jugador_publico(player)} end),
      territory: state.territory,
      obstacles:
        Map.new(state.obstacles, fn {position, obstacle} ->
          {position, Map.take(obstacle, [:type, :lives, :max_lives])}
        end),
      projectiles: Enum.map(state.projectiles, &Map.take(&1, [:x, :y])),
      hit_effects:
        Enum.map(state.hit_effects, &Map.take(&1, [:x, :y, :color, :timer, :max_timer])),
      powerups: Enum.map(state.powerups, &Map.take(&1, [:x, :y, :type])),
      time_left: state.time_left,
      game_state: state.game_state,
      game_mode: state.game_mode
    }
  end

  defp jugador_publico(player) do
    ammo = Map.get(player, :ammo, @municion_maxima)
    ammo = if is_number(ammo), do: min(ammo, @municion_maxima), else: @municion_maxima

    player
    |> Map.take([
      :id,
      :name,
      :x,
      :y,
      :color,
      :lives,
      :hit_timer,
      :reload_paused,
      :aim_dx,
      :aim_dy,
      :shield_timer,
      :speed_timer,
      :life_effect_timer
    ])
    |> Map.put(:ammo, ammo)
    |> Map.put(:max_ammo, @municion_maxima)
  end

  defp conexiones_jugadores(state), do: Map.get(state, :player_connections, %{})

  defp client_key(nil, connection_id), do: {:connection, connection_id}
  defp client_key("", connection_id), do: {:connection, connection_id}
  defp client_key(client_id, _connection_id), do: {:client, client_id}

  defp jugador_reservado_cliente(state, client_key) do
    state
    |> conexiones_jugadores()
    |> Enum.find_value(fn {player_id, connection} ->
      if connection.client_id == client_key, do: player_id
    end)
  end

  defp id_jugador_disponible(state) do
    connections = conexiones_jugadores(state)
    Enum.find(@player_ids, fn player_id -> !Map.has_key?(connections, player_id) end)
  end

  defp normalizar_paso(v), do: limitar(round(v), -1, 1)
  defp limitar(v, min, max), do: max(min, min(v, max))

  defp normalizar_direccion(dx, dy) when is_number(dx) and is_number(dy) do
    length = :math.sqrt(dx * dx + dy * dy)

    if length > 0 do
      {dx / length, dy / length}
    else
      nil
    end
  end

  defp normalizar_direccion(_, _), do: nil
  defp programar_pulso, do: Process.send_after(self(), :tick, @tick_rate)

  defp broadcast_state(state),
    do: TankWarsWeb.Endpoint.broadcast("game:lobby", "state", estado_publico(state))
end
