# GHOST-HUNTER
## Game Design Document (GDD) y plan de desarrollo del MVP

**Versión:** 0.1 — MVP  
**Motor:** Godot 4.x  
**Lenguaje:** GDScript  
**Plataforma objetivo:** Android / iOS  
**Perspectiva:** 3D Top-Down  
**Género:** Asymmetric Multiplayer / Hide & Seek / Casual Action  
**Estado:** Documento de diseño inicial

---

# 1. Visión general

Ghost-Hunter es un videojuego de persecución asimétrica en el que dos equipos se enfrentan dentro de una casa misteriosa: Hunters (cazadores) y Ghosts (fantasmas).

Los Hunters deben encontrar y capturar a todos los Ghosts antes de que termine el tiempo. Los Ghosts deben utilizar el entorno, esconderse, manipular objetos y escapar para sobrevivir.

La experiencia combina exploración, estrategia, engaño y persecución. El juego debe ser fácil de aprender, pero ofrecer suficientes posibilidades para que cada partida sea diferente.

### Propuesta de valor

Un juego de escondite en 3D donde los jugadores no solamente se esconden: pueden manipular la casa para engañar a sus perseguidores.

# 2. Pilares fundamentales del diseño

## 2.1. Persecución
El Hunter debe experimentar la emoción de encontrar, perseguir y capturar a los Ghosts.

## 2.2. Engaño
Los Ghosts deben tener herramientas para confundir al Hunter y aprovechar los elementos de la casa.

## 2.3. Interacción
La casa debe ser parte activa del gameplay. Puertas, luces y armarios deben tener utilidad.

## 2.4. Accesibilidad
Los controles deben ser sencillos, las partidas cortas y las reglas fáciles de comprender.

## 2.5. Rejugabilidad
Las diferentes decisiones de los jugadores deben generar situaciones distintas sin necesidad de construir mapas enormes.

# 3. Dirección artística

**Estilo:** 3D Cartoon / Stylized / Casual.

La ambientación debe ser misteriosa, pero no terrorífica.

### Personajes
Durante el MVP se utilizarán cápsulas 3D como personajes temporales.

- Hunter: cápsula con colores cálidos.
- Ghost: cápsula con colores fríos, preferiblemente celeste o violeta.
- Ghosts ligeramente translúcidos.
- Animaciones sencillas de movimiento, captura y escape.

No se necesitan modelos profesionales para validar el gameplay.

### Escenario
La casa debe tener una apariencia oscura, con iluminación cálida en las habitaciones y zonas de sombra.

La oscuridad nunca debe impedir que el jugador entienda dónde está o qué está sucediendo.

### Paleta conceptual

- Azul oscuro: ambiente y sombras.
- Violeta: elementos misteriosos.
- Amarillo cálido: iluminación de habitaciones.
- Celeste: Ghosts.
- Naranja: Hunters.
- Blanco: elementos interactivos y señales visuales.

### Referencia visual
El objetivo es que los personajes destaquen sobre el escenario. Aunque la casa esté oscura, el jugador debe identificar rápidamente a los personajes, las puertas y los objetos interactivos.

# 4. Cámara y perspectiva

El juego utilizará escenarios tridimensionales reales.

### Configuración propuesta

- Cámara ortográfica.
- Inclinación aproximada de 65° respecto al suelo.
- Rotación fija sobre el eje vertical.
- Seguimiento suave del personaje controlado.
- Zoom configurable.
- Paredes que puedan ocultarse o hacerse transparentes cuando bloqueen la visión del jugador.

No utilizaremos una cámara completamente lateral ni una perspectiva isométrica estricta.

El objetivo es permitir que el jugador observe las habitaciones y tenga suficiente visibilidad para perseguir o esconderse.

# 5. Estructura de las partidas

### Configuración principal del MVP

| Parámetro | Configuración |
|---|---|
| Hunters | 1 |
| Ghosts | 2 |
| Duración | 6 minutos |
| Preparación | 8 segundos |
| Jugadores humanos | 1 |
| Oponentes | IA |
| Escenario | Una casa |

El jugador podrá elegir su equipo:

- Hunter contra dos Ghosts controlados por IA.
- Ghost contra un Hunter controlado por IA, en una modalidad de práctica 1vs1.

Esto permitirá probar las dos experiencias sin desarrollar todavía una IA de compañeros.

### Secuencia de partida

