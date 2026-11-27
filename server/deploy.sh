#!/bin/bash
# Sube el servidor de salas a tu VPS y lo instala (o lo actualiza). Desde la carpeta del proyecto:
#   server/deploy.sh ubuntu@1.2.3.4                      (con tu clave SSH habitual)
#   server/deploy.sh ubuntu@1.2.3.4 ~/Downloads/clave.pem  (p. ej. la clave .pem de AWS)
set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Uso: server/deploy.sh usuario@ip [clave.pem]" >&2
	exit 1
fi
TARGET="$1"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
if [ $# -ge 2 ]; then
	chmod 600 "$2"
	SSH_OPTS+=(-i "$2")
fi
cd "$(dirname "$0")"

ssh "${SSH_OPTS[@]}" "$TARGET" "mkdir -p ~/cazador-relay"
scp "${SSH_OPTS[@]}" relay_protocol.gd relay_server.gd relay_main.gd install_vps.sh "$TARGET":~/cazador-relay/
ssh "${SSH_OPTS[@]}" "$TARGET" "sudo bash ~/cazador-relay/install_vps.sh"
