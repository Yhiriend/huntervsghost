# ¿CAZADOR O PRESA? — Plan de rendimiento

Qué hay que medir, cómo se mide, cómo se interpreta y qué hacer según el resultado.
Está escrito para quien continúe el proyecto. Incluye el estado actual (noviembre de 2026) y los pasos pendientes.

**Contexto:** Godot 4.7.2, renderizador **Mobile** (Vulkan en Android, Metal en Mac). Plataforma objetivo: **Android**. El dispositivo de referencia es un POCO F7 (adb id `6528ab91`).

---

## 1. Objetivos

| Métrica | Objetivo | Por qué |
|---|---|---|
| FPS en partida (móvil) | **60 estables** | El juego limita a 60 en el móvil (`max_fps_mobile`). |
| Tiempo por fotograma, p95 | **≤ 16,6 ms** | Si el 5 % peor supera 16,6 ms, se notan tirones aunque la media sea buena. |
| Menú | 60 FPS sin calentar el móvil | El fondo es un decorado: no debe costar más que la partida. |
| Tras 10 min de partida | Sigue a 60 FPS | Por encima de eso el móvil se calienta y baja la frecuencia (*throttling*). |
| Memoria de vídeo | < 400 MB | Margen para móviles de gama media. |
| Ping online | Lo más bajo posible (ver §7) | Depende sobre todo de la distancia al servidor. |

Hay que cumplirlos con **gráficos altos** en un móvil de gama media-alta. En uno de gama baja basta con cumplirlos usando «gráficos bajos».

---

## 2. Herramientas

### 2.1. Prueba de rendimiento: `scenes/test/Rendimiento.tscn`
Script: `scripts/test/rendimiento.gd`. Mide el tiempo medio por fotograma, los FPS, el p95, las *draw calls* y los triángulos en cada escena:
- menú;
- partida (`Prototype01`);
- IA contra IA (`TestAI`).

Repite cada medida con cada efecto apagado: gráficos bajos, sin fondo 3D, 3D a resolución nativa y sin jardín.

| Modo | Cómo se lanza | Qué mide |
|---|---|---|
| **Móvil (real)** | En el juego: *Más opciones › Escenarios de prueba › Prueba de rendimiento (1 min)* | El coste real en la pantalla del móvil, sin límite de FPS. Muestra la tabla y la guarda en `user://rendimiento.txt`. |
| **PC, GPU** | `Godot --path . res://scenes/test/Rendimiento.tscn` | Dibuja en una imagen de 7680×3456, unas 10 veces los píxeles de un móvil, para que el PC quede limitado por la GPU. **Solo sirve para comparar filas entre sí**, no para predecir los FPS del móvil. |
| **PC, real** | `... -- --real` (con `--resolution 2400x1080`) | Como en el móvil, pero un PC potente da siempre ~2,7 ms: es el suelo de medida, no el coste de la escena. |
| **PC, CPU** | `Godot --headless --fixed-fps 60 --path . res://scenes/test/Rendimiento.tscn` | Sin dibujar, con un paso de física por fotograma: coste de scripts, física, IA y navegación. |

Opciones: `-- --frames=300 --px=7680x3456 --real`.

Para leer el resultado del móvil sin tocarlo:
```bash
adb -s <id> shell run-as com.yhiriend.cazadoropresa cat files/rendimiento.txt
```

Para lanzar la prueba desde el PC (MIUI bloquea los toques por adb, pero no abrir la app): abre la app, navega a mano hasta la prueba y deja el móvil quieto 1 minuto.

### 2.2. Capturas: `tools/capturas.tscn`
Para revisar el aspecto sin móvil. Se ejecuta con ventana, no en modo headless:
```bash
Godot --path . res://tools/capturas.tscn --resolution 1600x720 -- --out=/carpeta
```
Guarda `cazador.png`, `presa.png`, `vista_general.png` y `menu.png`. Úsalo para comprobar que una optimización no cambia el aspecto.

### 2.3. Otras
- **Panel de depuración (F1 / botón Ajustes):** muestra FPS, *draw calls* y ping, y permite cambiar en caliente los ajustes de `GameConfig`, incluido el grupo «Rendimiento».
- **Monitor de Android:** `adb shell dumpsys gfxinfo com.yhiriend.cazadoropresa` para ver fotogramas lentos, y `adb shell dumpsys thermalservice` para la temperatura y el estado de *throttling*.
- **Batería:** `adb shell dumpsys batterystats --reset`, juega 10 min y luego `adb shell dumpsys batterystats com.yhiriend.cazadoropresa`.

---

