# GHOST-HUNTER — Plan de trabajo del MVP

**Basado en:** `Ghost-Hunter_GDD_MVP_v0.1.md`
**Motor:** Godot 4.7 (renderizador Mobile, Jolt Physics) · GDScript
**Objetivo único del MVP:** responder *"¿es divertido?"* con el menor coste posible.

> Regla de oro: **cero arte propio**. Todo se representa con primitivas del motor (`CapsuleMesh`, `BoxMesh`, `CSGBox3D`, `Label3D`, `StandardMaterial3D` de color plano, `OmniLight3D`). Si una mecánica no es divertida con cubos, no lo será con modelos bonitos.

**Enfoque en dos etapas:**
1. **Validar que las mecánicas funcionan** con **maniquíes**: personajes colocados en escenarios de prueba, sin IA.
2. **Validar que el juego es divertido** con partidas completas contra la **IA**, que se construye al final, con reglas ya probadas.

---

## 1. Sugerencias respecto al GDD

### 1.1. Maniquíes y escenarios de prueba antes de la IA
Mientras no hay IA, los rivales son **maniquíes**: la misma escena de Hunter o Ghost, pero controlada por un `DummyController` que no hace nada (o casi nada). Así las mecánicas se prueban sobre el **código real** de los personajes, no sobre objetos de mentira.

Cada maniquí se coloca con un nodo `DummySpawn` (`Marker3D` con `@export`) que define:
- **Rol:** Hunter o Ghost.
- **Estado inicial:** libre, dentro del armario X, de espaldas, etc.
- **Comportamiento:** `ESTÁTICO` (por defecto) o `RUTA` (sigue un `Path3D` en bucle, sin tomar decisiones).

**Escenario de prueba jugando como Hunter** (`TestHunter.tscn`):
| Maniquí | Qué permite probar |
|---|---|
| Ghost dentro de un armario | Registrar, revelar y expulsar. |
| Ghost en el centro de una habitación iluminada | Disparo, alcance, impacto, inmovilización y captura. |
| Ghost en una esquina de una habitación a oscuras | Radio de visión reducido por la oscuridad. |
| Ghost detrás de una puerta cerrada | La puerta bloquea la visión y la red. |
| Ghost en `RUTA` cruzando un pasillo | Acertar a un objetivo en movimiento. |

**Escenario de prueba jugando como Ghost** (`TestGhost.tscn`):
| Maniquí | Qué permite probar |
|---|---|
| Hunter estático mirando un pasillo | ¿Me ve o no me ve? Luz, sombras, puertas y armarios. |
| Hunter en `RUTA` patrullando habitaciones | Esconderse a tiempo, usar puertas, apagar luces para pasar sin ser visto. |
| *(Opcional)* Hunter "torreta": si te ve, está a rango y tiene la red cargada, dispara | Ser atrapado, el tiempo de inmovilización y el escape. Son ~10 líneas de código, no es IA. |

**Herramientas de depuración que lo hacen útil:**
- **R** reinicia el escenario (todos los maniquíes vuelven a su posición).
- **Tab** cambia el control entre el Hunter y un Ghost del escenario. Como la entrada está separada de la lógica, basta con pasar el `PlayerInput` de un personaje a otro, y permite probar ambos lados sin cambiar de escena.
- **F2** muestra el radio de visión del Hunter (disco en el suelo) y los rayos de línea de visión (verde = te ve, rojo = bloqueado).

> Importante: los maniquíes confirman que **las mecánicas funcionan y se sienten bien** (acertar, capturar, esconderse). La pregunta **"¿es divertido?"** solo puede responderse con rivales que reaccionan, es decir, al terminar la IA (Fase 6).

