(() => {
  const canvas = document.querySelector("#arena");
  const ctx = canvas.getContext("2d");
  const connectionEl = document.querySelector("#connection");
  const playerEl = document.querySelector("#player");
  const territoryEl = document.querySelector("#territory-count");

  const arenaWrap = document.querySelector(".arena-wrap");
  arenaWrap.style.position = "relative";

  const menuOverlay = document.createElement("div");
  menuOverlay.id = "menu-overlay";
  menuOverlay.style = "position: absolute; inset: 0; background: rgba(17, 19, 18, 0.9); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 20px; z-index: 10; color: #f1f5f2; font-family: system-ui, sans-serif;";
  arenaWrap.appendChild(menuOverlay);

  const statusGrid = document.querySelector(".status-grid");

  if (!document.querySelector("#lives-box")) {
    const livesDiv = document.createElement("div");
    livesDiv.id = "lives-box";
    livesDiv.innerHTML = `<span>Mis Vidas</span><strong id="hud-lives" style="color: #e5484d; font-size: 1.1rem;">❤️❤️❤️❤️❤️</strong>`;
    statusGrid.insertBefore(livesDiv, statusGrid.firstChild);
  }
  const livesEl = document.querySelector("#hud-lives");

  if (!document.querySelector("#timer-box")) {
    const timerDiv = document.createElement("div");
    timerDiv.id = "timer-box";
    timerDiv.innerHTML = `<span>Tiempo</span><strong id="hud-timer" style="color: #f5c542;">60s</strong>`;
    statusGrid.insertBefore(timerDiv, statusGrid.firstChild);
  }
  const timerEl = document.querySelector("#hud-timer");

  if (!document.querySelector("#ammo-box")) {
    const ammoDiv = document.createElement("div");
    ammoDiv.id = "ammo-box";
    ammoDiv.innerHTML = `<span>Balas</span><strong id="hud-ammo" style="color: #f5c542;">-</strong>`;
    statusGrid.insertBefore(ammoDiv, connectionEl.parentElement);
  }
  const ammoEl = document.querySelector("#hud-ammo");

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
  const aimSendIntervalMs = 50;
  const clientId = getClientId();

  function updateHud() {
    connectionEl.textContent = joinRejected ? "sala llena" : !connected ? "desconectado" : playerId ? "sincronizado" : "conectado";
    territoryEl.textContent = String(countOwnedTerritory());

    if (state && playerId && state.players[playerId]) {
      playerEl.textContent = state.players[playerId].name;
      playerEl.style.color = state.players[playerId].color;
      
      const currentLives = state.players[playerId].lives;
      livesEl.textContent = "❤️".repeat(currentLives) + "🖤".repeat(5 - currentLives);
      updateAmmoHud(state.players[playerId]);
    } else {
      ammoEl.textContent = "-";
    }

    if (state) {
      if (state.game_state === "menu") {
        menuOverlay.style.display = "flex";
        menuOverlay.innerHTML = `
          <h2 style="margin: 0; font-size: 2.3rem; color: #f5c542; text-transform: uppercase;">Tank Wars</h2>
          <p style="margin: 0; color: #a9b6ad; font-size: 0.9rem;">Esquiva los proyectiles, tienes 5 vidas!</p>
          <button id="start-btn" style="background: #f5c542; color: #111312; border: none; padding: 12px 36px; font-size: 1rem; font-weight: 800; border-radius: 6px; cursor: pointer;">INICIAR PARTIDA</button>
        `;
        document.querySelector("#start-btn").addEventListener("click", () => push(topic, "start_game", {}));
        timerEl.textContent = "60s";
      } else if (state.game_state === "playing") {
        menuOverlay.style.display = "none";
        timerEl.textContent = state.time_left + "s";
      } else if (state.game_state === "game_over") {
        menuOverlay.style.display = "flex";
        menuOverlay.innerHTML = `
          <h2 style="margin: 0; font-size: 2.5rem; color: #e5484d; text-transform: uppercase;">FIN DE LA PARTIDA</h2>
          <p style="margin: 0; color: #a9b6ad;">Queda un solo tanque con vida o se acabó el tiempo</p>
          <button id="reset-btn" style="background: #f1f5f2; color: #111312; border: none; padding: 12px 32px; font-size: 1rem; font-weight: 700; border-radius: 6px; cursor: pointer;">REINICIAR ARENA</button>
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
      <h2 style="margin: 0; font-size: 2.1rem; color: #e5484d; text-transform: uppercase;">PARTIDA LLENA</h2>
      <p style="margin: 0; color: #a9b6ad; font-size: 0.95rem; text-align: center;">${message || "Los tres jugadores ya estan ocupados."}</p>
    `;
  }

  function countOwnedTerritory() {
    if (!state || !playerId || !state.territory) return 0;
    return Object.values(state.territory).filter(owner => owner === playerId).length;
  }

  function updateAmmoHud(player) {
    const maxAmmo = player.max_ammo || 5;
    const ammo = Number.isFinite(player.ammo) ? player.ammo : maxAmmo;

    if (ammo <= 0) {
      ammoEl.textContent = "recargando";
      ammoEl.style.color = "#e5484d";
    } else {
      ammoEl.textContent = `${ammo}/${maxAmmo}`;
      ammoEl.style.color = "#f5c542";
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
    ctx.fillStyle = "#1f2a24";
    ctx.fillRect(0, 0, width, height);
  }

  function drawTerritory(cellW, cellH) {
    Object.entries(state.territory).forEach(([cell, owner]) => {
      const [x, y] = cell.split(",").map(Number);
      const player = state.players[owner];
      if (!player) return;
      ctx.fillStyle = withAlpha(player.color, 0.25);
      ctx.fillRect(x * cellW, y * cellH, cellW, cellH);
    });
  }

  function drawObstacles(cellW, cellH) {
    if (!state.obstacles) return;
    Object.entries(state.obstacles).forEach(([cell, obs]) => {
      const [x, y] = cell.split(",").map(Number);
      const xPos = x * cellW;
      const yPos = y * cellH;

      if (obs.type === "muro_gris") {
        ctx.fillStyle = "#3a473f";
        ctx.strokeStyle = "#a9b6ad";
        ctx.lineWidth = 1;
        roundRect(ctx, xPos + 2, yPos + 2, cellW - 4, cellH - 4, 4);
        ctx.fill(); ctx.stroke();
      } else if (obs.type === "torre_vida") {
        ctx.fillStyle = "#f5c542";
        roundRect(ctx, xPos + 3, yPos + 3, cellW - 6, cellH - 6, 6);
        ctx.fill();

        ctx.fillStyle = "#111312"; 
        
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

        ctx.fillStyle = "#ff2a30";
        ctx.fillRect(xPos + cellW * 0.24, yPos + cellH * 0.42, cellW * 0.16, cellH * 0.14);
        ctx.fillRect(xPos + cellW * 0.60, yPos + cellH * 0.42, cellW * 0.16, cellH * 0.14);

        ctx.fillStyle = "#111312";
        ctx.fillRect(xPos + cellW * 0.30, yPos + cellH * 0.46, cellW * 0.08, cellH * 0.08);
        ctx.fillRect(xPos + cellW * 0.62, yPos + cellH * 0.46, cellW * 0.08, cellH * 0.08);
        ctx.fillStyle = "#111312";
        ctx.fillRect(xPos + cellW * 0.32, yPos + cellH * 0.70, cellW * 0.36, cellH * 0.12);
        drawTowerLifeIndicator(obs, xPos, yPos, cellW, cellH);
      }
    });
  }

  function drawTowerLifeIndicator(tower, xPos, yPos, cellW, cellH) {
    const maxLives = tower.max_lives || 6;
    const lives = Number.isFinite(tower.lives) ? tower.lives : maxLives;
    const ratio = Math.max(0, Math.min(1, lives / maxLives));
    const barWidth = cellW * 0.58;
    const barHeight = Math.max(3, cellH * 0.08);
    const barX = xPos + (cellW - barWidth) / 2;
    const barY = yPos + Math.max(2, cellH * 0.05);

    ctx.save();
    ctx.fillStyle = "rgba(17, 19, 18, 0.75)";
    roundRect(ctx, barX, barY, barWidth, barHeight, 2);
    ctx.fill();

    ctx.fillStyle = ratio > 0.35 ? "#22c55e" : "#e5484d";
    roundRect(ctx, barX, barY, barWidth * ratio, barHeight, 2);
    ctx.fill();

    ctx.strokeStyle = "rgba(241, 245, 242, 0.75)";
    ctx.lineWidth = 1;
    roundRect(ctx, barX, barY, barWidth, barHeight, 2);
    ctx.stroke();
    ctx.restore();
  }

  function drawProjectiles(cellW, cellH) {
    if (!state.projectiles) return;
    state.projectiles.forEach(p => {
      ctx.fillStyle = "#ff4a4a"; 
      ctx.beginPath();
      ctx.arc(p.x * cellW, p.y * cellH, 6, 0, Math.PI * 2);
      ctx.fill();
      
      ctx.fillStyle = "#f5c542";
      ctx.beginPath();
      ctx.arc(p.x * cellW, p.y * cellH, 3, 0, Math.PI * 2);
      ctx.fill();
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
      ctx.strokeStyle = effect.color || "#f1f5f2";
      ctx.lineWidth = 2;
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
    ctx.strokeStyle = "rgba(241, 245, 242, 0.05)";
    for (let x = 0; x <= state.width; x++) {
      ctx.beginPath(); ctx.moveTo(x * cellW, 0); ctx.lineTo(x * cellW, height); ctx.stroke();
    }
    for (let y = 0; y <= state.height; y++) {
      ctx.beginPath(); ctx.moveTo(0, y * cellH); ctx.lineTo(width, y * cellH); ctx.stroke();
    }
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
      
      ctx.fillStyle = player.hit_timer > 0 ? "#FFFFFF" : player.color;
      ctx.strokeStyle = player.id === playerId ? "#ffffff" : "rgba(255,255,255,0.4)";
      ctx.lineWidth = player.id === playerId ? 3 : 1.5;

      roundRect(ctx, -size / 2, -size / 2, size, size, 6);
      ctx.fill(); ctx.stroke();

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
    ctx.fillStyle = "#111312";
    roundRect(ctx, size * 0.02, -size * 0.11, size * 0.62, size * 0.22, 3);
    ctx.fill();
    ctx.restore();
  }

  function drawDestroyedTank(player, cx, cy, size) {
    ctx.save();
    ctx.translate(cx, cy);

    ctx.fillStyle = "#202420";
    ctx.strokeStyle = withAlpha(player.color, 0.55);
    ctx.lineWidth = 2;
    roundRect(ctx, -size / 2, -size / 2, size, size, 6);
    ctx.fill();
    ctx.stroke();

    ctx.strokeStyle = "#e5484d";
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
  resizeCanvas();
  updateHud();
  connect();
})();
