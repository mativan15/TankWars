(() => {
  const canvas = document.querySelector("#arena");
  const ctx = canvas.getContext("2d");
  const connectionEl = document.querySelector("#connection");
  const playerEl = document.querySelector("#player");
  const tickEl = document.querySelector("#tick");

  const topic = "game:lobby";
  const joinRef = "1";
  let socket = null;
  let nextRef = 1;
  let connected = false;
  let playerId = null;
  let state = null;

  function statusLabel() {
    if (!connected) return "desconectado";
    if (!playerId) return "conectado";
    return "sincronizado";
  }

  function updateHud() {
    connectionEl.textContent = statusLabel();
    tickEl.textContent = state ? String(state.tick) : "0";

    if (state && playerId && state.players[playerId]) {
      playerEl.textContent = state.players[playerId].name;
      playerEl.style.color = state.players[playerId].color;
    } else {
      playerEl.textContent = "sin asignar";
      playerEl.style.color = "";
    }
  }

  function push(topicName, event, payload, refJoin = joinRef) {
    if (!socket || socket.readyState !== WebSocket.OPEN) return;

    const message = [refJoin, String(nextRef++), topicName, event, payload];
    socket.send(JSON.stringify(message));
  }

  function connect() {
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    socket = new WebSocket(`${protocol}://${window.location.host}/socket/websocket?vsn=2.0.0`);

    socket.addEventListener("open", () => {
      connected = true;
      updateHud();
      push(topic, "phx_join", { name: "Jugador" }, joinRef);
    });

    socket.addEventListener("message", (event) => {
      const [_joinRef, _ref, messageTopic, messageEvent, payload] = JSON.parse(event.data);
      if (messageTopic !== topic && messageTopic !== "phoenix") return;

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
      window.setTimeout(connect, 1200);
    });
  }

  function move(dx, dy) {
    push(topic, "move", { dx, dy }, joinRef);
  }

  function handleKeydown(event) {
    const key = event.key.toLowerCase();
    const moves = {
      arrowup: [0, -1],
      w: [0, -1],
      arrowdown: [0, 1],
      s: [0, 1],
      arrowleft: [-1, 0],
      a: [-1, 0],
      arrowright: [1, 0],
      d: [1, 0]
    };

    if (!moves[key]) return;
    event.preventDefault();
    move(moves[key][0], moves[key][1]);
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
    const width = rect.width;
    const height = rect.height;

    ctx.clearRect(0, 0, width, height);
    drawBackground(width, height);

    if (!state) {
      drawCenteredText(width, height, "Conectando arena...");
      return;
    }

    const cellW = width / state.width;
    const cellH = height / state.height;

    drawTerritory(cellW, cellH);
    drawGrid(width, height, cellW, cellH);
    drawPlayers(cellW, cellH);
  }

  function drawBackground(width, height) {
    ctx.fillStyle = "#1f2a24";
    ctx.fillRect(0, 0, width, height);

    ctx.fillStyle = "rgba(245, 197, 66, 0.04)";
    for (let y = 0; y < height; y += 28) {
      ctx.fillRect(0, y, width, 1);
    }
  }

  function drawTerritory(cellW, cellH) {
    Object.entries(state.territory).forEach(([cell, owner]) => {
      const [x, y] = cell.split(",").map(Number);
      const player = state.players[owner];
      if (!player) return;

      ctx.fillStyle = withAlpha(player.color, 0.36);
      ctx.fillRect(x * cellW, y * cellH, cellW, cellH);
    });
  }

  function drawGrid(width, height, cellW, cellH) {
    ctx.strokeStyle = "rgba(241, 245, 242, 0.11)";
    ctx.lineWidth = 1;

    for (let x = 0; x <= state.width; x += 1) {
      ctx.beginPath();
      ctx.moveTo(Math.round(x * cellW) + 0.5, 0);
      ctx.lineTo(Math.round(x * cellW) + 0.5, height);
      ctx.stroke();
    }

    for (let y = 0; y <= state.height; y += 1) {
      ctx.beginPath();
      ctx.moveTo(0, Math.round(y * cellH) + 0.5);
      ctx.lineTo(width, Math.round(y * cellH) + 0.5);
      ctx.stroke();
    }
  }

  function drawPlayers(cellW, cellH) {
    Object.values(state.players).forEach((player) => {
      const cx = player.x * cellW + cellW / 2;
      const cy = player.y * cellH + cellH / 2;
      const size = Math.min(cellW, cellH) * 0.56;
      const isCurrent = player.id === playerId;

      ctx.save();
      ctx.translate(cx, cy);
      ctx.fillStyle = player.color;
      ctx.strokeStyle = isCurrent ? "#ffffff" : "rgba(255,255,255,0.45)";
      ctx.lineWidth = isCurrent ? 3 : 2;

      roundRect(ctx, -size / 2, -size / 2, size, size, 6);
      ctx.fill();
      ctx.stroke();

      ctx.fillStyle = "#151816";
      roundRect(ctx, size * 0.05, -size * 0.11, size * 0.52, size * 0.22, 4);
      ctx.fill();

      ctx.restore();
    });
  }

  function drawCenteredText(width, height, text) {
    ctx.fillStyle = "#f1f5f2";
    ctx.font = "600 18px system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(text, width / 2, height / 2);
  }

  function roundRect(context, x, y, width, height, radius) {
    const r = Math.min(radius, width / 2, height / 2);
    context.beginPath();
    context.moveTo(x + r, y);
    context.arcTo(x + width, y, x + width, y + height, r);
    context.arcTo(x + width, y + height, x, y + height, r);
    context.arcTo(x, y + height, x, y, r);
    context.arcTo(x, y, x + width, y, r);
    context.closePath();
  }

  function withAlpha(hex, alpha) {
    const value = hex.replace("#", "");
    const red = parseInt(value.slice(0, 2), 16);
    const green = parseInt(value.slice(2, 4), 16);
    const blue = parseInt(value.slice(4, 6), 16);
    return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
  }

  window.addEventListener("resize", resizeCanvas);
  window.addEventListener("keydown", handleKeydown);

  window.setInterval(() => {
    push("phoenix", "heartbeat", {}, null);
  }, 30000);

  resizeCanvas();
  updateHud();
  connect();
})();
