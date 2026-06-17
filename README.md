# Tactical Tank Wars - Arcade Update

Este repositorio contiene la evolución del prototipo de Tank Wars desde un sistema estático/por turnos hacia un entorno **Arcade en tiempo Real** síncrono utilizando Elixir (GenServer) y Phoenix Channels.

## Cambios Introducidos en esta Versión

* **Físicas y Proyectiles Fluidos:** El pulso del servidor (`tick_rate`) se redujo de 1000ms a **100ms**. Los proyectiles ahora se mueven usando cálculos flotantes en el servidor, eliminando el movimiento "cuadro por cuadro".
* **Lógica de Torres Hostiles (Cara Amarilla):** * Spawn infinito y aleatorio en celdas vacías al iniciar o reiniciarse el mapa.
  * Inteligencia artificial con limitación de munición: cada torre solo puede tener **un proyectil activo** viajando por la pantalla. No vuelve a disparar hasta que su bala previa impacte o salga del tablero.
  * Diseño estético pixel art optimizado sin bordes excedentes para denotar furia pura.
* **Sistema de Salud Integrado:** Se añadieron **5 vidas (corazones)** dinámicos en la barra superior de estado del HUD.
* **Feedback Visual de Impacto:** Cuando un tanque colisiona con un proyectil, el servidor activa un `hit_timer` que renderiza el tanque en color rojo brillante en el Canvas por fracciones de segundo.

---

## Consideraciones Técnicas para Siguientes Módulos

El diseño actual es altamente modular, permitiendo reutilizar cerca del **80% del código base** para implementar las siguientes mecánicas:

### 1. Implementación de Proyectiles para los Tanques Jugadores
* **Frontend (`app.js`):** Escuchar el evento de teclado `Spacebar` (Barra espaciadora). Al presionarse, capturar la última dirección en la que se movió el tanque (ej. `last_dx`, `last_dy`) y hacer un `push` al canal: `push(topic, "player_shoot", {dx: last_dx, dy: last_dy})`.
* **Backend (`game_server.ex`):** Crear un `handle_call` para `{:player_shoot, player_id, dx, dy}` que añada un mapa a la lista `projectiles`, pero esta vez configurando un `origin_type: :player` para diferenciarlo del de las torres.
* **Reutilización:** La función `update_projectiles/1` actual es idéntica; solo se le debe agregar una regla para que si el proyectil es del jugador, disminuya la vida de las torres o de otros tanques enemigos en lugar de la propia.

### 2. Definición del Sistema de Ganadores
* **Criterio de Victoria:** Actualmente el juego termina si `time_left <= 0` o `any_player_dead?`. 
* **Lógica de Selección:** En la función que evalúa el `:game_over`, se puede procesar la colección de jugadores con un ordenamiento:
  1. El jugador con **más vidas restantes** (`lives`) es el ganador.
  2. En caso de empate en vidas, se puede evaluar el tamaño del territorio pintado en el mapa (`territory`) contando cuántas celdas posee cada ID de jugador.
* **Despliegue:** Pasar la información del ganador dentro del payload del estado final para que el overlay de JS renderice: `"¡GANADOR: JUGADOR AZUL!"`.
