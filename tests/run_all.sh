#!/bin/sh
# Ejecuta todas las pruebas automáticas sin ventana. Uso: tests/run_all.sh [ruta a Godot]
# Las pruebas usan user://_test_playtests.csv: nunca tocan tus partidas reales.
GODOT="${1:-/Volumes/KINGSTON/godot/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." || exit 1
"$GODOT" --headless --path . --import >/dev/null 2>&1
total=0
for scene in tests/test_*.tscn; do
	# Límite de 120 s por prueba (macOS no trae "timeout"): un error de sintaxis deja Godot colgado.
	out=$(perl -e 'alarm shift; exec @ARGV' 120 "$GODOT" --headless --fixed-fps 60 --path . "res://$scene" 2>&1)
	echo "$out" | grep -E "^FAIL|SCRIPT ERROR|Parse Error|TIMEOUT"
	result=$(echo "$out" | grep "RESULT" | tail -1)
	echo "== $(basename "$scene" .tscn): ${result:-SIN RESULTADO}"
	case "$result" in *"failures=0"*) ;; *) total=$((total + 1)) ;; esac
done
[ "$total" -eq 0 ] && echo "TODO OK" || echo "PRUEBAS CON FALLOS: $total"
exit "$total"
