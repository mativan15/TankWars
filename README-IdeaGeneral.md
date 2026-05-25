

# Territory Tank Wars

## Proyecto Final: Desarrollo de un Juego Multijugador en Paradigma Funcional

**Territory Tank Wars** es un videojuego multijugador en tiempo real desarrollado en **Elixir**, orientado a cumplir los requisitos de un proyecto final basado en el paradigma funcional. El juego combina combate entre tanques, control territorial, sincronización multijugador, eventos dinámicos y un mapa interactivo que reacciona al comportamiento de los jugadores.

El sistema está diseñado para permitir la participación simultánea de mínimo tres jugadores conectados desde distintos dispositivos. Cada jugador controla un tanque dentro de una arena 2D vista desde arriba, donde deberá moverse, disparar, capturar territorio, esquivar ataques, aprovechar bonificaciones y competir por la victoria según el modo de juego seleccionado.

La propuesta busca mantener un equilibrio entre creatividad, atractivo visual y viabilidad técnica, evitando mecánicas demasiado complejas que dificulten su implementación en un tiempo razonable.

---

## 1. Objetivo del proyecto

El objetivo principal del proyecto es implementar un sistema de juego interactivo para mínimo tres jugadores simultáneos utilizando exclusivamente **Elixir** como lenguaje de programación funcional.

El juego debe demostrar el uso de estructuras de datos inmutables, funciones puras, concurrencia mediante actores o agentes, sincronización de jugadores, comunicación mediante paso de mensajes y visualización en tiempo real de las acciones de todos los participantes.

En términos de gameplay, el objetivo es crear una experiencia competitiva donde los jugadores no solo ataquen directamente a sus rivales, sino que también controlen el terreno para obtener ventajas estratégicas.

---

## 2. Descripción general del juego

En **Territory Tank Wars**, cada jugador controla un tanque dentro de un mapa dividido en zonas o celdas. El terreno puede estar en estado neutral o pertenecer a uno de los jugadores.

Los tanques conquistan territorio al pasar sobre él. Cuando un tanque atraviesa una zona neutral o enemiga, esta cambia progresivamente al color del jugador. De esta forma, el movimiento no solo sirve para desplazarse, sino también para expandir influencia sobre el mapa.

Además del control territorial, los jugadores pueden dispararse entre sí para eliminarse, usar el retroceso de sus disparos como impulso, saltar para esquivar proyectiles o superar obstáculos, y aprovechar las propiedades del terreno controlado para mejorar su rendimiento.

El mapa también contiene obstáculos, coberturas, torres, núcleos, plantas o entidades neutrales que reaccionan según el color dominante en sus alrededores. Esto permite que el mapa funcione como un entorno parcialmente vivo, generando situaciones dinámicas durante la partida.

---

## 3. Mecánicas principales

Cada jugador podrá realizar las siguientes acciones principales:

- Mover su tanque por el mapa.
- Capturar territorio al pasar sobre una zona.
- Disparar proyectiles contra otros tanques.
- Usar el retroceso del disparo como forma de impulso.
- Activar una habilidad de salto.
- Cubrirse detrás de obstáculos para evitar disparos enemigos.
- Aprovechar bonificaciones al moverse sobre territorio propio.
- Sufrir penalizaciones al moverse sobre territorio enemigo.
- Interactuar indirectamente con torres, núcleos, plantas o entidades neutrales del mapa.
- Participar en partidas por contrarreloj o modo muerte.

Estas mecánicas están pensadas para ser implementadas con reglas simples, pero con suficiente profundidad estratégica para que el juego sea interesante.

---

## 4. Sistema de territorio

El territorio es el elemento central del juego. El mapa estará dividido en pequeñas zonas o celdas, y cada una podrá tener uno de los siguientes estados:

- Neutral.
- Controlada por el jugador 1.
- Controlada por el jugador 2.
- Controlada por el jugador 3.
- Controlada por jugadores adicionales, si existen.

Cuando un tanque pasa sobre una celda, esa celda cambia al color del jugador. Esto permite que el mapa se transforme constantemente durante la partida.

El territorio no es únicamente visual. También afecta directamente el comportamiento del tanque.

### Efectos del territorio propio

Si un tanque se encuentra sobre territorio de su mismo color:

- Aumenta su velocidad.
- Reduce su tiempo de recarga.
- Mantiene controles estables.

Esto permite que los jugadores se muevan mejor dentro de sus propias zonas y defiendan con mayor eficacia su territorio.

### Efectos del territorio enemigo

Si un tanque se encuentra sobre territorio enemigo:

- Se mueve más lento.
- Sus controles se vuelven ligeramente inestables.
- Aumenta su tiempo de recarga.