1. Selección del equipo.
2. Carga de la casa.
3. Posicionamiento de personajes.
4. Ocho segundos de ventaja para los Ghosts.
5. Inicio de la persecución.
6. Captura de Ghosts.
7. Comprobación de las condiciones de victoria.
8. Pantalla de resultados.
9. Opción de volver a jugar.

### Condiciones de victoria

**Hunters:** capturar a todos los Ghosts antes de que termine el tiempo.

**Ghosts:** conseguir que al menos un Ghost permanezca libre cuando el temporizador llegue a cero.

Si una captura termina exactamente antes de finalizar el tiempo, prevalece la captura completada.

# 6. Mecánicas de los personajes

## 6.1. Hunter

El Hunter dispone de un lanzador de redes y una caja de contención portátil.

### Habilidades

**Movimiento**
- Movimiento libre en el escenario.
- Velocidad ligeramente inferior a la del Ghost.

**Disparar red**
- Dispara un proyectil.
- Alcance limitado.
- Tiempo de recarga.
- Requiere apuntar correctamente.
- No atraviesa paredes.

**Capturar**
- Cuando una red impacta, el Ghost queda inmovilizado.
- El Hunter debe acercarse.
- Debe mantener la interacción durante un tiempo determinado.
- El Ghost queda almacenado en la caja de contención.

La captura no debe producirse automáticamente al acertar el disparo.

### Valores iniciales

| Parámetro | Valor |
|---|---:|
| Velocidad | 4.2 m/s |
| Alcance de red | 6 m |
| Recarga | 3 segundos |
| Inmovilización | 5 segundos |
| Distancia de captura | 1.5 m |
| Tiempo de captura | 1.5 segundos |

Estos valores serán modificables para realizar pruebas de balance.

## 6.2. Ghost

El Ghost tiene como objetivo evitar ser capturado.

### Habilidades

**Movimiento**
- Mayor velocidad que el Hunter.
- Puede cambiar de dirección rápidamente.

**Esconderse**
- Puede introducirse en armarios habilitados.
- Mientras está escondido no puede ser detectado visualmente.
- Puede salir cuando quiera.
- El Hunter puede registrar el escondite.

**Manipular el entorno**
- Encender y apagar luces.
- Abrir y cerrar puertas.

**Escapar**
- Cuando recibe un impacto de red queda inmovilizado.
- Si el Hunter no completa la captura antes de que termine el efecto de la red, puede escapar.

### Valores iniciales

| Parámetro | Valor |
|---|---:|
| Velocidad | 4.6 m/s |
| Tiempo de preparación | 8 segundos |
| Interacción con objetos | Instantánea o breve |

Los Ghosts no tendrán invisibilidad ni habilidades especiales durante el MVP.

# 7. Mecánicas del escenario

## 7.1. Puertas

- Pueden abrirse y cerrarse.
- Bloquean el paso cuando están cerradas.
- Pueden bloquear parcialmente la visión.
- Tanto Hunters como Ghosts pueden interactuar con ellas.
- Las interacciones producen ruido.

Para simplificar la navegación de la IA, esta podrá abrir automáticamente las puertas cuando necesite atravesarlas.

## 7.2. Iluminación

Cada habitación tendrá una fuente de luz controlable.

- Estado encendido.
- Estado apagado.
- Interruptor interactivo.
- Cambios visibles en la iluminación.

La oscuridad también tendrá una función de gameplay: reducirá la distancia a la que el Hunter puede detectar a un Ghost.

La iluminación no debe generar oscuridad absoluta.

## 7.3. Armarios

Los armarios son escondites especiales.

Funcionamiento:

1. El Ghost se acerca.
2. Aparece el botón contextual.
3. El Ghost entra en el armario.
4. Su personaje deja de ser visible para el Hunter.
5. El Ghost puede salir cuando quiera.
6. El Hunter puede registrar el armario.
7. Si encuentra un Ghost, lo revela y lo expulsa.

Registrar un armario no equivale a capturar automáticamente al Ghost.

## 7.4. Ruido

Para una primera implementación:

- Correr produce ruido.
- Abrir y cerrar puertas produce ruido.
- El Hunter puede recibir una señal direccional aproximada.

Los ruidos no deben revelar la posición exacta del Ghost.

# 8. Diseño del mapa inicial

Una única casa de una planta.

### Distribución

Cinco habitaciones:

