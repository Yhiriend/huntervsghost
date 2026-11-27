#!/bin/sh
# Ejecuta todas las pruebas automáticas sin ventana. Uso: tests/run_all.sh [ruta a Godot]
# Sin argumento usa $GODOT o la ruta conocida de cada equipo (Mac o PC con Windows/Git Bash).
# Las pruebas usan user://_test_playtests.csv: nunca tocan tus partidas reales.
if [ -n "$1" ]; then
	GODOT="$1"
elif [ -z "$GODOT" ]; then
	case "$(uname -s)" in
		Darwin) GODOT="/Volumes/KINGSTON/godot/Godot.app/Contents/MacOS/Godot" ;;
		# En Windows se usa el ejecutable *_console.exe: el normal no escribe en la terminal.
		MINGW*|MSYS*|CYGWIN*) GODOT="/c/Users/DELL/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ;;
		*) GODOT="godot" ;;
	esac
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "No se encuentra Godot en: $GODOT"
	echo "Uso: tests/run_all.sh <ruta a Godot>   (o define la variable GODOT)"
	exit 1
fi
cd "$(dirname "$0")/.." || exit 1
"$GODOT" --headless --path . --import >/dev/null 2>&1
total=0
for scene in tests/test_*.tscn; do
	# Límite de 150 s por prueba: un error de sintaxis deja Godot colgado. macOS no trae
	# "timeout", así que allí se usa perl; en Git Bash perl no mataría el .exe de Windows.
	# Las pruebas de red (test_red*) van en tiempo real: con --fixed-fps los frames no esperan
	# al reloj y las conexiones no llegan a tiempo.
	case "$scene" in *test_red*) fps="" ;; *) fps="--fixed-fps 60" ;; esac
	if command -v timeout >/dev/null 2>&1; then
		out=$(timeout 150 "$GODOT" --headless $fps --path . "res://$scene" 2>&1)
	else
		out=$(perl -e 'alarm shift; exec @ARGV' 150 "$GODOT" --headless $fps --path . "res://$scene" 2>&1)
	fi
	echo "$out" | grep -E "^FAIL|SCRIPT ERROR|Parse Error|TIMEOUT"
	result=$(echo "$out" | grep "RESULT" | tail -1)
	echo "== $(basename "$scene" .tscn): ${result:-SIN RESULTADO}"
	case "$result" in *"failures=0"*) ;; *) total=$((total + 1)) ;; esac
done
[ "$total" -eq 0 ] && echo "TODO OK" || echo "PRUEBAS CON FALLOS: $total"
exit "$total"
