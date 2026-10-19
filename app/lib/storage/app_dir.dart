import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Carpeta donde la app guarda canciones y configuración.
///
/// En la tablet es la de documentos de la app (privada). En escritorio esa
/// sería la carpeta "Documentos" del usuario, así que se usa la de datos de
/// la aplicación.
Future<Directory> appDataDirectory() =>
    Platform.isAndroid || Platform.isIOS ? getApplicationDocumentsDirectory() : getApplicationSupportDirectory();
