# Scale

App para tablet (Flutter, Android) que escucha un piano por MIDI y anota canciones: detecta los acordes y la tonalidad en vivo, guarda la secuencia y ayuda a tocarlas después. Pensada para músicos de alabanza.

## Qué hace

- **En vivo**: acorde actual, seguridad y alternativas; tonalidad con su relativa, enarmónica y modulaciones; grados Nashville.
- **Grabar**: guarda la toma MIDI cruda y la convierte en una canción. Las partes se proponen solas ("Parte 1, 2…") por pausas, repeticiones seguidas (×N) y frases de igual duración; luego se editan a mano.
- **Canciones**: partitura por secciones o lineal, corrección de acordes, tiempos anotados (D′ B′′), notación americana o latina. La lista **para tocar** se ordena (recientes, título, tonalidad o a mano) y se reorganiza arrastrando; el **archivo** guarda todas, también las que no se van a tocar. Cada canción muestra su tonalidad original y en qué suena con el transporte guardado.
- **Editor**: cada sección se edita como una vuelta (×N). Los acordes se arrastran para moverlos de lugar o entre secciones; una paleta trae los de la tonalidad, los de la canción y el último tocado en el piano. Una sección se escribe como texto (`G D/F# Em7'' C x2`), se toca en el piano para que se escriba sola o se regraba. "Probar" sigue lo que tocas en el mismo editor y, si algo no coincide, se corrige con un toque. Todo se puede deshacer.
- **Transporte**: simulador ("de D a F: +3 o −9") y capa de transpose digital para tocar con las figuras originales mientras el piano suena en otra tonalidad.
- **Tocar**: reproduce la toma original por el piano o sigue en vivo lo que tocas, con las vueltas y los saltos entre partes. Abajo, la canción anterior y la siguiente de la lista para tocar. Las notas de cada sección ("entrar suave", "subir intensidad") aparecen al llegar a ella.
- **Importar con IA**: desde capturas de páginas de acordes, fotos de partituras a mano o texto pegado, con un chat al lado para corregir antes de guardar. Usa la API de Claude con tu propia clave, que se guarda solo en la tablet (⚙).
- **Cantante**: escucha por el micrófono de la tablet (no por el audio USB del teclado), muestra la nota y la afinación, y un gráfico en tiempo real con la línea de la voz sobre el espectrograma (eje en notas, escala resaltada). Estima en qué tonalidad y escala canta y dice cuánto transportar una canción para su voz.
- **Herramientas**: rueda de quintas con piezas que se giran (mayor y sus modos, menor armónica, pentatónica): muestra la escala, sus acordes por grado y transporta progresiones escritas en grados (`I V vi IV`). Tabla de grados de las 12 tonalidades (mayores, menor natural y armónica, con o sin séptimas). Los acordes suenan en el piano al tocarlos.

## Estructura

| Carpeta | Contenido |
|---|---|
| `packages/scale_core` | Núcleo en Dart puro: teoría, reconocimiento de acordes, estimación de tonalidad, detección de partes, seguidor, modelo de canción (`scale.song` v1). Con tests. |
| `app` | App Flutter: MIDI (`flutter_midi_command`), pantallas y almacenamiento local en JSON. |

## Desarrollo

```bash
# Núcleo
cd packages/scale_core && dart pub get && dart test

# App (con una tablet Android conectada)
cd app && flutter pub get && flutter run
```
