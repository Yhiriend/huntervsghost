# Keystore de depuración (solo pruebas)

`debug.keystore` firma los APK de prueba. Está en el repo para que todos los ordenadores firmen con la misma clave: así un APK exportado en cualquiera de ellos se instala encima del anterior, sin desinstalar ni perder datos.

`export_presets.cfg` ya apunta a ella (`keystore/debug`). Sus datos:

| Dato | Valor |
|---|---|
| Alias | `androiddebugkey` |
| Contraseña | `android` |
| Huella SHA-256 | `F2:2D:AC:C3:96:4C:FC:D8:53:50:6C:EB:BB:4F:39:39:E0:75:F2:C6:CF:43:50:EB:0F:92:FC:8C:FB:AD:D4:9F` |

Es una clave pública de pruebas: **no la uses para publicar.** Para Google Play hace falta una keystore de release propia, que nunca debe subirse al repo.
