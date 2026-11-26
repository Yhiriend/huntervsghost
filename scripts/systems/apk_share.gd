class_name ApkShare
## Comparte el propio APK instalado (por WhatsApp si está, si no con el menú de compartir de Android).
## Sin plugins: usa JavaClassWrapper y el FileProvider que ya trae la plantilla de Godot
## (autoridad "<paquete>.fileprovider", con la carpeta de archivos de la app expuesta).

const WHATSAPP_PACKAGES := ["com.whatsapp", "com.whatsapp.w4b"]
const FILE_NAME := "cazador-o-presa.apk"
const MESSAGE := "¡Juega conmigo a ¿Cazador o Presa?! Instala este APK (Android te pedirá permitir apps de origen desconocido)."


static func is_available() -> bool:
	return OS.has_feature("android") and Engine.has_singleton("AndroidRuntime")


## Devuelve "" si se abrió WhatsApp (o el menú de compartir), o el motivo del fallo.
static func share() -> String:
	if not is_available():
		return "Compartir el APK solo funciona en Android."
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	if activity == null:
		return "No se pudo acceder a Android."

	# Copia el APK instalado a la carpeta de archivos de la app, que el FileProvider sí puede servir.
	var source: String = activity.getPackageCodePath()
	var File := JavaClassWrapper.wrap("java.io.File")
	var folder = File.File(activity.getFilesDir(), "compartir")
	folder.mkdirs()
	var file = File.File(folder, FILE_NAME)
	var source_file = File.File(source)
	if not file.exists() or file.length() != source_file.length():
		# Godot no puede abrir rutas fuera de su carpeta: la copia la hace Java.
		var out = JavaClassWrapper.wrap("java.io.FileOutputStream").FileOutputStream(file)
		JavaClassWrapper.wrap("java.nio.file.Files").copy(source_file.toPath(), out)
		out.close()
		var copy_error = JavaClassWrapper.get_exception()
		if copy_error != null or file.length() != source_file.length():
			file.delete()
			return "No se pudo preparar el APK%s." % ("" if copy_error == null else ": " + copy_error.toString())

	var FileProvider := JavaClassWrapper.wrap("androidx.core.content.FileProvider")
	var uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".fileprovider", file)
	if uri == null:
		return "No se pudo preparar el enlace al APK."

	var Intent := JavaClassWrapper.wrap("android.content.Intent")
	var intent = Intent.Intent("android.intent.action.SEND")
	intent.setType("application/vnd.android.package-archive")
	intent.putExtra("android.intent.extra.STREAM", uri)
	intent.putExtra("android.intent.extra.TEXT", MESSAGE)
	intent.addFlags(1)  # FLAG_GRANT_READ_URI_PERMISSION

	# Sin <queries> en el manifiesto no se puede preguntar si WhatsApp está instalado (Android 11+),
	# así que se intenta abrirlo directamente y, si falla, se muestra el menú de compartir.
	for package in WHATSAPP_PACKAGES:
		intent.setPackage(package)
		activity.startActivity(intent)
		if JavaClassWrapper.get_exception() == null:
			return ""
	intent.setPackage(null)
	activity.startActivity(Intent.createChooser(intent, "Compartir ¿Cazador o Presa?"))
	var exception = JavaClassWrapper.get_exception()
	if exception != null:
		return "No se pudo compartir: %s" % exception.toString()
	return ""
