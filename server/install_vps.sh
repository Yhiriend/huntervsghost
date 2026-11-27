#!/bin/bash
# Instala el servidor de salas de ¿Cazador o Presa? en un VPS Linux (Ubuntu/Debian, x86_64 o ARM).
# Normalmente lo ejecuta server/deploy.sh desde tu ordenador. A mano, en el VPS:
#   sudo bash install_vps.sh            (desde la carpeta con relay_*.gd)
# Deja un servicio "cazador-relay" que arranca solo y se reinicia si falla. Puerto: UDP 24680.
set -euo pipefail

GODOT_VERSION="4.7.2"
PORT="${PORT:-24680}"
DIR=/opt/cazador-relay
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
	echo "Ejecútalo con sudo." >&2
	exit 1
fi

case "$(uname -m)" in
	x86_64) ARCH=x86_64 ;;
	aarch64 | arm64) ARCH=arm64 ;;
	*) echo "Arquitectura no soportada: $(uname -m)" >&2; exit 1 ;;
esac

# Solo se instala lo que falte: en un servidor compartido (webs, etc.) no se actualiza nada más.
MISSING=""
for tool in unzip curl; do
	command -v "$tool" >/dev/null || MISSING="$MISSING $tool"
done
if [ -n "$MISSING" ]; then
	echo "== Instalando:$MISSING"
	if command -v apt-get >/dev/null; then
		apt-get update -qq
		DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-upgrade $MISSING >/dev/null
	elif command -v dnf >/dev/null; then
		dnf install -y -q $MISSING
	fi
fi

echo "== Godot $GODOT_VERSION ($ARCH)"
mkdir -p "$DIR/server"
if [ ! -x "$DIR/godot" ] || ! "$DIR/godot" --version 2>/dev/null | grep -q "^$GODOT_VERSION"; then
	ZIP="Godot_v${GODOT_VERSION}-stable_linux.${ARCH}.zip"
	TMP="$(mktemp -d)"
	curl -fsSL -o "$TMP/godot.zip" "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/${ZIP}"
	unzip -q "$TMP/godot.zip" -d "$TMP"
	mv "$TMP"/Godot_v*_linux.* "$DIR/godot"
	chmod +x "$DIR/godot"
	rm -rf "$TMP"
fi

echo "== Archivos del servidor"
cp "$HERE"/relay_protocol.gd "$HERE"/relay_server.gd "$HERE"/relay_main.gd "$DIR/server/"
cat > "$DIR/project.godot" <<'EOF'
config_version=5

[application]

config/name="Servidor de salas"
EOF
id cazador >/dev/null 2>&1 || useradd --system --home "$DIR" --shell /usr/sbin/nologin cazador
chown -R cazador:cazador "$DIR"

echo "== Servicio"
cat > /etc/systemd/system/cazador-relay.service <<EOF
[Unit]
Description=Servidor de salas de ¿Cazador o Presa?
After=network-online.target
Wants=network-online.target

[Service]
User=cazador
WorkingDirectory=$DIR
Environment=HOME=$DIR
ExecStart=$DIR/godot --headless --path $DIR --script res://server/relay_main.gd -- --port=$PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable cazador-relay >/dev/null 2>&1
systemctl restart cazador-relay

# Cortafuegos del propio sistema, si está activo (el del proveedor se abre en su panel).
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
	ufw allow "$PORT"/udp >/dev/null
fi
if command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
	firewall-cmd --permanent --add-port="$PORT"/udp >/dev/null && firewall-cmd --reload >/dev/null
fi

sleep 2
if systemctl is-active --quiet cazador-relay; then
	IP="$(curl -fsS --max-time 5 https://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')"
	echo
	echo "Listo: servidor de salas en marcha en UDP $PORT."
	echo "IP pública: $IP"
	echo "Recuerda abrir UDP $PORT en el cortafuegos del proveedor (en AWS: Security Group / Lightsail > Networking)."
	echo "Registro: sudo journalctl -u cazador-relay -f"
else
	echo "El servicio no arrancó. Mira: sudo journalctl -u cazador-relay -n 50" >&2
	exit 1
fi
