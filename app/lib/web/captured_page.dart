/// Texto de una página web abierta en el navegador de la app, para
/// importarla con la IA.
class CapturedPage {
  const CapturedPage({required this.url, required this.title, required this.text});

  final Uri url;
  final String title;
  final String text;

  /// Mensaje para la IA: de dónde viene y el texto.
  String get prompt =>
      'Esta es una página web abierta por el usuario: "$title" ($url).\n'
      'El texto puede traer menús, anuncios, comentarios u otras canciones: ignóralos y '
      'toma solo la canción principal (acordes, secciones y letra) tal como está en la página.\n\n'
      '$text';

  /// Cómo se muestra en el chat.
  String get label => 'Página: $title\n${url.host}';
}
