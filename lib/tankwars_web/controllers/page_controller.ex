defmodule TankWarsWeb.PageController do
  use TankWarsWeb, :controller

  def home(conn, _params) do
    html(conn, """
    <!doctype html>
    <html lang="es">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Tank Wars</title>
        <link rel="stylesheet" href="/assets/styles.css">
      </head>
      <body>
        <main class="shell">
          <section class="hud" aria-label="Estado de partida">
            <div class="brand">
              <p class="eyebrow">Ivan Sardón - Diego Vasquez - Steffano Ballesteros</p>
              <h1>Tank Wars</h1>
            </div>
            <div class="status-grid">
              <div id="pause-box" class="hud-action-box">
                <button id="pause-btn" class="game-control" type="button" disabled>⏸ Pausar</button>
              </div>
              <div id="reset-box" class="hud-action-box">
                <button id="global-reset-btn" class="game-control game-control--danger" type="button" disabled>↻ Reiniciar</button>
              </div>
              <div id="timer-box">
                <span>Tiempo</span>
                <strong id="hud-timer">-</strong>
              </div>
              <div id="player-box">
                <span>Jugador</span>
                <strong id="player">sin asignar</strong>
              </div>
              <div id="lives-box">
                <span>Vidas</span>
                <strong id="hud-lives">❤️❤️❤️❤️❤️</strong>
              </div>
              <div id="ammo-box">
                <span>Balas</span>
                <strong id="hud-ammo" aria-label="5 de 5 balas">●●●●●</strong>
              </div>
              <div id="territory-box" aria-live="polite">
                <span>Clasificación territorial</span>
                <ol id="territory-leaderboard" class="territory-leaderboard">
                  <li class="territory-empty">Esperando jugadores</li>
                </ol>
              </div>
            </div>
          </section>

          <section class="game-area">
            <section class="arena-wrap" aria-label="Arena">
              <canvas id="arena" width="1200" height="800"></canvas>
            </section>

            <aside class="powerups-panel">
              <h2>Power Ups</h2>

              <div class="powerup-card powerup-shield">
                <div class="powerup-icon">💠</div>
                <div>
                  <h3>Escudo</h3>
                  <p>Te protege de recibir daño durante 10 segundos.</p>
                </div>
              </div>

              <div class="powerup-card powerup-speed">
                <div class="powerup-icon">⚡</div>
                <div>
                  <h3>Velocidad</h3>
                  <p>Aumenta la velocidad de tu tanque durante 10 segundos.</p>
                </div>
              </div>

              <div class="powerup-card powerup-life">
                <div class="powerup-icon">❤️</div>
                <div>
                  <h3>Vida</h3>
                  <p>Recupera 1 vida hasta un máximo de 5.</p>
                </div>
              </div>
            </aside>
          </section>
        </main>
        <script src="/assets/app.js"></script>
      </body>
    </html>
    """)
  end
end