Esto hace que invadir zonas enemigas sea riesgoso y obliga a los jugadores a planificar sus movimientos antes de atacar.

---

## 5. Combate entre tanques

Los tanques pueden dispararse entre sí mediante proyectiles. Cada disparo genera un proyectil que se desplaza por el mapa y puede impactar contra:

- Tanques enemigos.
- Obstáculos.
- Torres o estructuras del mapa.
- Zonas deformables del terreno.

Cuando un tanque recibe suficiente daño, queda eliminado de la partida, dependiendo del modo de juego activo.

El combate no se basa únicamente en apuntar y disparar. El control territorial influye directamente en la pelea, ya que estar sobre territorio propio mejora la velocidad y la recarga, mientras que estar sobre territorio enemigo perjudica el movimiento y la capacidad ofensiva.

---

## 6. Mecánica de recoil

Cada disparo produce un pequeño retroceso en el tanque. Este retroceso puede utilizarse como una mecánica de movilidad estratégica.

Por ejemplo, un jugador puede disparar hacia atrás para impulsarse hacia adelante, escapar de una zona peligrosa o entrar rápidamente a territorio enemigo para capturarlo.

Esta mecánica agrega profundidad sin requerir una simulación física compleja. Basta con aplicar un pequeño impulso en dirección contraria al disparo.

---

## 7. Habilidad de salto

Cada tanque contará con una habilidad de salto con tiempo de reutilización. El salto permitirá:

- Esquivar proyectiles.
- Cruzar zonas peligrosas.
- Superar pequeños obstáculos.
- Escapar de territorio enemigo.
- Reposicionarse rápidamente durante el combate.

Para mantener la implementación realista, el salto no necesita una física vertical compleja. Puede representarse como un desplazamiento corto hacia adelante acompañado de una animación simple, sombra o cambio temporal de escala del tanque.

---

## 8. Obstáculos, cobertura y terreno ligeramente deformable

El mapa incluirá obstáculos que los jugadores podrán usar como cobertura. Estos obstáculos pueden representar muros, rocas, bloques metálicos, barreras o estructuras neutrales.

Los obstáculos servirán para:

- Bloquear proyectiles enemigos.
- Crear zonas seguras temporales.
- Permitir emboscadas.
- Proteger territorio propio.
- Dividir el mapa en rutas estratégicas.

Además, algunos obstáculos o zonas del terreno podrán deformarse ligeramente cuando reciban disparos o explosiones.

Esta deformación será sencilla y controlada. Puede representarse mediante:

- Grietas visuales.
- Reducción de vida de un obstáculo.
- Cambio parcial de color.
- Creación de pequeñas zonas neutrales alrededor del impacto.

No se busca implementar destrucción física avanzada, sino dar sensación de dinamismo y reacción del escenario.

---

## 9. Mapa vivo

Una característica original de **Territory Tank Wars** es que el mapa no será completamente pasivo. Algunas estructuras neutrales reaccionarán según el color dominante en sus alrededores.

El mapa podrá incluir elementos como:

- Núcleos de energía.
- Plantas mecánicas.
- Torres neutrales.
- Entidades automáticas simples.

Estos elementos reaccionarán de forma básica al territorio cercano.

Ejemplos de comportamiento:

- Una torre neutral puede activarse a favor del jugador que controle la mayoría del territorio alrededor.
- Un núcleo puede entregar bonificaciones temporales al jugador dominante de la zona.
- Una planta mecánica puede expandir lentamente el color del jugador que controle su área.
- Una entidad neutral puede atacar al jugador con mayor territorio para equilibrar la partida.

Para mantener la complejidad bajo control, estos elementos tendrán comportamientos simples y predecibles. No se implementará inteligencia artificial avanzada.

---

## 10. Eventos globales aleatorios

Durante la partida podrán ocurrir eventos globales aleatorios que afecten temporalmente a todos los jugadores. Estos eventos buscan hacer que cada partida sea diferente y evitar que el desarrollo del juego sea completamente lineal.

Ejemplos de eventos globales:

### Tormenta de interferencia

Durante unos segundos, los controles sobre territorio enemigo se vuelven más inestables.

### Sobrecarga de energía

Los tanques recargan más rápido, pero los proyectiles causan menos daño.

### Zona corrupta

Algunas partes del mapa se vuelven neutrales nuevamente.

### Despertar del mapa

Las torres, núcleos y plantas reaccionan con mayor intensidad durante un corto periodo.

### Impulso territorial

El territorio de cada jugador se expande ligeramente alrededor de sus zonas principales.

Estos eventos serán temporales y simples de calcular, para que el proyecto siga siendo viable.

---

## 11. Modos de juego

