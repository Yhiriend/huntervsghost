class_name LowLatencyWifi
## En Android, pide al sistema el modo Wi-Fi de baja latencia mientras el juego está abierto.
## Sin esto el móvil pone la Wi-Fi en ahorro de energía y retiene los paquetes entrantes
## (a menudo 50-200 ms más de ping). Android solo lo aplica con la app en primer plano y la
## pantalla encendida, así que no gasta batería en segundo plano. Necesita el permiso WAKE_LOCK.

const MODE_FULL_HIGH_PERF := 3  # Android < 10
const MODE_FULL_LOW_LATENCY := 4  # Android 10+

static var _lock = null


## Devuelve "" si se activó, o el motivo.
static func acquire() -> String:
	if _lock != null:
		return ""
	if not OS.has_feature("android") or not Engine.has_singleton("AndroidRuntime"):
		return "Solo en Android."
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	if activity == null:
		return "No se pudo acceder a Android."
	var wifi = activity.getApplicationContext().getSystemService("wifi")
	if wifi == null:
		return "Sin Wi-Fi."
	for mode in [MODE_FULL_LOW_LATENCY, MODE_FULL_HIGH_PERF]:
		var lock = wifi.createWifiLock(mode, "cazador-o-presa")
		if JavaClassWrapper.get_exception() != null or lock == null:
			continue
		lock.setReferenceCounted(false)
		lock.acquire()
		if JavaClassWrapper.get_exception() == null:
			_lock = lock
			return ""
	return "Android no permitió el modo de baja latencia."


static func is_active() -> bool:
	return _lock != null
