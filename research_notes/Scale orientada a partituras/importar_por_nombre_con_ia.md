# Importar una canción por nombre con IA ("Astral Observatory", Zelda: Majora's Mask) — fuentes, herramientas, fiabilidad y legalidad (estado a nov. 2026)

> Notas de investigación. No es asesoría legal. No se descargó ningún archivo con derechos de autor; la existencia y el formato se comprobaron solo con páginas de listado o índices de buscador.
> Hallazgo transversal: **ninsheetmusic.org, musescore.com, musescore.org y zeldadungeon.net respondieron HTTP 403 a un fetcher automatizado** (WebFetch) en esta sesión. VGMusic.com sí respondió. Esto afecta directamente el diseño (ver pregunta b).

## (a) ¿Dónde existen legítimamente partituras/MIDI de "Astral Observatory" y en qué formatos?

### Takeaway
"Astral Observatory" **sí existe** como MIDI gratuito en VGMusic.com (3 versiones) y como arreglo para piano en NinSheetMusic (por "The Deku Trombonist"; el sitio ofrece PDF + MIDI + MUS por arreglo). No encontré un arreglo publicado con licencia (Musicnotes, Hal Leonard, Alfred) ni uno verificable en MuseScore.com. MuseScore entrega MusicXML/MIDI, pero solo a cuentas PRO (salvo dominio público u obras "Original") y con límite de 20 descargas al día.

