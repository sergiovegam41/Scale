import 'package:flutter/widgets.dart';

/// Tamaños de pantalla. La app nació para tablet en horizontal; en pantallas
/// angostas (teléfono) o bajas (teléfono acostado) las pantallas apilan sus
/// paneles en vez de ponerlos lado a lado.
extension Responsive on BuildContext {
  Size get screen => MediaQuery.sizeOf(this);

  /// Teléfono o ventana pequeña: menos de 700 de ancho o 500 de alto.
  bool get isCompact => screen.width < 700 || screen.height < 500;
}