1. Sala de estar.
2. Cocina.
3. Dormitorio principal.
4. Baño.
5. Estudio o habitación de almacenamiento.

Dos pasillos que conecten las habitaciones.

### Objetos

- Aproximadamente cinco puertas.
- Tres armarios funcionales.
- Cinco interruptores.
- Cinco fuentes de iluminación.
- Mobiliario básico para crear obstáculos y rutas alternativas.

### Reglas de construcción

- Las habitaciones deben tener espacio suficiente para perseguir.
- Evitar pasillos excesivamente estrechos.
- Evitar habitaciones sin salida.
- Incluir diferentes rutas para desplazarse.
- Los armarios no deben estar todos juntos.
- El mapa debe permitir que un Ghost escape sin depender exclusivamente de su velocidad.

# 9. Inteligencia artificial

La IA utilizará máquinas de estados finitos (Finite State Machine).

## 9.1. Ghost IA

Estados:

- **IDLE:** permanece en una posición.
- **ROAM:** explora la casa.
- **FLEE:** intenta alejarse del Hunter.
- **HIDE:** busca un armario y se esconde.
- **ESCAPE:** intenta escapar después de recibir una red.

Prioridad de comportamiento:

1. Si está atrapado, esperar o escapar cuando termine el efecto.
2. Si detecta peligro cercano, escapar.
3. Si tiene un escondite disponible y está siendo perseguido, esconderse.
4. Si no existe peligro, explorar.

## 9.2. Hunter IA

Estados:

- **PATROL:** recorre habitaciones.
- **INVESTIGATE:** investiga ruidos.
- **CHASE:** persigue a un Ghost.
- **ATTACK:** intenta disparar una red.
- **CAPTURE:** intenta capturar al Ghost atrapado.
- **SEARCH:** registra posibles escondites.

La IA no debe conocer permanentemente las posiciones de los Ghosts. Debe utilizar información que también estaría disponible para un jugador humano.

# 10. Controles móviles

## Hunter

- Joystick izquierdo: movimiento.
- Botón principal: disparar red.
- Botón contextual: interactuar.
- Botón secundario: acción opcional futura.

## Ghost

- Joystick izquierdo: movimiento.
- Botón contextual: esconderse, abrir puertas, apagar luces, etc.

La interacción será contextual para evitar demasiados botones.

Ejemplos:

- Cerca de una puerta: **ABRIR**.
- Cerca de un interruptor: **APAGAR**.
- Cerca de un armario: **ESCONDERSE**.
- Cerca de un Ghost atrapado: **CAPTURAR**.

Durante el desarrollo también habrá controles de teclado para facilitar las pruebas en PC.

# 11. Interfaz (HUD)

HUD mínimo:

- Temporizador.
- Indicador de Ghosts restantes.
- Indicador de recarga de red.
- Botones de interacción.
- Indicadores de ruido.
- Mensajes de estado.

No implementaremos minimapa inicialmente.

# 12. Sonido

Sonidos necesarios para el MVP:

- Pasos.
- Puertas.
- Interruptores.
- Disparo de red.
- Impacto de red.
- Captura.
- Entrada y salida de armarios.
- Ambiente de casa misteriosa.

La música puede ser ambiental, discreta y no demasiado terrorífica.

# 13. Funcionalidades fuera del MVP

Se posponen:

- Multiplayer online.
- Matchmaking.
- Diferentes casas.
- Personalización de personajes.
- Diferentes tipos de Ghosts.
- Diferentes tipos de Hunters.
- Habilidades especiales.
- Sistema de progresión.
- Monedas y recompensas.
- Inventario.
- Rescate de compañeros.
- Chat de voz.
- Clasificaciones.
- Eventos y temporadas.

# 14. Arquitectura técnica

**Motor:** Godot 4.x  
**Lenguaje:** GDScript

## Componentes principales

| Componente | Responsabilidad |
|---|---|
| GameManager | Control de la partida |
| MatchController | Inicio y final de partida |
| CharacterBase | Movimiento y propiedades comunes |
| HunterController | Acciones del Hunter |
| GhostController | Acciones del Ghost |
| NetProjectile | Disparo y colisiones |
| CaptureSystem | Captura de Ghosts |
| Door | Apertura y cierre |
| LightSwitch | Control de iluminación |
| HidingSpot | Escondites |
| AIController | Comportamiento de IA |
| HUD | Interfaz |
| AudioManager | Sonidos |