## 3. Ajustes de rendimiento existentes

En `scripts/resources/game_config.gd`, grupo **Rendimiento**. Se aplican con `GameManager.apply_graphics()` al arrancar y al cambiarlos en el panel.

| Ajuste | Por defecto | Efecto |
|---|---|---|
| `max_fps_mobile` | 60 | Límite de FPS en el móvil. Sin él, una pantalla de 120 Hz dibuja el doble. |
| `render_scale_mobile` | 0,8 | Resolución del 3D en el móvil. La interfaz va siempre a resolución completa. Con 0,8 se dibujan un 36 % menos de píxeles. |
| `graphics_low` | false | Sin glow, césped de color plano y linterna del menú sin sombra. Los nodos que reaccionan están en el grupo `graphics_quality` y tienen el método `apply_graphics_quality(low)`. |

Otras decisiones ya tomadas:
- **Fondo del menú** (`scripts/ui/menu_background.gd`): se dibuja a media resolución (`stretch_shrink = 2`) y a 30 FPS.
- **Jardín y acera:** son anillos alrededor de la casa, no planos enteros, para no dibujar píxeles debajo del suelo. El césped usa solo dos capas de ruido.
- **Shaders de suelo y pared:** no usan texturas y cuestan lo mismo que un material plano (medido).
- **Entorno compartido:** `scenes/game/house_environment.tres`, usado por la partida, las pruebas y el menú. Si se cambia aquí, cambia en todas partes.

---

## 4. Datos medidos hasta ahora (Mac M4)

### 4.1. GPU (imagen de 7680×3456; solo comparación relativa)

| Escena | Antes de optimizar | Ahora | Gráficos bajos |
|---|---|---|---|
| Menú (sin fondo 3D, versión antigua) | 2,3 ms | — | — |
| Menú con fondo 3D | 10,7 ms | 4,8 ms | 2,4 ms |
| Partida | 7,8 ms | 6,8 ms | 5,8 ms |
| IA contra IA | — | 7,1 ms | — |

Coste aproximado de cada elemento en la partida:

| Elemento | Coste |
|---|---|
| Jardín y alfombras | ~1,2 ms (era 2,2 ms antes de convertirlos en anillos) |
| Glow | ~0,3 ms |
| Suelos y paredes con shader | ≈ 0 ms (igual que un material plano) |
| Sombra de la linterna del menú y MSAA del fondo | casi nada |

### 4.2. CPU (sin dibujar)

| Escena | ms por fotograma |
|---|---|
| Partida | 0,31 (p95 0,37) |
| IA contra IA | 0,46 (p95 0,58) |

Conclusión: **la CPU no es el cuello de botella**. Aunque un móvil sea 4–5 veces más lento, sigue muy lejos de los 16,6 ms. Si en el móvil hay tirones, lo primero que hay que sospechar es la GPU o el calor.

### 4.3. Pendiente
- [ ] **Medir en el POCO F7.** Es el siguiente paso; ver §5.

---

## 5. Qué medir en el móvil (en este orden)

1. **Prueba de rendimiento** (1 min) con los ajustes por defecto. Guarda la tabla en este documento, en §4, como «POCO F7».
2. **Partida real de 10 minutos** contra la IA, con el panel de FPS visible. Anota:
   - los FPS al principio y al final;
   - si hay tirones (en qué momento y en qué habitación);
   - la temperatura al final (`dumpsys thermalservice`).
3. **Misma partida con «gráficos bajos».** Compara FPS y temperatura.
4. **Batería:** porcentaje gastado en 10 minutos con cada ajuste.
5. **Si hay un segundo móvil de gama baja**, repite los pasos 1 y 2. Ahí se decide si «gráficos bajos» basta o hace falta más.

Anota siempre: modelo, versión de Android, hercios de la pantalla, brillo y si estaba cargando. Todo eso cambia los resultados.

---

## 6. Cómo interpretar y qué hacer