### Cited Findings
**La pieza**
- "Astral Observatory" es un tema de Majora's Mask atribuido a Koji Kondo y Toru Minegishi. Dura 1:24 en la banda sonora original y suena en el Observatorio Astral tras pasar por el escondite de los Bombers (índice de búsqueda; la página de la wiki devolvió 403 al fetch directo) — [Zelda Dungeon Wiki](https://zeldadungeon.net/wiki/Astral_Observatory_(Theme))
- El nombre japonés es probablemente "Tentai Kansoku" (天体観測). Ojo: el resultado de búsqueda "free sheet tentai kansoku" parece ser la canción homónima de BUMP OF CHICKEN, no la de Zelda. Es un riesgo de ambigüedad en la búsqueda — [pianojuku.info](https://pianojuku.info/en/free-sheet-tentai-kansoku)
- Las pistas de Majora's Mask se añadieron a la app Nintendo Music en octubre de 2026 (titular de un resultado de búsqueda; no se abrió el artículo) — [Nintendo Wire](https://nintendowire.com/news/2026/10/05/majoras-mask-tracks-set-to-be-added-to-nintendo-music-on-october-8th-2026/)

**VGMusic.com (archivo de MIDI de videojuegos)**
- El listado de N64 incluye en "Legend of Zelda, The: Majora's Mask" unos 130 MIDI, entre ellos:
  - "Astral Observatory": `ZMM-Astral%28v1.1%29.mid`, 7.412 bytes, de John Harvey
  - "Astral Observatory (2)": `32_Astronomical_Observatory_GM.mid`, 9.989 bytes, de Jarel Jones
  - "Astral Observatory (XG)": `32_Astronomical_Observatory_XG.mid`, 10.228 bytes, de Jarel Jones

  — [VGMusic N64](https://www.vgmusic.com/music/console/nintendo/n64/)
- El encabezado dice que el directorio de N64 está completo al 23-sep-2023. La página es HTML estático y se puede leer con un fetcher. En la parte leída no vi términos de uso — [VGMusic N64](https://www.vgmusic.com/music/console/nintendo/n64/)

**NinSheetMusic.org**
- El índice del buscador muestra PDFs de Majora's Mask bajo `ninsheetmusic.org/download/pdf/{id}`, con "Astral Observatory" arreglado por "The Deku Trombonist". En el mismo grupo aparecen Title Screen, Goron Race, Rosa Sisters y Termina Field (Deku Trombonist), Oath to Order (G-Han), Bremen March y New Wave Bossa Nova (Tangy), Ikana Canyon (Beethoven II) y Guru Guru (Dekudude). El índice no permite asociar con certeza cada ID con su título — [búsqueda site:ninsheetmusic.org, p. ej. download/pdf/2141](https://www.ninsheetmusic.org/download/pdf/2141)
- Por cada arreglo el sitio ofrece **.pdf, .mid y .mus** (Finale). Ejemplo: Breath of the Wild con 75 hojas — [NinSheetMusic Zelda series](https://ninsheetmusic.org/browse/series/TheLegendofZelda)
- Gigazine (2020) lo describe como un sitio gratuito con más de 4.000 partituras y MIDI de juegos de Nintendo — [Gigazine](https://gigazine.net/gsc_news/en/20200604-game-sheet-music-ninsheetmusic)
- El servidor respondió 403 a las peticiones automatizadas (WebFetch) en www y en el dominio sin www — prueba directa en esta sesión (sin URL citable más allá de [la página de la serie](https://ninsheetmusic.org/browse/series/TheLegendofZelda))

**MuseScore.com**
- Reglas de descarga (actualizadas el 28-abr-2025): **límite de 20 descargas al día** por usuario. Las cuentas Basic solo bajan obras de dominio público y las marcadas "Original". PRO baja todo excepto las "Official scores". Las partituras oficiales HQ **no se pueden descargar ni imprimir**, solo ver, reproducir y usar en Practise. Formatos: **MSCZ, PDF, PDF con partes, MusicXML, MIDI, MP3** — [MuseScore Help Center](https://intercom.help/musescore/en/articles/8535931)
- La búsqueda de "astral observatory" en musescore.com devolvió 403 al fetch automatizado, así que no pude confirmar si hay arreglos de esta pieza — prueba directa ([URL de búsqueda](https://musescore.com/sheetmusic?text=astral%20observatory))
- Según un comentario de usuario en el foro (no oficial), existió una API de musescore.com que se retiró tras usarse para saltarse restricciones de copyright — [musescore.org foro](https://musescore.org/en/node/373269)

**Tiendas con licencia y publicaciones oficiales**
- Musicnotes tiene una página de artista "Legend of Zelda: Majora's Mask, The" con arreglos sueltos, p. ej. "Prelude of Majora's Mask" y "Termina Field" para piano. Las páginas de listado redirigieron (302) y no pude verificar el catálogo completo ni si incluye "Astral Observatory" — [Musicnotes MM](https://www.musicnotes.com/SheetMusic/index/Artists/LegendofZeldaMajorasMaskThe/default.asp); [Prelude MN0109500](https://origin-www.musicnotes.com/sheetmusic/MN0109500/92617)
- "The Legend of Zelda Series for Piano" (Alfred, 2011) incluye "Termina Field" de MM. La versión Easy Piano cita "Majora's Mask – Prelude" — [Zelda Wiki](https://zeldawiki.wiki/wiki/The_Legend_of_Zelda_Series_for_Piano); [Sheet Music Plus](https://www.sheetmusicplus.com/en/product/the-legend-of-zelda-series-for-piano-19724793.html); [Easy Piano](https://zeldawiki.wiki/wiki/The_Legend_of_Zelda_Series_for_Easy_Piano)
- "The Legend of Zelda: Best Collection" es un libro de piano de 192 páginas que cubre Zelda 1, ALttP, OoT, MM y WW (contenido no verificado pieza a pieza) — [Zelda Wiki](https://zeldawiki.wiki/wiki/The_Legend_of_Zelda:_Best_Collection)
- PaidTabs lista transcripciones de "Astral Observatory" **para guitarra**, por encargo y de pago: Sam Griffin Guitar por unos 10 USD y John Oeth (guitarra clásica) por unos 15 USD. No son para piano — [PaidTabs](https://paidtabs.com/search/astral_observatory_chords_tabs_sheet_music); [PaidTabs Oeth](https://paidtabs.com/search/astral_observatory_oeth_chords_tabs_sheet_music)
- OverClocked ReMix tiene una ficha de canción "Astral Observatory" (remixes de audio, no partituras) — [OCReMix](https://ocremix.org/song/13220)

### Inferences
- Para esta pieza concreta, las **fuentes reales y gratuitas son VGMusic (MIDI) y NinSheetMusic (PDF/MIDI/MUS)**. Ninguna ofrece MusicXML. Así que Scale tendría que importar **MIDI** y cuantizarlo/convertirlo a su modelo interno, u OMR desde PDF, que es mucho menos fiable.
- Los MIDI de VGMusic son *secuencias* fan-made (orientadas a reproducir el sonido del juego, a menudo multipista y con canales GM/XG), no partituras de piano. Para "aprender a tocar" conviene más el MIDI de NinSheetMusic (arreglo de piano a dos manos), si el usuario lo descarga.
- Las tiendas con licencia no parecen tener "Astral Observatory". El "camino oficial" para esta pieza es inexistente o no verificado.
- IMSLP y Mutopia/OpenScore no aplican: solo publican dominio público o licencias libres, y la música de Nintendo de 2000 no lo es (no verificado en esta sesión; ver Gaps).

### Gaps
- No pude abrir ninsheetmusic.org (403) para confirmar la ficha exacta de "Astral Observatory" (ID, fecha, formatos de esa hoja concreta), ni sus términos de uso o FAQ.
- No verifiqué si NinSheetMusic ofrece hoy MusicXML (solo vi pdf/mid/mus).
- No pude confirmar si hay arreglos de "Astral Observatory" en MuseScore.com (403).
- No revisé flat.io, Sheet Music Boss, IMSLP, Mutopia ni OpenScore en esta sesión (tope de llamadas). Que IMSLP sea solo de dominio público es conocimiento previo, no lo verifiqué aquí.
- No verifiqué precios ni formatos de Musicnotes (redirección 302). Por conocimiento previo Musicnotes entrega PDF y un visor propio, no MusicXML ni MIDI en general, pero no está verificado.

## (b) ¿Cómo encuentra y obtiene el archivo un agente LLM (herramientas, APIs)?

### Takeaway
La API de Claude ofrece `web_search` (10 USD por cada 1.000 búsquedas más tokens) y `web_fetch` (sin recargo, solo tokens). Pero **web_fetch solo acepta texto, HTML y PDF: un .mid o un .mxl devuelve `unsupported_content_type`**. Además respeta robots.txt, no ejecuta JavaScript y solo abre URLs que ya aparecieron en la conversación. La arquitectura viable es: Claude busca y propone candidatos (URLs de páginas de ficha), **el usuario confirma y la app descarga el archivo ella misma** (o el usuario lo descarga en su navegador y lo importa).

### Cited Findings
- Versiones de web search: `web_search_20250305` (básica), `web_search_20260209` (filtrado dinámico) y `web_search_20260318` (añade `response_inclusion`). Precio: **10 USD por 1.000 búsquedas** más los tokens de los resultados. Las búsquedas fallidas no se cobran — [Anthropic docs: web search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)
- Parámetros de web search: `max_uses`, `allowed_domains` o `blocked_domains` (no ambos a la vez; si se mandan los dos da error 400) y `user_location` (país ISO, zona horaria). Las citas están siempre activas. Al continuar la conversación hay que reenviar `encrypted_content` sin modificar — [Anthropic docs: web search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)
- En `web_search_20260209+`, `allowed_callers` vale por defecto `["code_execution_20260120"]` (filtrado dinámico). Para llamar la herramienta directamente hay que poner `["direct"]` — [Anthropic docs: web search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)
- Versiones de web fetch: `web_fetch_20250910` (básica), `_20260209` (filtrado dinámico), `_20260309` (añade `use_cache:false`) y `_20260318` (añade `response_inclusion`). **No tiene recargo**, solo se pagan tokens (página media de 10 kB ≈ 2.500 tokens; PDF de 500 kB ≈ 125.000 tokens) — [Anthropic docs: web fetch](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool)
- **Tipos de contenido:** error `unsupported_content_type` con la descripción "only text, HTML, and PDF". Los PDF llegan en base64 y se procesan como un PDF adjunto — [Anthropic docs: web fetch](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool)
- **No soporta sitios renderizados con JavaScript.** La documentación sugiere la herramienta browser-use (del lado del cliente) para esos casos — [Anthropic docs: web fetch](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool)
- **Validación de URL:** Claude solo puede abrir URLs que ya aparecieron en mensajes del usuario, en resultados de herramientas cliente o en resultados previos de search/fetch, nunca URLs que haya inventado. El error es `url_not_in_prior_context`. `url_not_allowed` cubre los filtros de dominio y las restricciones de Anthropic, entre ellas **robots.txt**. `url_not_accessible` corresponde a errores HTTP. El límite de URL es de 250 caracteres — [Anthropic docs: web fetch](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool)
- Otros parámetros de web fetch: `max_uses`, `allowed_domains`/`blocked_domains`, `url_sources`, `citations` (desactivado por defecto) y `max_content_tokens`, que no se aplica a los PDF. El administrador de la organización puede desactivar search/fetch o restringir dominios en la Console; si están desactivados, la llamada da error 400 — [Anthropic docs: web fetch](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool)
- Advertencia oficial: existe riesgo de exfiltración de datos si se mezcla entrada no confiable con datos sensibles. Se recomienda `allowed_domains` y `max_uses` — [Anthropic docs: web fetch](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool)
- Al usar search y fetch juntos, Claude busca, elige resultados, los abre y responde con citas — [Anthropic docs: web fetch](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool)
- Las herramientas de scraping de terceros para MuseScore (Apify "musescore-scraper", paquetes PyPI) son productos no oficiales — [Apify](https://apify.com/maximedupre/musescore-scraper/api/python); [PyPI musescore-scraper](https://pypi.org/project/musescore-scraper/2.2.1)

### Inferences
- Flujo recomendado para Scale: (1) prompt con `web_search`, `allowed_domains` = [vgmusic.com, ninsheetmusic.org, musescore.com, musicnotes.com, …] y `max_uses` de unos 3 → (2) Claude devuelve en JSON estructurado una lista de candidatos (título, arreglista, sitio, URL de la ficha, formatos, licencia o gratuidad) → (3) la UI los muestra y **el usuario elige** → (4) la app descarga con el cliente HTTP de Flutter, **solo si el sitio lo permite** (VGMusic sirve .mid estáticos). Si no, abre la ficha en el navegador del sistema para que el usuario descargue y luego importe el archivo (intent "Abrir con" o selector de archivos) → (5) la app valida y convierte.
- Como web_fetch no lee .mid, Claude **nunca "ve" las notas** del archivo. El análisis musical lo tiene que hacer la app localmente (parser MIDI en Dart) y, si se quiere, pasar a Claude un resumen textual (tonalidad estimada, compases, rango) para revisarlo.
- Costo por importación: 1 a 3 búsquedas (≈0,01–0,03 USD) más algunos miles de tokens. Es despreciable frente al riesgo de errores.
- Los 403 en NinSheetMusic y MuseScore indican protección anti-bot o Cloudflare. Una descarga automatizada desde la app probablemente también fallaría o violaría la voluntad del sitio. Para esos sitios conviene "abrir en navegador" y no descargar en segundo plano.

### Gaps
- No verifiqué el robots.txt de vgmusic.com ni el de ninsheetmusic.org.
- No verifiqué si web_search devuelve buenos resultados de ninsheetmusic para esta pieza vía API (en esta sesión el buscador sí indexó los PDFs).

## (c) ¿Por qué el LLM no debe "escribir la partitura de memoria"?

### Takeaway
No encontré ningún estudio que mida directamente la exactitud con que los LLM generalistas reproducen melodías conocidas de memoria. La evidencia disponible es indirecta: los modelos de música simbólica se evalúan por "musicalidad" o preferencia, no por fidelidad nota a nota, y la memorización de material poco repetido es mala. Para una pieza de nicho como "Astral Observatory" una transcripción "de memoria" no es verificable y sería, en el mejor caso, una aproximación plausible. Se necesita recuperar un archivo real y validarlo.

### Cited Findings
- ChatMusician (LLaMA2 entrenado en notación ABC) se evalúa en comprensión (MusicTheoryBench) y en generación por evaluación humana y métricas. Su ventaja frente a GPT-4 se mide en musicalidad y estructura, no en recuerdo exacto de obras existentes — [arXiv 2402.16153](https://arxiv.org/pdf/2402.16153)
- MuPT reporta que los oyentes prefirieron su música el 79 % de las veces frente a GPT-4. Es una medida de preferencia, no de fidelidad — [MuPT](https://irep.mbzuai.ac.ae/items/d1c3391c-a91f-4236-8395-2da8cd7635ce)
- SongComposer incluye un análisis de memorización (pide melodías de entrenamiento y compara con el original). Los fragmentos leídos no dan cifras — [arXiv 2402.17645](https://arxiv.org/html/2402.17645v2)
- Recuerdo en LLM: con 2 exposiciones, los mejores modelos recuerdan muy bien oraciones naturales, pero quedan cerca del azar con otros tipos de estímulos — [arXiv 2303.17557](https://arxiv.org/pdf/2303.17557)
- LLM y razonamiento armónico: se evalúan en tareas como deducir notas a partir de intervalos o identificar acordes y escalas, con variantes enharmónicas y notas barajadas (capacidad de teoría, no de memoria de obras) — [arXiv 2409.05521](https://arxiv.org/html/2409.05521v1)

### Inferences
- "Astral Observatory" es una pieza de 1:24 de un juego del año 2000, con poca presencia textual (ABC/MusicXML) en la web. Es improbable que esté memorizada nota a nota, y el modelo puede producir una melodía "al estilo de" con total confianza. Para un alumno, aprender notas equivocadas es peor que no tener partitura.
- Además, una reproducción "de memoria" de una obra protegida sería igualmente una copia o derivado con copyright. Generarla no resuelve el tema legal.
- Validación práctica del archivo encontrado, en la app:
  1. **Duración**: comparar con unos 1:24 de la OST, teniendo en cuenta repeticiones y loops.
  2. **Tonalidad y compás**: estimarlos localmente (Krumhansl-Schmuckler) y mostrarlos.
  3. **Preescucha** con el sintetizador de la app antes de guardar, para que el usuario confirme que "suena a" la pieza.
  4. **Estructura MIDI**: número de pistas y canales (descartar o mapear percusión, canal 10), rango de notas tocable en teclado, cuantización.
  5. **Metadatos de procedencia** guardados localmente: URL, arreglista, sitio, fecha y licencia o nota.
  6. Opcional: pedir a Claude un chequeo cruzado, enviándole solo un resumen textual del MIDI parseado, no el binario.

### Gaps
- No encontré una evaluación publicada de "recall de melodías conocidas" por GPT-4/Claude con tasas de error nota a nota. Sería la evidencia ideal, pero no la localicé.

## (d) Copyright y términos de servicio (uso personal y app que automatiza descargas)

### Takeaway
La música de Majora's Mask está protegida (Nintendo; compositores Koji Kondo y Toru Minegishi). Los arreglos de fans en NinSheetMusic, VGMusic o MuseScore son obras derivadas no licenciadas en general, toleradas pero no "libres". MuseScore restringe las descargas por niveles y ha perseguido herramientas que las saltan. Una app debe ser iniciada por el usuario, respetar robots.txt y los ToS, guardar solo en local, no redistribuir y preferir archivos aportados por el usuario o enlaces a fuentes con licencia. Las excepciones de "copia privada" en Latinoamérica varían por país y no suelen cubrir expresamente las partituras.

### Cited Findings
- Muse Group (MuseScore) no es en general titular de las partituras comerciales: es un intermediario con derechos de distribución. Las herramientas que saltan sus controles de acceso le generan costos no monetizados o incumplimientos de contratos con titulares (paráfrasis de Ars Technica). En 2021 se retiró de GitHub el repositorio "musescore-downloader", en un debate sobre la DMCA y la elusión de controles — [Michael Tsai blog, 2-ago-2021](https://mjtsai.com/blog/?p=33297)
- MuseScore: las "Official scores" no se pueden descargar ni imprimir "per copyright owners' requirements". PRO es necesario para descargar el resto, salvo dominio público u Original. Límite de 20 al día — [MuseScore Help Center](https://intercom.help/musescore/en/articles/8535931)
- La descarga de partituras pasó a formar parte de la suscripción Pro (cita recogida por Archive Team) — [Archive Team wiki](https://wiki.archiveteam.org/index.php/MuseScore)
- Ejemplo de cláusula habitual en sitios de partituras: Soundslice prohíbe el scraping y el rastreo automatizado en su AUP — [Soundslice AUP](https://soundslice.com/terms/aup)
- Perú: la ley autoriza copias "para uso exclusivamente personal" de obras publicadas **en grabaciones sonoras o audiovisuales**, y habla de copia "personal", no "privada", lo que limita su alcance — [Tesis PUCP](https://tesis.pucp.edu.pe/bitstreams/a18a08fb-30d0-4e1f-bc28-42a66f418266/download); [repositorio PUCP](https://repositorio.pucp.edu.pe/index/handle/123456789/143766)
- México: una tesis de la UNAM sostiene que la Ley Federal del Derecho de Autor *debería* regular la remuneración por copia privada siguiendo el modelo español (es decir, la regulación no es completa) — [Tesis UNAM](https://ru.dgb.unam.mx/bitstream/20.500.14330/TES01000636122/3/0636122_A1.pdf)
- Colombia: hay literatura académica sobre la excepción de copia privada en entorno analógico y digital (contenido normativo no extraído) — [Dialnet](https://dialnet.unirioja.es/descarga/articulo/5109708.pdf)
- La OMPI (2005) señala el interés en Latinoamérica por reconocer la remuneración por copia privada — [OMPI](https://www.wipo.org/edocs/mdocs/lac/es/ompi_da_mex_05/ompi_da_mex_05_4.pdf); panorama regional: [ASIPI](https://asipi.org/biblioteca/en/?p=16785)

### Inferences
- **Uso personal**: descargar un MIDI o PDF que un sitio de fans publica gratis, para practicar en privado, es una práctica muy extendida y de bajo riesgo práctico. Aun así, *técnicamente* sigue siendo una copia de un derivado no licenciado. En muchas jurisdicciones latinoamericanas la excepción de copia privada es estrecha (p. ej. Perú la limita a grabaciones sonoras y audiovisuales). No se puede afirmar que sea "legal" en todos los países; lo correcto es decir "uso personal, sin redistribución, bajo responsabilidad del usuario".
- **La app** (que automatiza buscar y descargar) tiene más exposición que el usuario:
  1. La acción debe ser **iniciada y confirmada por el usuario**, una pieza por vez, sin crawling masivo ni precarga.
  2. **Respetar robots.txt y los ToS** de cada sitio, con un User-Agent identificable. No eludir logins, paywalls, límites diarios ni protecciones anti-bot (p. ej. **nada de "MuseScore downloader"**).
  3. Para sitios que bloquean bots (NinSheetMusic, MuseScore), **abrir la ficha en el navegador** y dejar que el usuario descargue e importe.
  4. **Guardar solo en local**, sin subir a la nube compartida ni compartir entre usuarios, y conservar la atribución (arreglista, URL).
  5. **Priorizar archivos aportados por el usuario** (importar desde el almacenamiento) y **mostrar enlaces a tiendas con licencia** (Musicnotes, Sheet Music Plus, libros de Alfred) cuando existan.
  6. **No generar la partitura con IA "de memoria"** como sustituto. Además de inexacta, también sería una reproducción de la obra protegida.
- Aplicar Anthropic `allowed_domains` (solo sitios de una lista curada) reduce el riesgo legal y el de inyección o exfiltración.
- Que Nintendo publicara las pistas de Majora's Mask en Nintendo Music (oct-2026) indica que la escucha oficial existe, pero no da licencia de partituras.

### Gaps
- No obtuve el texto de los Términos de Uso de musescore.com (403) ni de ninsheetmusic.org. No puedo citar una cláusula concreta contra el scraping en esos sitios.
- No encontré la postura pública de Nintendo sobre las partituras de fans (DMCA o tolerancia) en esta sesión.
- No verifiqué el texto vigente de las leyes de Argentina (Ley 11.723), México (LFDA) ni Colombia sobre copia privada aplicada a partituras. Hace falta consulta legal específica según el país del usuario.