### 1.2. Visión del Hunter (falta en el GDD y es crítica)
Si la cámara cenital muestra toda la casa, el Ghost solo puede esconderse dentro de armarios y el pilar de *engaño* desaparece. Hace falta definir **qué ve el Hunter**:
- Un Ghost solo se dibuja para el Hunter si hay **línea de visión** (`PhysicsRayQueryParameters3D`) y está dentro de su **radio de detección**.
- El radio depende de la luz de la habitación (ej.: 9 m con luz, 4 m a oscuras). Así las luces se vuelven estrategia de verdad.
- Jugando como Hunter, los Ghosts fuera de visión no se dibujan (`visible = false`).
- Jugando como Ghost, el Hunter se ve siempre (ventaja de información asimétrica). Se deja configurable para probar ambas variantes.
- La IA del Hunter usará **exactamente la misma función** de visión, así no hace trampas.

### 1.3. Paredes bajas en lugar de paredes transparentes
Ocultar o volver transparentes las paredes que tapan la cámara requiere shaders y lógica de oclusión. Para el prototipo: **paredes de ~1,2 m** (estilo "casa de muñecas"). La cámara ve por encima, la visión del Hunter sigue bloqueada por raycast y el problema queda resuelto con cero código.

### 1.4. Todos los valores ajustables en caliente
- Un `Resource` `GameConfig` (`game_config.tres`) con todos los números del GDD (`@export`).
- Un **panel de depuración** (F1) con sliders para cambiar velocidades, recargas, radios de visión, etc. durante el juego.
- Interruptores para **activar o desactivar mecánicas** (puertas, luces, armarios, ruido, visión) y hacer pruebas A/B.

### 1.5. Pequeños ajustes de diseño para probar
| Propuesta | Motivo |
|---|---|
| Partidas de **3 min** al principio (configurable hasta 6) | Más partidas por sesión y feedback más rápido. |
| Registrar un armario **cuesta ~1 s** al Hunter | Riesgo/recompensa: cada registro fallido es tiempo perdido. |
| **Enfriamiento** de 5 s tras ser expulsado de un armario | Evita el bucle "me sacan → vuelvo a entrar". |
| "Latido"/ruido leve si el Hunter está cerca de un armario ocupado | El armario no es 100 % seguro y genera tensión en ambos lados. |
| *(Experimento opcional)* Pulsar repetidamente acorta la red | Da agencia al Ghost atrapado si la captura se siente pasiva. |
| Empezar con **3 habitaciones** y crecer a 5 solo si hace falta | Menos trabajo de nivel; ampliar es fácil. |

### 1.6. Sonido provisional desde el primer día
Se generan efectos con **jsfxr / Bfxr** (gratis, en el navegador) en minutos. Sin pasos, disparo e impacto audibles, las mecánicas se sienten peor de lo que son.

---

## 2. Representación visual con primitivas de Godot

| Elemento | Nodo / recurso | Aspecto |
|---|---|---|
| Hunter | `CharacterBody3D` + `CapsuleMesh` | Naranja. Un `BoxMesh` pequeño al frente como "nariz"/lanzador para ver la orientación. |
| Ghost | `CharacterBody3D` + `CapsuleMesh` | Celeste, `transparency = alpha` (≈0,75). Emisión suave para destacar en la oscuridad. |
| Maniquí | La misma escena del personaje | Igual que el personaje, con un `Label3D` "DUMMY" encima para distinguirlo. |
| Ghost atrapado | `SphereMesh` en *wireframe* o `TorusMesh` alrededor | Blanco, simula la red. Parpadea cuando está a punto de liberarse. |
| Paredes | `CSGBox3D` con `use_collision = true` | Gris azulado oscuro, 1,2 m de alto. |
| Suelo | `CSGBox3D` / `PlaneMesh` | **Un color distinto por habitación** para orientarse sin texturas. |
| Puertas | `AnimatableBody3D` + `BoxMesh` | Marrón claro con borde blanco; giran con `Tween` sobre la bisagra. |
| Armarios | `StaticBody3D` + `BoxMesh` + `Area3D` | Violeta. Tiembla levemente (`Tween`) si está ocupado y el Hunter está cerca. |
| Interruptores | `BoxMesh` pequeño + `Area3D` | Blanco; emisivo amarillo cuando está encendido. |
| Luz de habitación | `OmniLight3D` | Amarillo cálido. `WorldEnvironment` con ambiente azul oscuro tenue: nunca negro total. |
| Muebles / obstáculos | `CSGBox3D`, `CSGCylinder3D` | Marrón/gris; mesas, sofás y camas como bloques. |
| Proyectil de red | `Area3D` + `SphereMesh` | Blanco emisivo, pequeño. |
| Ruido | `TorusMesh` que se expande (`Tween`) | Anillo blanco en una posición **aproximada** (con desplazamiento aleatorio). |
| Indicador de interacción | `Label3D` *billboard* | "E · ABRIR", "E · ESCONDERSE", "E · CAPTURAR". |
| Visión (depuración) | `MeshInstance3D` con `CylinderMesh` plano + `ImmediateMesh` para rayos | Disco translúcido y líneas verde/rojo. |
| HUD | `Control` + `Label` / `ProgressBar` | Temporizador, Ghosts restantes, recarga, progreso de captura. |
| Feedback ("juice") | `Tween`, sacudida de cámara, `CPUParticles3D` | Escala al impactar, sacudida al capturar. `CPUParticles3D` por compatibilidad móvil. |

