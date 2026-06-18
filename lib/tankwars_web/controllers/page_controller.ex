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
            <div>
              <p class="eyebrow">Ivan Sardón - Diego Vasquez - Steffano Ballesteros</p>
              <h1>Tank Wars</h1>
            </div>
            <div class="status-grid">
              <div>
                <span>Conexión</span>
                <strong id="connection">iniciando</strong>
              </div>
              <div>
                <span>Jugador</span>
                <strong id="player">sin asignar</strong>
              </div>
              <div>
                <span>Territorio</span>
                <strong id="territory-count">0</strong>
              </div>
            </div>
          </section>

          <section class="arena-wrap" aria-label="Arena">
            <canvas id="arena" width="1200" height="800"></canvas>
          </section>
        </main>
        <script src="/assets/app.js"></script>
      </body>
    </html>
    """)
  end
end