| Si en el móvil... | Probable causa | Qué hacer |
|---|---|---|
| Partida < 60 FPS y «3D a resolución nativa» es mucho peor que «Juego» | Límite de GPU por píxeles | Bajar `render_scale_mobile` (0,7) o probar `SCALING_3D_MODE_FSR` (comprobar el coste del filtro en el móvil). |
| «Gráficos bajos» mejora mucho | Efectos (glow, ruido del césped) | Activar gráficos bajos automáticamente en móviles lentos (ver la tarea B3). |
| «Sin jardín/alfombras» mejora mucho | Shaders de pantalla completa | Hornear el césped en una textura pequeña (tarea B2). |
| Menú lento pero partida bien | Fondo 3D | Bajar el fondo a 20 FPS o sustituirlo por una imagen pre-renderizada. |
| Empieza a 60 FPS y baja tras unos minutos | Calor (*throttling*) | Limitar a 30 FPS en el menú; valorar `render_scale_mobile` 0,7 por defecto. |
| p95 alto con media buena | Picos: carga, cálculo de rutas de la IA, recolección de basura | Medir con el perfilador del editor conectado al móvil (*Remote debug*) y buscar el pico. |
| Muchas *draw calls* (> 300) | Demasiados objetos | Unir mallas estáticas o usar MultiMesh para la decoración repetida. |
| Partida bien en todos los casos | — | Nada. No optimizar sin una medida que lo justifique. |

Regla: **cada optimización se mide antes y después** con la misma prueba y en el mismo dispositivo. Además se comprueba con `tools/capturas.tscn` que el aspecto no cambia, salvo que se busque cambiarlo.

---

## 7. Latencia online (pendiente, aparte del rendimiento gráfico)

Situación medida:
- El servidor de salas (*relay*) está en un VPS de OVH en Beauharnois (Canadá). Desde la red de pruebas, el ping ICMP mínimo es de ~92–96 ms tanto en el Mac como en el POCO.
- El juego muestra la ida y vuelta completa pasando dos veces por el servidor (cliente → VPS → anfitrión → VPS → cliente). En una prueba en vivo salió un mínimo de 191 ms.
- En los móviles se ve ~260 ms. Hay un caso sin explicar: un PC mostró ~80 ms, que no cuadra con el camino por el servidor. Probablemente fuera una partida en red local; hay que confirmarlo.

Ya hecho:
- envío inmediato con `flush()` en el cliente y en el servidor;
- ENet sin *throttle*;
- red atendida antes de cada paso de física;
- modo Wi-Fi de baja latencia en Android (`LowLatencyWifi`).

Tareas:
- [ ] **L1.** Añadir al panel de depuración el desglose del ping: red frente a espera de fotogramas en cada extremo.
- [ ] **L2.** Aclarar el caso del PC a ~80 ms: ¿red local u online?
- [ ] **L3.** Si se necesita menos latencia, poner un relay más cercano a los jugadores (por ejemplo Miami o São Paulo para Latinoamérica). El código del relay (`server/`) es independiente del VPS actual; hay instrucciones en `server/LEEME.md`.

---

## 8. Lista de tareas (backlog)

Ordenada por prioridad. **No empezar ninguna sin una medida en el móvil que la justifique** (§5 y §6).

| Id | Tarea | Cuándo |
|---|---|---|
| A1 | Medir en el POCO F7 (§5) y anotar los resultados en §4 | **Ya** |
| A2 | Partida de 10 min: FPS, temperatura y batería | **Ya** |
| B1 | Ajustar los valores por defecto (`render_scale_mobile`, `max_fps_mobile`) según A1/A2 | Tras A1 |
| B2 | Hornear el césped en una textura de 256×256 en lugar de calcular ruido | Si «sin jardín» mejora mucho |
| B3 | Calidad automática: si los FPS medios < 50 durante 10 s, activar `graphics_low` y avisar | Si hay móviles lentos |
| B4 | Opción «Gráficos» visible en el menú (alta/baja), no solo en el panel de depuración | Antes de publicar |
| B5 | Guardar los ajustes de rendimiento en `user://ajustes.cfg` para que persistan | Junto con B4 |
| B6 | Menú a 30 FPS cuando no hay interacción | Si el menú calienta el móvil |
| C1 | Perfil remoto del editor en el móvil para buscar picos de p95 | Si p95 > 16,6 ms |
| C2 | Tamaño del APK (~34 MB): revisar la importación de audio y texturas | Antes de publicar |
| L1–L3 | Latencia online (§7) | Cuando se retome el online |

---

## 9. Cómo añadir algo nuevo sin romper el rendimiento

- **Efecto o decoración nueva:** añade una fila a `scripts/test/rendimiento.gd` que mida la escena con y sin él, y compara en el modo GPU del PC.
- **Algo caro:** que respete `graphics_low` (grupo `graphics_quality` + `apply_graphics_quality(low)`).
- **Shaders de pantalla completa:** pocas operaciones por píxel, sin bucles y sin texturas grandes.
- **Mallas grandes de decorado:** que no se dibujen debajo de otras (la sobrecarga de dibujo cuenta en el móvil).
- **Antes de subir:** pasa `tests/run_all.sh` (debe decir «TODO OK») y saca capturas con `tools/capturas.tscn`.