La casa se construye con **CSG**: es lo más rápido para iterar en el editor y la navegación (`NavigationRegion3D`) puede generarse sobre esa geometría. Si más adelante hace falta rendimiento, los CSG se convierten a `MeshInstance3D`.

---

## 3. Arquitectura mínima

```
PlayerInput | DummyController | AIController | (futuro) NetworkInput
        │  producen "intenciones": move_dir, aim_dir, fire, interact
        ▼
CharacterBase (Hunter / Ghost)  ← misma API para humano, maniquí e IA
        │  emite señales: net_fired, netted, captured, hid, noise_made
        ▼
MatchController  ← reglas, temporizador, victoria
```

- **Separar la entrada de la lógica** es lo único de arquitectura imprescindible. Con eso, el maniquí, el cambio de control con Tab, la IA y el multijugador futuro son solo "otro controlador".
- El `DummyController` se reemplaza más tarde por el `AIController` sin tocar los personajes ni los escenarios de prueba, que seguirán sirviendo para depurar la IA.
- Un objeto interactivo implementa `interact(actor)` y `get_prompt(actor)`. El personaje elige el más cercano dentro de su `Area3D`.
- Comunicación por **señales**. `GameManager` como *autoload* solo para el estado global de la partida.
- La estructura de carpetas del GDD (sección 17) es válida. Los archivos se crean cuando se necesitan; los escenarios de prueba van en `scenes/test/`.

---

## 4. Fases de trabajo

Cada fase termina en algo **jugable** y en una **puerta de decisión**. Estimaciones en *jornadas de trabajo enfocado (~4 h)*, orientativas.

### Fase 0 — Preparación · ~0,5 jornada
- [x] Estructura de carpetas (`scenes/`, `scripts/`, `resources/`, `scenes/test/`).
- [x] *Input Map*: WASD movimiento, ratón para apuntar, clic/espacio disparar, E interactuar, Shift sigilo (por defecto se corre a velocidad máxima), R reiniciar, Tab cambiar de personaje, F1/F2 depuración.
- [x] `GameConfig` con todos los valores del GDD.
- [x] Panel de depuración vacío (F1) y un `Label` con FPS.

### Fase 1 — Prototype 01: movimiento y casa · ~2 jornadas
*(Hito 1 del GDD)*
- [x] Casa de 3 habitaciones + pasillo con CSG, paredes bajas, suelos de colores.
- [x] Cámara `Camera3D` ortográfica, ~65°, seguimiento suave, zoom configurable.
- [x] `CharacterBase` con movimiento, aceleración/frenado y rotación hacia la dirección.
- [x] Escenas de Hunter y Ghost (cápsulas).
- [x] `PlayerInput` + `DummyController` + `DummySpawn`; cambio de control con **Tab** y reinicio con **R**.

**Puerta 1:** ¿Moverse se siente cómodo? ¿Se entiende el espacio con la cámara? ¿Las colisiones son limpias (sin engancharse en esquinas)?