## Nodos y herramientas de Godot

- `CharacterBody3D`: personajes.
- `Camera3D`: cámara.
- `NavigationRegion3D`: navegación.
- `NavigationAgent3D`: pathfinding de IA.
- `Area3D`: detección e interacción.
- `StaticBody3D`: paredes y obstáculos.
- `AnimatableBody3D`: puertas animadas con colisión.
- `OmniLight3D`: iluminación.
- `Timer`: temporizadores.
- `RayCast3D`: comprobaciones de visibilidad y obstáculos.

## Consideraciones para multiplayer futuro

Aunque el MVP será local y contra IA, debemos separar:

- Entrada del jugador.
- Lógica del personaje.
- Reglas del juego.
- Estado de los personajes.
- Sincronización futura.

La IA y el jugador deben utilizar las mismas acciones de gameplay. Por ejemplo, ambos deben invocar la misma función para disparar una red.

Más adelante, la arquitectura podrá migrar a un modelo de autoridad del servidor, donde el servidor controle las capturas, movimientos y resultados de las partidas.

No implementaremos networking en esta etapa.

# 15. Criterios de éxito del MVP

Consideraremos que el MVP cumple su objetivo cuando:

1. El jugador puede moverse cómodamente por toda la casa.
2. El Hunter puede disparar y capturar Ghosts.
3. Los Ghosts pueden escapar y esconderse.
4. Las puertas y luces funcionan correctamente.
5. La IA puede desplazarse y tomar decisiones básicas.
6. Las condiciones de victoria funcionan correctamente.
7. Es posible completar y reiniciar partidas.
8. El juego funciona en un dispositivo móvil real.
9. Las partidas generan situaciones interesantes.
10. El jugador tiene ganas de volver a jugar.

**El objetivo no es conseguir un juego visualmente terminado, sino validar que su mecánica principal es divertida.**

---

# 16. Plan de desarrollo del MVP

El proyecto se desarrollará por hitos. Cada hito debe producir algo jugable y comprobable. No se avanzará si el hito anterior tiene problemas fundamentales.

## Hito 1 — Proyecto y movimiento

- Crear proyecto Godot 3D.
- Configurar cámara Top-Down.
- Crear casa con geometría básica.
- Crear cápsula Hunter.
- Crear movimiento y colisiones.
- Crear cápsula Ghost.

**Resultado:** dos personajes que pueden moverse por la casa.

## Hito 2 — Sistema de cacería

- Implementar lanzador de redes.
- Detectar impactos.
- Implementar estados del Ghost.
- Implementar inmovilización.
- Implementar captura.
- Crear HUD básico.

**Resultado:** ya podemos jugar a perseguir y capturar.

## Hito 3 — Casa interactiva

- Crear puertas funcionales.
- Crear interruptores.
- Crear iluminación por habitaciones.
- Crear armarios.
- Implementar escondites y búsqueda.

**Resultado:** el escenario empieza a ofrecer posibilidades estratégicas.

## Hito 4 — Inteligencia artificial

- Configurar navegación.
- Crear estados de Ghost IA.
- Crear estados de Hunter IA.
- Implementar persecución y búsqueda.
- Implementar detección básica de ruido.

**Resultado:** podemos jugar partidas sin necesitar otros jugadores.

## Hito 5 — Sistema de partidas

- Temporizador.
- Preparación inicial.
- Selección de equipo.
- Condiciones de victoria.
- Pantalla de resultados.
- Reinicio.

**Resultado:** tenemos un juego funcional de principio a fin.

## Hito 6 — Experiencia móvil

- Joystick virtual.
- Botones contextuales.
- Ajustar cámara.
- Mejorar iluminación.
- Agregar sonidos.
- Optimizar rendimiento.
- Probar en teléfonos reales.

**Resultado:** primera versión jugable del MVP.

---

# 17. Arquitectura de escenas propuesta en Godot

