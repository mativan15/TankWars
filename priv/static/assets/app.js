(() => {
  const COLORS = {
    arenaTop: "#160b2a",
    arenaBottom: "#07101d",
    cyan: "#00f5ff",
    blue: "#008cff",
    danger: "#ff315d",
    gold: "#f9f871",
    green: "#39ff88",
    towerHealth: "#00ff66",
    wall: "#211331",
    wallHighlight: "#39244d",
    wallBorder: "#a855f7",
    ink: "#07040f",
    text: "#f4faff"
  };

  const canvas = document.querySelector("#arena");
  const ctx = canvas.getContext("2d");
  const playerEl = document.querySelector("#player");
  const playerBox = document.querySelector("#player-box");
  const territoryLeaderboardEl = document.querySelector("#territory-leaderboard");
  const livesEl = document.querySelector("#hud-lives");
  const timerEl = document.querySelector("#hud-timer");
  const ammoEl = document.querySelector("#hud-ammo");
  const pauseButton = document.querySelector("#pause-btn");
  const resetButton = document.querySelector("#global-reset-btn");

  const arenaWrap = document.querySelector(".arena-wrap");

  const menuOverlay = document.createElement("div");
  menuOverlay.id = "menu-overlay";
  arenaWrap.appendChild(menuOverlay);

  const topic = "game:lobby";
  const joinRef = "1";
  let socket = null;
  let nextRef = 1;
  let connected = false;
  let playerId = null;
  let state = null;
  let joinRejected = false;
  let joinError = "";
  let lastAimSentAt = 0;
  let lastLeaderboardSignature = "";
  const aimSendIntervalMs = 50;
  const clientId = getClientId();

  function updateHud() {
    updateTerritoryLeaderboard();
    const canControlGame = connected && !joinRejected && Boolean(playerId && state);
    const isPaused = state && state.game_state === "paused";

    pauseButton.disabled = !canControlGame || !["playing", "paused"].includes(state.game_state);
    pauseButton.textContent = isPaused ? "▶ Reanudar" : "⏸ Pausar";
    pauseButton.classList.toggle("is-active", Boolean(isPaused));
    pauseButton.setAttribute("aria-pressed", String(Boolean(isPaused)));
    resetButton.disabled = !canControlGame;

    if (state && playerId && state.players[playerId]) {
      playerEl.textContent = state.players[playerId].name;
      playerEl.style.color = state.players[playerId].color;
      playerBox.style.setProperty("--card-accent", state.players[playerId].color);
      
      const currentLives = state.players[playerId].lives;
      livesEl.textContent = "❤️".repeat(currentLives) + "🖤".repeat(5 - currentLives);
      updateAmmoHud(state.players[playerId]);
    } else {
      playerEl.style.removeProperty("color");
      playerBox.style.removeProperty("--card-accent");
      livesEl.textContent = "🖤🖤🖤🖤🖤";
      ammoEl.textContent = "○○○○○";
      ammoEl.setAttribute("aria-label", "Sin munición asignada");
    }

    if (state) {
      if (state.game_state === "menu") {
        menuOverlay.style.display = "flex";
        menuOverlay.innerHTML = `
          <h2 class="overlay-title">Tank Wars</h2>
          <p class="overlay-copy">Esquiva los proyectiles, tienes 5 vidas!</p>
          <button id="start-btn" class="overlay-button">INICIAR PARTIDA</button>
        `;
        document.querySelector("#start-btn").addEventListener("click", () => push(topic, "start_game", {}));
        timerEl.textContent = state.time_left + "s";
      } else if (state.game_state === "playing") {
        menuOverlay.style.display = "none";
        timerEl.textContent = state.time_left + "s";
      } else if (state.game_state === "paused") {
        menuOverlay.style.display = "flex";
        menuOverlay.innerHTML = `
          <h2 class="overlay-title">PAUSA</h2>
          <p class="overlay-copy">La partida está pausada para todos</p>
        `;
        timerEl.textContent = state.time_left + "s";
      } else if (state.game_state === "game_over") {
        menuOverlay.style.display = "flex";
        menuOverlay.innerHTML = `
          <h2 class="overlay-title overlay-title--danger">FIN DE LA PARTIDA</h2>
          <p class="overlay-copy">Queda un solo tanque con vida o se acabó el tiempo</p>
          <button id="reset-btn" class="overlay-button overlay-button--secondary">REINICIAR ARENA</button>
        `;
        document.querySelector("#reset-btn").addEventListener("click", () => push(topic, "reset", {}));
      }
    }

    if (joinRejected) showJoinError(joinError);
  }

  function getClientId() {
    const key = "tankwars-client-id";
    const fallback = () => `client-${Date.now()}-${Math.random().toString(16).slice(2)}`;

    try {
      let id = window.sessionStorage.getItem(key);
      if (!id) {
        id = window.crypto && window.crypto.randomUUID ? window.crypto.randomUUID() : fallback();
        window.sessionStorage.setItem(key, id);
      }
      return id;
    } catch (_error) {
      return fallback();
    }
  }

  function showJoinError(message) {
    menuOverlay.style.display = "flex";
    menuOverlay.innerHTML = `
      <h2 class="overlay-title overlay-title--danger">PARTIDA LLENA</h2>
      <p class="overlay-copy">${message || "Los tres jugadores ya estan ocupados."}</p>
    `;
  }

  function updateTerritoryLeaderboard() {
    if (!state || !state.players || !state.territory) {
      territoryLeaderboardEl.innerHTML = `<li class="territory-empty">Esperando jugadores</li>`;
      lastLeaderboardSignature = "";
      return;
    }

    const territoryCounts = Object.values(state.territory).reduce((counts, owner) => {
      counts[owner] = (counts[owner] || 0) + 1;
      return counts;
    }, {});

    const ranking = Object.values(state.players)
      .map(player => ({
        id: player.id,
        name: player.name,
        color: player.color,
        count: territoryCounts[player.id] || 0
      }))
      .sort((a, b) => b.count - a.count || a.id.localeCompare(b.id));

    const signature = JSON.stringify({ playerId, ranking });
    if (signature === lastLeaderboardSignature) return;
    lastLeaderboardSignature = signature;

    const topCount = ranking.length > 0 ? ranking[0].count : 0;
    const leaders = ranking.filter(entry => entry.count === topCount).length;

    territoryLeaderboardEl.replaceChildren(...ranking.map(entry => {
      const rank = ranking.findIndex(candidate => candidate.count === entry.count) + 1;

      const row = document.createElement("li");
      row.className = "territory-row";
      if (entry.id === playerId) row.classList.add("is-self");
      if (rank === 1) row.classList.add("is-leading");

      const position = document.createElement("span");
      position.className = "territory-rank";
      position.textContent = String(rank);

      const marker = document.createElement("span");
      marker.className = "territory-marker";
      marker.style.backgroundColor = entry.color;
      marker.style.boxShadow = `0 0 7px ${entry.color}`;

      const name = document.createElement("span");
      name.className = "territory-name";
      name.textContent = entry.id === playerId ? `${entry.name} (tú)` : entry.name;

      const status = document.createElement("span");
      status.className = "territory-status";
      if (rank === 1) status.textContent = leaders === 1 ? "LÍDER" : "EMPATE";

      const score = document.createElement("strong");
      score.className = "territory-score";
      score.textContent = `${entry.count} celdas`;

      row.append(position, marker, name, status, score);
      return row;
    }));
  }

  function updateAmmoHud(player) {
    const maxAmmo = player.max_ammo || 5;
    const ammo = Number.isFinite(player.ammo)
      ? Math.max(0, Math.min(maxAmmo, Math.trunc(player.ammo)))
      : maxAmmo;
    const bullets = "●".repeat(ammo) + "○".repeat(maxAmmo - ammo);

    if (ammo <= 0) {
      ammoEl.textContent = `${bullets} ${player.reload_paused ? "⏸" : "↻"}`;
      ammoEl.setAttribute("aria-label", player.reload_paused ? "Recarga pausada" : "Recargando");
      ammoEl.style.color = COLORS.danger;
      ammoEl.style.textShadow = "0 0 8px rgba(255, 49, 93, 0.55)";
    } else {
      ammoEl.textContent = bullets;
      ammoEl.setAttribute("aria-label", `${ammo} de ${maxAmmo} balas`);
      ammoEl.style.color = COLORS.blue;
      ammoEl.style.textShadow = "0 0 8px rgba(0, 140, 255, 0.5)";
    }
  }

  function push(topicName, event, payload) {
    if (!socket || socket.readyState !== WebSocket.OPEN) return;
    socket.send(JSON.stringify([joinRef, String(nextRef++), topicName, event, payload]));
  }

  function connect() {
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    socket = new WebSocket(`${protocol}://${window.location.host}/socket/websocket?vsn=2.0.0`);

    socket.addEventListener("open", () => {
      connected = true;
      joinRejected = false;
      joinError = "";
      updateHud();
      push(topic, "phx_join", { name: "Jugador", client_id: clientId });
    });

    socket.addEventListener("message", (event) => {
      const [,, messageTopic, messageEvent, payload] = JSON.parse(event.data);
      if (messageTopic !== topic && messageTopic !== "phoenix") return;

      if (messageEvent === "phx_reply" && payload.status === "error") {
        joinRejected = true;
        playerId = null;
        joinError = payload.response && payload.response.reason ? payload.response.reason : "No hay jugadores disponibles.";
        if (payload.response && payload.response.state) state = payload.response.state;
        updateHud();
        draw();
        return;
      }

      if (messageEvent === "phx_reply" && payload.status === "ok" && payload.response.state) {
        playerId = payload.response.player_id;
        state = payload.response.state;
      }
      if (messageEvent === "state") {
        state = payload;
      }
      updateHud();
      draw();
    });

    socket.addEventListener("close", () => {
      connected = false;
      updateHud();
      if (!joinRejected) window.setTimeout(connect, 1200);
    });
  }

  function handleKeydown(event) {
    if (joinRejected || !state || state.game_state !== "playing" || !playerId) return;
    const player = state.players[playerId];
    if (!player || player.lives <= 0) return;

    const key = event.key.toLowerCase();
    const moves = {
      arrowup: [0, -1], w: [0, -1],
      arrowdown: [0, 1], s: [0, 1],
      arrowleft: [-1, 0], a: [-1, 0],
      arrowright: [1, 0], d: [1, 0]
    };
    if (!moves[key]) return;
    event.preventDefault();
    push(topic, "move_player", { dx: moves[key][0], dy: moves[key][1] });
  }

  function aimVectorFromMouseEvent(event) {
    if (joinRejected || !state || !playerId) return null;

    const player = state.players[playerId];
    if (!player || player.lives <= 0) return null;

    const rect = canvas.getBoundingClientRect();
    const cellW = rect.width / state.width;
    const cellH = rect.height / state.height;
    const mouseX = event.clientX - rect.left;
    const mouseY = event.clientY - rect.top;
    const playerX = (player.x + 0.5) * cellW;
    const playerY = (player.y + 0.5) * cellH;
    const dx = (mouseX - playerX) / cellW;
    const dy = (mouseY - playerY) / cellH;

    if (Math.hypot(dx, dy) === 0) return null;
    return { dx, dy };
  }

  function updateLocalAim(dx, dy) {
    const player = state && playerId ? state.players[playerId] : null;
    if (!player) return;

    const length = Math.hypot(dx, dy);
    if (length === 0) return;

    player.aim_dx = dx / length;
    player.aim_dy = dy / length;
  }

  function handleCanvasMouseMove(event) {
    if (!state || state.game_state !== "playing" || !playerId) return;

    const aim = aimVectorFromMouseEvent(event);
    if (!aim) return;

    updateLocalAim(aim.dx, aim.dy);
    draw();

    const now = performance.now();
    if (now - lastAimSentAt >= aimSendIntervalMs) {
      lastAimSentAt = now;
      push(topic, "aim_player", aim);
    }
  }

  function handleCanvasMouseDown(event) {
    if (event.button !== 0 || !state || state.game_state !== "playing" || !playerId) return;

    const aim = aimVectorFromMouseEvent(event);
    if (!aim) return;

    event.preventDefault();
    updateLocalAim(aim.dx, aim.dy);
    push(topic, "aim_player", aim);
    push(topic, "shoot_player", aim);
    draw();
  }

  function resizeCanvas() {
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = Math.max(1, Math.round(rect.width * dpr));
    canvas.height = Math.max(1, Math.round(rect.height * dpr));
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    draw();
  }

  function draw() {
    const rect = canvas.getBoundingClientRect();
    ctx.clearRect(0, 0, rect.width, rect.height);
    
    drawBackground(rect.width, rect.height);
    if (!state) return;

    const cellW = rect.width / state.width;
    const cellH = rect.height / state.height;

    drawTerritory(cellW, cellH);
    drawObstacles(cellW, cellH);
    drawProjectiles(cellW, cellH);
    drawGrid(rect.width, rect.height, cellW, cellH);
    drawHitEffects(cellW, cellH);
    drawPlayers(cellW, cellH);
  }

  function drawBackground(width, height) {
    const background = ctx.createLinearGradient(0, 0, width, height);
    background.addColorStop(0, COLORS.arenaTop);
    background.addColorStop(0.55, "#0c0a20");
    background.addColorStop(1, COLORS.arenaBottom);
    ctx.fillStyle = background;
    ctx.fillRect(0, 0, width, height);
  }

  function drawTerritory(cellW, cellH) {
    Object.entries(state.territory).forEach(([cell, owner]) => {
      const [x, y] = cell.split(",").map(Number);
      const player = state.players[owner];
      if (!player) return;
      ctx.fillStyle = withAlpha(player.color, 0.22);
      ctx.fillRect(x * cellW, y * cellH, cellW, cellH);
    });

    Object.entries(state.territory).forEach(([cell, owner]) => {
      const [x, y] = cell.split(",").map(Number);
      const player = state.players[owner];
      if (!player) return;

      const xPos = x * cellW;
      const yPos = y * cellH;
      const neighbors = {
        top: state.territory[`${x},${y - 1}`],
        right: state.territory[`${x + 1},${y}`],
        bottom: state.territory[`${x},${y + 1}`],
        left: state.territory[`${x - 1},${y}`]
      };

      ctx.save();
      ctx.beginPath();
      if (neighbors.top !== owner) {
        ctx.moveTo(xPos, yPos);
        ctx.lineTo(xPos + cellW, yPos);
      }
      if (neighbors.right !== owner) {
        ctx.moveTo(xPos + cellW, yPos);
        ctx.lineTo(xPos + cellW, yPos + cellH);
      }
      if (neighbors.bottom !== owner) {
        ctx.moveTo(xPos + cellW, yPos + cellH);
        ctx.lineTo(xPos, yPos + cellH);
      }
      if (neighbors.left !== owner) {
        ctx.moveTo(xPos, yPos + cellH);
        ctx.lineTo(xPos, yPos);
      }
      ctx.strokeStyle = withAlpha(player.color, 0.85);
      ctx.lineWidth = 1.5;
      ctx.shadowColor = player.color;
      ctx.shadowBlur = 6;
      ctx.stroke();
      ctx.restore();
    });
  }

  function drawObstacles(cellW, cellH) {
    if (!state.obstacles) return;
    Object.entries(state.obstacles).forEach(([cell, obs]) => {
      const [x, y] = cell.split(",").map(Number);
      const xPos = x * cellW;
      const yPos = y * cellH;

      if (obs.type === "muro_gris") {
        ctx.save();
        const wallGradient = ctx.createLinearGradient(xPos, yPos, xPos + cellW, yPos + cellH);
        wallGradient.addColorStop(0, COLORS.wallHighlight);
        wallGradient.addColorStop(1, COLORS.wall);
        ctx.fillStyle = wallGradient;
        ctx.strokeStyle = COLORS.wallBorder;
        ctx.lineWidth = 1;
        ctx.shadowColor = "rgba(0, 245, 255, 0.45)";
        ctx.shadowBlur = 4;
        roundRect(ctx, xPos + 2, yPos + 2, cellW - 4, cellH - 4, 4);
        ctx.fill(); ctx.stroke();

        ctx.shadowBlur = 0;
        ctx.strokeStyle = "rgba(0, 245, 255, 0.6)";
        ctx.beginPath();
        ctx.moveTo(xPos + 7, yPos + 4);
        ctx.lineTo(xPos + cellW - 7, yPos + 4);
        ctx.stroke();
        ctx.restore();
      } else if (obs.type === "torre_vida") {
        ctx.save();
        ctx.fillStyle = COLORS.gold;
        ctx.shadowColor = "rgba(249, 248, 113, 0.7)";
        ctx.shadowBlur = 10;
        roundRect(ctx, xPos + 3, yPos + 3, cellW - 6, cellH - 6, 6);
        ctx.fill();
        ctx.shadowBlur = 0;

        ctx.fillStyle = COLORS.ink;
        
        // Ceja Izquierda Obstaculo
        ctx.beginPath();
        ctx.moveTo(xPos + cellW * 0.2, yPos + cellH * 0.2);
        ctx.lineTo(xPos + cellW * 0.45, yPos + cellH * 0.38);
        ctx.lineTo(xPos + cellW * 0.45, yPos + cellH * 0.48);
        ctx.lineTo(xPos + cellW * 0.2, yPos + cellH * 0.3);
        ctx.closePath(); ctx.fill();

        // Ceja Derecha Obstaculo
        ctx.beginPath();
        ctx.moveTo(xPos + cellW * 0.8, yPos + cellH * 0.2);
        ctx.lineTo(xPos + cellW * 0.55, yPos + cellH * 0.38);
        ctx.lineTo(xPos + cellW * 0.55, yPos + cellH * 0.48);
        ctx.lineTo(xPos + cellW * 0.8, yPos + cellH * 0.3);
        ctx.closePath(); ctx.fill();

        ctx.fillStyle = "#ff1744";
        ctx.fillRect(xPos + cellW * 0.24, yPos + cellH * 0.42, cellW * 0.16, cellH * 0.14);
        ctx.fillRect(xPos + cellW * 0.60, yPos + cellH * 0.42, cellW * 0.16, cellH * 0.14);

        ctx.fillStyle = COLORS.ink;
        ctx.fillRect(xPos + cellW * 0.30, yPos + cellH * 0.46, cellW * 0.08, cellH * 0.08);
        ctx.fillRect(xPos + cellW * 0.62, yPos + cellH * 0.46, cellW * 0.08, cellH * 0.08);
        ctx.fillStyle = COLORS.ink;
        ctx.fillRect(xPos + cellW * 0.32, yPos + cellH * 0.70, cellW * 0.36, cellH * 0.12);
        drawTowerLifeIndicator(obs, xPos, yPos, cellW, cellH);
        ctx.restore();
      }
    });
  }

  function drawTowerLifeIndicator(tower, xPos, yPos, cellW, cellH) {
    const maxLives = tower.max_lives || 6;
    const lives = Number.isFinite(tower.lives) ? tower.lives : maxLives;
    const ratio = Math.max(0, Math.min(1, lives / maxLives));
    const barWidth = cellW * 0.72;
    const barHeight = Math.max(5, cellH * 0.13 - 1);
    const barX = xPos + (cellW - barWidth) / 2;
    const barY = yPos + Math.max(0, cellH * 0.025 - 2);
    const framePadding = 2;

    ctx.save();
    ctx.fillStyle = "rgba(4, 8, 14, 0.96)";
    roundRect(
      ctx,
      barX - framePadding,
      barY - framePadding,
      barWidth + framePadding * 2,
      barHeight + framePadding * 2,
      4
    );
    ctx.fill();

    ctx.fillStyle = ratio > 0.35 ? COLORS.towerHealth : COLORS.danger;
    ctx.shadowColor = ratio > 0.35 ? COLORS.towerHealth : COLORS.danger;
    ctx.shadowBlur = 8;
    roundRect(ctx, barX, barY, barWidth * ratio, barHeight, 3);
    ctx.fill();

    ctx.shadowBlur = 0;
    ctx.strokeStyle = "rgba(244, 250, 255, 0.82)";
    ctx.lineWidth = 1.5;
    roundRect(
      ctx,
      barX - framePadding,
      barY - framePadding,
      barWidth + framePadding * 2,
      barHeight + framePadding * 2,
      4
    );
    ctx.stroke();
    ctx.restore();
  }

  function drawProjectiles(cellW, cellH) {
    if (!state.projectiles) return;
    state.projectiles.forEach(p => {
      ctx.save();
      ctx.fillStyle = COLORS.danger;
      ctx.shadowColor = COLORS.danger;
      ctx.shadowBlur = 14;
      ctx.beginPath();
      ctx.arc(p.x * cellW, p.y * cellH, 6, 0, Math.PI * 2);
      ctx.fill();
      
      ctx.shadowColor = COLORS.gold;
      ctx.shadowBlur = 7;
      ctx.fillStyle = COLORS.gold;
      ctx.beginPath();
      ctx.arc(p.x * cellW, p.y * cellH, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    });
  }

  function drawHitEffects(cellW, cellH) {
    if (!state.hit_effects) return;

    state.hit_effects.forEach(effect => {
      const progress = effect.timer / (effect.max_timer || 6);
      const cx = effect.x * cellW + cellW / 2;
      const cy = effect.y * cellH + cellH / 2;
      const radius = Math.min(cellW, cellH) * (0.25 + (1 - progress) * 0.45);

      ctx.save();
      ctx.globalAlpha = Math.max(0, progress);
      ctx.strokeStyle = effect.color || COLORS.text;
      ctx.lineWidth = 2;
      ctx.shadowColor = effect.color || COLORS.cyan;
      ctx.shadowBlur = 10;
      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.stroke();

      ctx.fillStyle = "rgba(255, 255, 255, 0.6)";
      ctx.beginPath();
      ctx.arc(cx, cy, Math.max(2, radius * 0.18), 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    });
  }

  function drawGrid(width, height, cellW, cellH) {
    ctx.save();
    ctx.strokeStyle = "rgba(0, 245, 255, 0.10)";
    ctx.lineWidth = 0.75;
    for (let x = 0; x <= state.width; x++) {
      ctx.beginPath(); ctx.moveTo(x * cellW, 0); ctx.lineTo(x * cellW, height); ctx.stroke();
    }
    for (let y = 0; y <= state.height; y++) {
      ctx.beginPath(); ctx.moveTo(0, y * cellH); ctx.lineTo(width, y * cellH); ctx.stroke();
    }
    ctx.restore();
  }

  function drawPlayers(cellW, cellH) {
    Object.values(state.players).forEach((player) => {
      const cx = player.x * cellW + cellW / 2;
      const cy = player.y * cellH + cellH / 2;
      const size = Math.min(cellW, cellH) * 0.58;

      if (player.lives <= 0) {
        drawDestroyedTank(player, cx, cy, size);
        return;
      }

      ctx.save();
      ctx.translate(cx, cy);

      ctx.fillStyle = player.hit_timer > 0 ? "#ffffff" : player.color;
      ctx.shadowColor = player.color;
      ctx.shadowBlur = player.id === playerId ? 14 : 9;
      roundRect(ctx, -size / 2, -size / 2, size, size, 6);
      ctx.fill();

      if (player.id === playerId) {
        ctx.strokeStyle = withAlpha(player.color, 0.95);
        ctx.lineWidth = 6;
        ctx.stroke();
        ctx.shadowBlur = 0;
        ctx.strokeStyle = "#ffffff";
        ctx.lineWidth = 2.5;
        ctx.stroke();
      } else {
        ctx.strokeStyle = "rgba(255, 255, 255, 0.52)";
        ctx.lineWidth = 1.5;
        ctx.stroke();
      }

      drawTankCannon(player, size);
      ctx.restore();
    });
  }

  function drawTankCannon(player, size) {
    const aimDx = Number.isFinite(player.aim_dx) ? player.aim_dx : 1;
    const aimDy = Number.isFinite(player.aim_dy) ? player.aim_dy : 0;
    const angle = Math.atan2(aimDy, aimDx);

    ctx.save();
    ctx.rotate(angle);
    ctx.shadowBlur = 0;
    ctx.fillStyle = COLORS.ink;
    roundRect(ctx, size * 0.02, -size * 0.11, size * 0.62, size * 0.22, 3);
    ctx.fill();
    ctx.restore();
  }

  function drawDestroyedTank(player, cx, cy, size) {
    ctx.save();
    ctx.translate(cx, cy);

    ctx.fillStyle = "#130f1d";
    ctx.strokeStyle = withAlpha(player.color, 0.55);
    ctx.lineWidth = 2;
    ctx.shadowColor = player.color;
    ctx.shadowBlur = 6;
    roundRect(ctx, -size / 2, -size / 2, size, size, 6);
    ctx.fill();
    ctx.stroke();

    ctx.shadowColor = COLORS.danger;
    ctx.strokeStyle = COLORS.danger;
    ctx.lineWidth = Math.max(2, size * 0.08);
    ctx.beginPath();
    ctx.moveTo(-size * 0.28, -size * 0.28);
    ctx.lineTo(size * 0.28, size * 0.28);
    ctx.moveTo(size * 0.28, -size * 0.28);
    ctx.lineTo(-size * 0.28, size * 0.28);
    ctx.stroke();

    ctx.fillStyle = "rgba(0, 0, 0, 0.45)";
    roundRect(ctx, size * 0.05, -size * 0.12, size * 0.55, size * 0.24, 3);
    ctx.fill();
    ctx.restore();
  }

  function roundRect(context, x, y, width, height, radius) {
    const r = Math.min(radius, width / 2, height / 2);
    context.beginPath(); context.moveTo(x + r, y);
    context.arcTo(x + width, y, x + width, y + height, r);
    context.arcTo(x + width, y + height, x, y + height, r);
    context.arcTo(x, y + height, x, y, r);
    context.arcTo(x, y, x + width, y, r);
    context.closePath();
  }

  function withAlpha(hex, alpha) {
    const value = hex.replace("#", "");
    const r = parseInt(value.slice(0, 2), 16);
    const g = parseInt(value.slice(2, 4), 16);
    const b = parseInt(value.slice(4, 6), 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }

  window.addEventListener("resize", resizeCanvas);
  window.addEventListener("keydown", handleKeydown);
  canvas.addEventListener("mousemove", handleCanvasMouseMove);
  canvas.addEventListener("mousedown", handleCanvasMouseDown);
  pauseButton.addEventListener("click", () => push(topic, "toggle_pause", {}));
  resetButton.addEventListener("click", () => {
    if (window.confirm("¿Reiniciar la partida para todos los jugadores?")) {
      push(topic, "reset", {});
    }
  });
  resizeCanvas();
  updateHud();
  connect();
})();