### Fase 2 — Núcleo de cacería + visión · ~3 jornadas
*(Hito 2 del GDD + sugerencia 1.2)*
- [x] Disparo de red: proyectil, alcance 6 m, recarga 3 s, no atraviesa paredes.
- [x] Estados del Ghost: `FREE`, `NETTED`, `CAPTURED` (`HIDDEN` llega con los armarios en la Fase 3).
- [x] Inmovilización 5 s + captura manteniendo pulsado 1,5 s a ≤1,5 m.
- [x] **Visión**: cono (ángulo + radio) + línea de visión para Hunter y Ghost; los Ghosts fuera de visión se ocultan al Hunter. Conos visibles por defecto (F2 para ocultarlos).
- [x] Maniquí con comportamiento `RUTA` (recorre los puntos de un `Path3D` en bucle y abre las puertas cerradas).
- [x] HUD básico: Ghosts restantes, recarga, progreso de captura.
- [ ] Sonidos provisionales: pasos, disparo, impacto, captura.
- [x] `TestHunter.tscn` con los maniquíes de habitación iluminada, pasillo con ruta y habitación oscura.

**Puerta 2:** Contra maniquíes:
- ¿Acertar a uno quieto es fácil y a uno en movimiento es difícil pero posible?
- ¿La captura de 1,5 s se siente como un momento de tensión o como una espera?
- ¿El sistema de visión es claro: entiendo por qué veo o no veo a un Ghost?

### Fase 3 — Casa interactiva · ~3 jornadas
*(Hito 3 del GDD)*
- [x] Puertas (correderas): abrir/cerrar, bloquean paso, visión y red; producen ruido. No se cierran con alguien en el hueco.
- [x] Luces por habitación + interruptores; la oscuridad reduce el radio de visión.
- [x] Armarios: esconderse, salir, registrar (1 s), revelar/expulsar, enfriamiento, latido.
- [x] Ruido: correr, puertas, interruptores y armarios generan un anillo aproximado visible para el Hunter.
- [x] Interruptores en el panel F1: luces afectan visión, ruido, latido, visión oculta Ghosts (las puertas no se pueden desactivar).
- [x] Completar `TestHunter.tscn` (Ghost en armario, Ghost tras una puerta) y crear `TestGhost.tscn` (Hunter estático, Hunter en ruta y Hunter torreta).
- [ ] Ampliar a 5 habitaciones si el mapa se queda pequeño.

**Puerta 3:** Como Ghost frente al Hunter en ruta: ¿puedo pasar sin ser visto usando puertas, sombras y armarios? Como Hunter: ¿registrar armarios y leer el ruido se entiende? Si una mecánica no aporta nada en los escenarios de prueba, se simplifica o se pospone.

### Fase 4 — Ciclo de partida · ~1,5 jornadas
*(Hito 5 del GDD)*
- [x] Menú mínimo: jugar como Hunter / jugar como Ghost / escenarios de prueba / abrir carpeta de datos.
- [x] Temporizador, preparación de 8 s (Hunter bloqueado y con la vista tapada).
- [x] Victoria/derrota según el GDD, con prioridad a la captura en el último instante.
- [x] Pantalla de resultados con estadísticas, valoración de diversión (1–5) y botón "Jugar otra vez".
- [x] **Registro de partidas** en `user://playtests.csv`: duración, ganador, capturas, tiempo escondido, redes disparadas/acertadas, puertas, luces, diversión y si se quiso jugar otra.
- [x] Se prueba con maniquíes (como Hunter, 2 Ghosts quietos en sitios aleatorios, a veces en armarios; como Ghost, un Hunter que patrulla, dispara y captura) para validar el flujo completo antes de la IA.

### Fase 5 — Inteligencia artificial · ~5 jornadas
*(Hito 4 del GDD)*
- [x] `NavigationRegion3D` generada al arrancar (sin las puertas); la IA abre las puertas cerradas al llegar.
- [x] **Ghost IA**: `ROAM`, `IDLE`, `FLEE` (cierra puertas, busca la oscuridad y romper la línea de visión), `HIDE`/`HIDDEN` (solo si no le ven), `ESCAPE`; apaga luces.
- [x] **Hunter IA**: `PATROL`, `INVESTIGATE`, `CHASE` (incluye disparar), `CAPTURE`, `SEARCH`, usando solo visión, ruido y el latido de los armarios; enciende luces.
- [x] `Label3D` encima de cada IA con su estado actual (visible con F2).
- [x] Dificultad: reacción, error de puntería, anticipación, prob. de registrar/esconderse/apagar luces… en el panel F1 (grupo IA).
- [x] Escenario `TestAI` (tecla 4): IA contra IA en modo espectador (P toma/suelta el control) + simulador `tools/ai_simulation.tscn` para equilibrar sin mirar.