```text
GhostHunter/
│
├── scenes/
│   ├── main/
│   │   ├── Main.tscn
│   │   └── MainMenu.tscn
│   │
│   ├── game/
│   │   ├── Game.tscn
│   │   └── House.tscn
│   │
│   ├── characters/
│   │   ├── CharacterBase.tscn
│   │   ├── Hunter.tscn
│   │   └── Ghost.tscn
│   │
│   ├── objects/
│   │   ├── Door.tscn
│   │   ├── LightSwitch.tscn
│   │   ├── HidingSpot.tscn
│   │   └── NetProjectile.tscn
│   │
│   └── ui/
│       ├── HUD.tscn
│       ├── MobileControls.tscn
│       └── ResultScreen.tscn
│
├── scripts/
│   ├── managers/
│   │   ├── GameManager.gd
│   │   └── MatchController.gd
│   │
│   ├── characters/
│   │   ├── CharacterBase.gd
│   │   ├── HunterController.gd
│   │   └── GhostController.gd
│   │
│   ├── ai/
│   │   ├── HunterAI.gd
│   │   └── GhostAI.gd
│   │
│   ├── objects/
│   │   ├── Door.gd
│   │   ├── LightSwitch.gd
│   │   └── HidingSpot.gd
│   │
│   └── systems/
│       ├── CaptureSystem.gd
│       └── AudioManager.gd
│
├── resources/
│   └── game_config.tres
│
├── assets/
│   ├── materials/
│   ├── models/
│   ├── audio/
│   └── textures/
│
└── project.godot
```

Esta estructura es una propuesta inicial. No necesitamos crear todos esos archivos desde el primer día.

# 18. Decisiones técnicas importantes

### Movimiento
Utilizar `CharacterBody3D` para los personajes. Es apropiado para controlar movimiento, colisiones y velocidad.

### Inteligencia artificial
Utilizar `NavigationAgent3D` para calcular rutas y máquinas de estados para decidir qué hacer. No necesitamos machine learning.

### Interacciones
Utilizar `Area3D` para detectar objetos cercanos. El botón contextual interactuará con el objeto válido más cercano.

### Rendimiento móvil
- Probar el renderizador Mobile de Godot en los dispositivos objetivo.
- Mantener geometría sencilla.
- Evitar exceso de luces dinámicas.
- Limitar efectos visuales costosos.
- Perfilar en dispositivo real temprano.

---

# 19. Validación y pruebas de gameplay

Después de implementar cada mecánica, probarla desde ambas perspectivas.

| Mecánica | Pregunta de validación |
|---|---|
| Movimiento | ¿Es cómodo perseguir y escapar? |
| Red | ¿Es difícil pero posible acertar? |
| Captura | ¿Genera tensión acercarse al Ghost? |
| Armarios | ¿Realmente sirven para engañar? |
| Puertas | ¿Cambian las posibilidades de escape? |
| Luces | ¿Aportan estrategia sin perjudicar la visibilidad? |
| IA | ¿Parece tomar decisiones razonables? |

No agregar funcionalidades nuevas simplemente porque sean posibles.

# 20. Prototype 01 — Primer objetivo de desarrollo

Antes de construir todos los sistemas, crear un prototipo muy pequeño.

### Contenido

- Una casa construida con cubos.
- Tres habitaciones conectadas.
- Una cápsula naranja (Hunter).
- Una cápsula celeste (Ghost).
- Cámara 3D ortográfica.
- Movimiento con teclado y joystick (joystick en una fase posterior).
- Colisiones con paredes.

### Todavía no tendrá

- Armas.
- Luces interactivas.
- IA.
- Sistema de partidas.
- Captura.
- Escondites.

### Objetivo

Comprobar que moverse por la casa resulta cómodo, que la cámara permite entender el espacio y que las colisiones funcionan correctamente.

Aunque el juego sea para móviles, inicialmente desarrollar y probar en PC utilizando teclado puede acelerar el trabajo. Después se incorporarán controles táctiles y se validará en Android/iOS.

---

# 21. Filosofía de desarrollo

Ghost-Hunter no debe convertirse en un juego donde el objetivo sea simplemente encontrar personajes escondidos. Debe ser un juego donde los jugadores intentan engañarse mutuamente.

- La casa es el tablero.
- Las puertas son herramientas.
- Las luces son una ventaja estratégica.
- Los armarios son oportunidades.
- Las redes son el mecanismo de captura.
- El ruido es información imperfecta.
- Las decisiones de los jugadores generan la diversión.

El objetivo del MVP es validar que el ciclo principal —persecución, escape, engaño y captura— sea divertido antes de invertir en contenido, personalización, progresión o multiplayer online.

---

# 22. Siguiente paso recomendado

Construir **Prototype 01 en Godot desde un proyecto vacío**.

No necesitamos más funcionalidades ni más planificación antes de comprobar que movernos por esa casa resulta divertido.
