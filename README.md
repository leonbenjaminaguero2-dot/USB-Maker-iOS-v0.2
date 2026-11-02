# BootMaker v0.2 — iOS (Swift + UIKit)

Prototipo funcional nativo de BootMaker: interfaz Android oscura/violeta inspirada en el video de Vendroid, **sin SwiftUI, HTML ni Ventoy**. Flujo: **USB → ISO → Crear**.

## Qué funciona realmente

- El usuario elige una carpeta en Archivos (intención: raíz de una memoria USB). Antes de continuar, BootMaker comprueba formato FAT, permisos de escritura, espacio mínimo y que la carpeta esté vacía. No puede identificar con certeza si es la raíz de un USB físico.
- El usuario elige una **ISO real** con el selector de Archivos.
- El lector Swift `ISO9660Reader.swift` inspecciona las estructuras ISO 9660/Joliet y busca `EFI/BOOT/BOOTX64.EFI` o `EFI/BOOT/BOOTAA64.EFI`, validando cabecera PE/COFF, arquitectura correcta y subsistema EFI (no solo `MZ`).
- `UEFICreationService.swift` extrae **los archivos reales de la ISO**, no solo copia el archivo `.iso`. Exige que el destino esté vacío y se presente como FAT/FAT32, verifica espacio cuando está disponible y muestra progreso/velocidad/tiempo restante calculados desde los bytes procesados. **Lee de vuelta y compara cada byte escrito con la ISO**; solo entonces informa que los archivos se verificaron.
- Los fallos se muestran como fallos y la tarea intenta eliminar únicamente los archivos que creó. Incluye cancelación y confirmación.
- `UIDocumentPicker` ahora conserva de forma fiable el tipo de selección (USB o ISO) mediante estado interno, sin depender de identificadores de accesibilidad del controlador.
- El workflow ejecuta 5 pruebas del lector antes de compilar la IPA.

## Límites fundamentales (leer antes de usar)

**NO es una alternativa completa a Rufus/Etcher/Vendroid**. iOS normal no permite a una IPA de terceros reformatear, particionar ni escribir sectores crudos a un pendrive por una API pública. Este proyecto **NO formatea el USB automáticamente**. Apple permite el formateo desde Archivos en modelos de iPhone USB-C, pero **el iPhone 13 Pro con Lightning no dispone de esa función**.

La creación UEFI por extracción puede ser válida **solo para determinadas ISO que ofrecen una estructura UEFI de archivos independiente** y para unidades que ya están en **FAT32 con partición adecuada**. La presencia de `BOOTX64.EFI` no garantiza que el sistema arranque, porque algunos cargadores dependen de una estructura propia de ISO/El Torito, rutas adicionales, una tabla de particiones específica o parámetros propios. **El arranque final debe comprobarse en una PC**.

No se soportan ISO UDF sin árbol ISO9660 completo, archivos mayores de 4 GiB en FAT32 (`install.wim` de Windows incluido), imágenes `.img`, multiextent, BIOS/Legacy, ISOs híbridas que requieran escritura cruda, ni extracción de Rock Ridge específico. Tampoco se detecta con fiabilidad si el usuario eligió *la raíz de un USB físico* en lugar de una carpeta local: esa elección es responsabilidad del usuario. **No se debe anunciar un éxito de booteo confirmado.**

**Advertencia de datos:** esta app se niega a sobrescribir una carpeta de destino que no esté vacía y no ejecuta formateos. Si el usuario formatea el USB previamente mediante otro sistema, se borrarán sus datos.

## Compilar la IPA

1. Creá un repositorio de GitHub con todo el contenido de esta carpeta (incluida `.github`).
2. En GitHub → **Actions** → **BootMaker - IPA sin firma** → **Run workflow**.
3. Al terminar, descargá el artifact `BootMaker-unsigned-IPA` con `BootMaker-unsigned.ipa`.
4. La IPA **no está firmada**: para instalarla necesitarás firmarla por el método compatible con tu dispositivo (ej. SideStore). Una IPA compilada no altera los permisos USB de iOS.

En un Mac, también podés instalar `xcodegen` y ejecutar:

```sh
brew install xcodegen
xcodegen generate --spec project.yml
xcodebuild -project BootMaker.xcodeproj -scheme BootMaker -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Pruebas locales (lector ISO, Linux/macOS)

```sh
bash Tests/test_reader.sh
```

Las pruebas usan un cargador EFI **sintético**, no una ISO booteable real. Verifican un archivo aceptado y 4 variantes deliberadamente corruptas o incompatibles; no certifican el arranque real de un USB.

## Estado de validación

Se ejecutaron 5 pruebas del parser ISO9660 con Swift Linux y se revisó la sintaxis Swift de todos los archivos. Se validó la tipificación de `ISO9660Reader` y `UEFICreationService` en Swift Linux mediante un shim de seguridad (no equivale a una prueba en iOS). **No se ejecutó Xcode ni se compiló una IPA real en este entorno**; el workflow generará la IPA en un corredor macOS de GitHub Actions. La verificación de escritura en USB real y arranque en PC continúa pendiente.

## Cambios de v0.2 y funciones que NO se solucionaron

- Corregido: un archivo PE normal ya no se acepta como cargador EFI sin verificar arquitectura y subsistema.
- Corregido: el picker de USB/ISO no depende de `accessibilityIdentifier`.
- Añadido: verificación byte a byte tras escritura, con etapa y porcentaje propios.
- Añadido: verificación anticipada del destino FAT y permisos reales de escritura, antes de poder pasar a ISO.
- Añadido: pruebas automáticas positivas y negativas antes del build.
- **No disponible:** enumeración automática de pendrives sin interacción del usuario. `FileManager.mountedVolumeURLs` devuelve `nil` fuera de macOS. iOS necesita elegir el volumen a través de Archivos.
- **No disponible:** formateo/particionado del pendrive desde una IPA convencional sin acceso a bloques USB.
- **No garantizado:** que una ISO de Windows/Linux arranque, incluso tras una copia verificada. Las ISO UDF, las particiones especiales, los archivos mayores de 4 GiB y las configuraciones de arranque específicas requieren otro motor.

Estos puntos son limitaciones de la plataforma y del formato del sistema, **no errores que se solucionen renombrando la IPA**.