### Fase 6 — Prueba de diversión · ~1–2 jornadas + continuo
**Puerta principal del MVP.** Primeras partidas completas contra la IA, en ambos roles.
- [ ] Jugar 10+ partidas por rol y rellenar el cuestionario (sección 5).
- [ ] Revisar el CSV y ajustar valores con el panel de depuración.
- [ ] Si no es divertido: revisar visión, tamaño del mapa, ritmo y velocidades **antes** de añadir nada.

### Fase 7 — Móvil · ~3 jornadas
*(Hito 6 del GDD)*
- [ ] Joystick virtual + botón principal + botón contextual (con el texto de la acción).
- [ ] Apuntado móvil: auto-apuntado suave hacia el Ghost visible más cercano.
- [ ] Ajustar cámara y zoom para pantalla de teléfono.
- [ ] Exportar a Android, probar en dispositivo real y perfilar FPS con varias luces.

**Puerta 7:** ¿Sigue siendo divertido con controles táctiles?

**Total orientativo:** ~20 jornadas hasta el MVP en móvil.
- Mecánicas validadas con maniquíes: **~10 jornadas** (fin de la Fase 3).
- Primera respuesta sobre la diversión: **~16 jornadas** (Fase 6).

---

## 5. Cómo medir la diversión (Fase 6 en adelante)

Sin otros probadores, la herramienta principal es la honestidad con uno mismo y los datos.

### Cuestionario rápido (tras cada partida, 30 segundos)
1. Del 1 al 5, ¿cuánto me divertí?
2. ¿Hubo algún momento de tensión? ¿Cuál?
3. ¿Gané/perdí por mis decisiones o por azar/injusticia de la IA?
4. ¿Qué me frustró?
5. **¿Quiero jugar otra partida?** ← la métrica más importante.

Conviene apuntar las respuestas en el mismo CSV o en un archivo de notas. Cuando sea posible, pedir a 2–3 personas que jueguen unas partidas en el móvil aunque sea sin explicación: su primera reacción vale mucho.

### Señales en los datos (CSV)
| Señal | Saludable | Problema |
|---|---|---|
| Ganador por bando | 40–60 % | Un bando gana casi siempre → rebalancear o ajustar la IA. |
| Duración media | A veces termina antes del tiempo, a veces no | Siempre agota el tiempo o siempre termina en 30 s. |
| Precisión de red | 25–50 % | <15 % frustrante · >70 % trivial. |
| Uso de armarios/puertas/luces | Se usan en la mayoría de partidas | Nunca se usan → no aportan o no se entienden. |
| Escapes tras red | Ocurren a veces | Nunca (captura demasiado fácil) o casi siempre. |

### Criterio de "sí, es divertido"
Sigues queriendo jugar "una más" aunque ya no estés probando nada concreto, y las partidas producen anécdotas ("se escondió justo cuando entré a la habitación"). Si no ocurre, es mejor replantear el diseño que seguir añadiendo sistemas.

---

## 6. Qué NO hacer durante el MVP
- Modelos, texturas, animaciones o shaders propios.
- Transparencia de paredes, menús elaborados, ajustes gráficos.
- Networking (solo mantener la entrada separada).
- Cualquier elemento de la sección 13 del GDD.
- Añadir mecánicas nuevas antes de pasar la puerta de la fase actual.

---

## 7. Próximo paso
Empezar la **Fase 0 + Fase 1**: estructura del proyecto, *Input Map*, `GameConfig`, la casa de 3 habitaciones con CSG, el Hunter y el Ghost como cápsulas, el maniquí y el cambio de control con Tab.
