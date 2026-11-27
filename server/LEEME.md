# Servidor de salas (jugar por internet)

El servidor no ejecuta el juego, solo reenvía paquetes. Quien crea la sala es el anfitrión y simula la partida, igual que en red local. El servidor le da un código de 4 letras, y los demás entran con ese código desde *Multijugador → Por internet*.

Consume muy poco: un servidor con 512 MB de RAM aguanta de sobra decenas de salas.

## Servidor actual

- **Dónde:** VPS Ubuntu 24.04 en `51.79.58.49`, puerto UDP 24680. Ya está configurado en `DEFAULT_ONLINE_SERVER`.
- **Comparte máquina con otras webs:** corren en Docker con Dokploy (puertos 80, 443 y 3000). No hay que tocarlas.
- **Cómo corre el servidor de salas:** como servicio de systemd (`cazador-relay`), fuera de Docker. Sus archivos están en `/opt/cazador-relay`.
- **Actualizarlo:** `server/deploy.sh root@51.79.58.49`.

## Montarlo en AWS Lightsail

1. **Crear la instancia.** En [lightsail.aws.amazon.com](https://lightsail.aws.amazon.com), entra en *Create instance* y elige:
   - plataforma **Linux/Unix**, blueprint **OS Only → Ubuntu 24.04 LTS**;
   - el plan más barato (512 MB, unos 3,5–5 USD/mes; suele traer meses gratis).
2. **Descargar la clave SSH.** En *Account → SSH keys*, descarga la clave por defecto de tu región: un archivo `.pem`.
3. **Fijar la IP.** En *Networking*, crea una **Static IP** y asígnala a la instancia. Así la IP no cambia al reiniciar.
4. **Abrir el puerto.** En la pestaña *Networking* de la instancia, dentro de *IPv4 Firewall*, pulsa *Add rule*:
   - protocolo **UDP**;
   - puerto **24680**.
5. **Instalar el servidor.** Desde la carpeta del proyecto, en tu Mac:
   ```sh
   server/deploy.sh ubuntu@TU_IP ~/Downloads/LightsailDefaultKey-us-east-1.pem
   ```
   El script descarga Godot para Linux, copia el servidor y deja un servicio que arranca solo.
6. **Configurar la IP en el juego.** Escribe la IP en `DEFAULT_ONLINE_SERVER`, en `scripts/autoload/net_manager.gd`, y exporta el APK de nuevo. Así el APK que compartes ya viene configurado. También se puede escribir en *Multijugador → Servidor*.

Con EC2 el proceso es el mismo: el usuario de Ubuntu es `ubuntu`, el puerto se abre en el *Security Group* (regla de entrada UDP 24680) y la IP fija es una *Elastic IP*.

## Mantenimiento

- **Actualizar el servidor:** vuelve a ejecutar `server/deploy.sh`.
- **Ver el registro:**
  ```sh
  ssh -i clave.pem ubuntu@TU_IP sudo journalctl -u cazador-relay -f
  ```
- **Reiniciar:**
  ```sh
  ssh -i clave.pem ubuntu@TU_IP sudo systemctl restart cazador-relay
  ```
- **Cambios de protocolo:** si cambias `server/relay_protocol.gd`, sube `VERSION` y actualiza el servidor y el APK a la vez. Las versiones antiguas reciben el aviso de que deben actualizar.
