# Scale

App para tablet (Flutter, Android) que escucha un piano por MIDI y anota canciones: detecta los acordes y la tonalidad en vivo, guarda la secuencia y ayuda a tocarlas después. Pensada para músicos de alabanza.

## Qué hace

- **En vivo**: acorde actual, seguridad y alternativas; tonalidad con su relativa, enarmónica y modulaciones; grados Nashville.
- **Grabar**: guarda la toma MIDI cruda y la convierte en una canción. Las partes se proponen solas ("Parte 1, 2…") por pausas, repeticiones seguidas (×N) y frases de igual duración; luego se editan a mano.
- **Canciones**: partitura por secciones o lineal, corrección de acordes, tiempos anotados (D′ B′′), notación americana o latina.
- **Transporte**: simulador ("de D a F: +3 o −9") y capa de transpose digital para tocar con las figuras originales mientras el piano suena en otra tonalidad.
- **Tocar**: reproduce la toma original por el piano o sigue en vivo lo que tocas, con las vueltas y los saltos entre partes.

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