El juego tendrá dos posibles modos principales: modo contrarreloj y modo muerte. La implementación inicial puede centrarse en uno de ellos, pero ambos forman parte de la propuesta general del proyecto.

---

## 11.1. Modo contrarreloj

En el modo contrarreloj, la partida tiene un tiempo límite definido. Durante ese tiempo, los jugadores deben capturar la mayor cantidad posible de territorio.

Cuando el temporizador llega a cero, el sistema calcula el porcentaje de territorio controlado por cada jugador. Gana el jugador con mayor cantidad de territorio.

### Condición de victoria

Gana el jugador que controle más territorio al finalizar el tiempo.

### Ventajas de este modo

- Favorece la estrategia y el movimiento.
- Reduce la dependencia exclusiva del combate.
- Permite partidas rápidas.
- Hace que el sistema de territorio sea el centro del juego.
- Es más fácil de balancear para una primera versión.

---

## 11.2. Modo muerte

En el modo muerte, gana el último tanque que quede en pie.

En este modo, el territorio sigue siendo importante porque otorga ventajas ofensivas y defensivas. Un jugador con más territorio puede obtener mejores condiciones de combate.

El control territorial puede proporcionar:

- Mayor velocidad.
- Menor tiempo de recarga.
- Control de torretas.
- Mejores posiciones defensivas.
- Mayor presión sobre enemigos.

Las torretas capturadas podrán ayudar al jugador dominante de una zona atacando automáticamente a enemigos cercanos.

Para mantener el sistema simple, las torretas tendrán una lógica básica: detectar al enemigo más cercano dentro de un rango y disparar cada cierto tiempo.

### Condición de victoria

Gana el último jugador que no haya sido eliminado.

---

## 12. Requisitos técnicos del proyecto

El proyecto se desarrollará usando **Elixir** y deberá cumplir los requisitos técnicos definidos para el trabajo final.

---

## 12.1. Uso de estructuras de datos inmutables

El estado del juego se representará mediante estructuras inmutables como:

- Mapas (`%{}`)
- Listas
- Tuplas
- Structs

El estado global del juego puede incluir información como:

- Jugadores conectados.
- Posiciones de los tanques.
- Vida de los jugadores.
- Proyectiles activos.
- Territorio controlado.
- Obstáculos.
- Torres.
- Núcleos.
- Eventos activos.
- Tiempo restante de partida.
- Modo de juego actual.

Cada actualización producirá una nueva versión del estado en lugar de modificar directamente el estado anterior.

---

## 12.2. Funciones puras

La lógica principal del juego se definirá mediante funciones puras. Estas funciones recibirán un estado y una acción, y devolverán un nuevo estado.

Ejemplos de funciones puras:

- Actualizar la posición de un jugador.
- Aplicar el efecto de un disparo.
- Calcular el impacto de un proyectil.
- Cambiar el control de una celda del territorio.
- Aplicar bonificaciones por territorio propio.
- Aplicar penalizaciones por territorio enemigo.
- Activar un evento global.
- Calcular el ganador de la partida.

Este diseño permite separar la lógica del juego de la comunicación por red, facilitando las pruebas y manteniendo el enfoque funcional.

---

## 12.3. Sincronización de jugadores

El servidor debe gestionar al menos tres conexiones activas al mismo tiempo y mantener un estado coherente para todos los jugadores.

Cada jugador enviará sus acciones al servidor. El servidor recibirá esas acciones, validará los cambios, actualizará el estado global de la partida y enviará el estado actualizado a todos los clientes conectados.

De esta manera, todos los jugadores podrán ver en tiempo real:

- La posición de los demás tanques.
- Los disparos realizados.
- Los cambios en el territorio.
- Las eliminaciones.
- Los eventos globales.
- Las torres o elementos activos del mapa.

---

## 12.4. Concurrencia mediante actores o agentes

El sistema utilizará el modelo de procesos para manejar la concurrencia.

Una estructura viable sería:

```text
GameServer
 ├── PlayerProcess 1
 ├── PlayerProcess 2
 ├── PlayerProcess 3
 ├── TerritoryProcess
 ├── ProjectileProcess
 └── EventProcess
```

El `GameServer` coordinará la partida principal, siguiendo el patrón de un proceso servidor en Elixir. Los procesos de jugador recibirán las acciones individuales de cada usuario, como moverse, disparar o saltar. Otros procesos podrán encargarse de proyectiles, territorio o eventos globales.

Este modelo permite manejar múltiples jugadores simultáneos de forma organizada y coherente.

---

## 12.5. Comunicación mediante paso de mensajes

La comunicación entre procesos se realizará mediante paso de mensajes, aprovechando el modelo de concurrencia de Elixir.

Ejemplos de mensajes del sistema:

```text
MovePlayer
Shoot
Jump
UpdateTerritory
ProjectileHit
SpawnEvent
BroadcastState
PlayerEliminated
CaptureTower
GameOver
```

Este enfoque evita el uso de variables globales mutables y permite que las acciones del juego se procesen de manera ordenada mediante mensajes entre procesos.

---

## 12.6. Visualización en tiempo real

La visualización se realizará mediante **HTML Canvas** conectado al servidor Elixir por medio de **WebSockets**. La opción recomendada es utilizar Phoenix Channels o una solución equivalente basada en WebSockets para comunicar el cliente con el servidor.

La opción recomendada es usar HTML Canvas, porque permite separar claramente la lógica del servidor de la parte visual del cliente.

El cliente se encargará de dibujar:

- Tanques.
- Proyectiles.
- Territorio controlado.
- Obstáculos.
- Torres.
- Núcleos.
- Plantas o elementos vivos del mapa.
- Eventos activos.
- Barra de vida.
- Contador de tiempo.
- Porcentaje de territorio controlado.

El servidor mantendrá el estado oficial de la partida y lo enviará constantemente a los clientes.

---

## 13. Arquitectura general propuesta

La arquitectura general del juego seguirá este flujo:

```text
Jugador realiza una acción
        ↓
Cliente envía mensaje por WebSocket
        ↓
Servidor Elixir recibe la acción
        ↓
Proceso correspondiente procesa el mensaje
        ↓
GameServer actualiza el estado global
        ↓
Servidor envía el estado actualizado a todos los clientes
        ↓
Cada cliente renderiza la nueva escena en Canvas
```

Este modelo permite cumplir con los requisitos de comunicación, sincronización y visualización en tiempo real.

---

## 14. Alcance realista del proyecto

Para mantener el proyecto viable, se propone dividir el desarrollo en una versión mínima funcional y una versión extendida.

---

## 14.1. Versión mínima funcional

La primera versión debe incluir:

- Tres jugadores conectados simultáneamente.
- Movimiento de tanques.
- Control de territorio al pasar sobre él.
- Disparos entre tanques.
- Daño y eliminación.
- Bonificaciones por territorio propio.
- Penalizaciones por territorio enemigo.
- Obstáculos básicos para cobertura.
- Estado sincronizado por WebSockets.
- Visualización en Canvas.
- Modo contrarreloj.

Esta versión permitiría cumplir los requisitos principales del proyecto sin sobrecargar la implementación.

---

## 14.2. Versión extendida

Si el tiempo lo permite, se pueden agregar:

- Recoil como mecánica avanzada de movimiento.
- Habilidad de salto.
- Obstáculos parcialmente deformables.
- Torretas capturables.
- Núcleos de energía.
- Plantas mecánicas.
- Entidades neutrales simples.
- Eventos globales aleatorios.
- Modo muerte.

Estas características aumentan la profundidad del juego, pero pueden implementarse después de asegurar que la versión mínima funciona correctamente.

---

## 15. Justificación del uso de Elixir

Elixir es adecuado para este proyecto porque está diseñado para construir sistemas concurrentes, distribuidos y tolerantes a fallos sobre la máquina virtual de Erlang. Su modelo de procesos ligeros permite manejar múltiples jugadores conectados al mismo tiempo de forma natural.

El juego puede representar su estado mediante estructuras inmutables como mapas (`%{}`), listas, tuplas y structs. Además, la lógica principal puede organizarse mediante funciones puras que transforman el estado del juego a partir de acciones recibidas.

Para la concurrencia, Elixir permite usar procesos ligeros, paso de mensajes y módulos como `GenServer`, lo que facilita la creación de un servidor principal de partida, procesos asociados a jugadores y procesos auxiliares para eventos, territorio o proyectiles.

Esta elección permite cumplir los requisitos del trabajo final y, al mismo tiempo, mantener una arquitectura clara para un juego multijugador en tiempo real.

---

## 16. Conclusión

**Territory Tank Wars** es una propuesta de videojuego multijugador funcional en Elixir que combina combate, control territorial, sincronización en tiempo real y un entorno interactivo.

El juego cumple con los requisitos técnicos planteados: uso de estructuras inmutables, funciones puras, concurrencia mediante actores o agentes, paso de mensajes, sincronización de al menos tres jugadores y visualización en tiempo real de posiciones y acciones.

Además, mantiene una complejidad razonable para un proyecto académico. La versión mínima permite demostrar correctamente la arquitectura funcional y concurrente, mientras que la versión extendida ofrece espacio para agregar características más creativas como recoil, salto, torres capturables, mapa vivo y eventos globales.

El resultado esperado es un juego competitivo, visualmente atractivo y técnicamente alineado con el paradigma funcional.