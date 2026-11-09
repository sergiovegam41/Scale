# Sheet-music formats and interactive rendering in Flutter (Android + Windows, web later), state as of Nov 2026

Research date: 2026-11-08. About 20 search/fetch calls. Items marked "(prior knowledge, not re-verified)" come from background knowledge and were not confirmed against a live source in this session. Treat them as leads to check.

## 1. Formats: MusicXML 4.0, MEI 5, ABC, MNX, Humdrum, MIDI. Which is best for interchange, and which for the app's internal model?

### Takeaway
MusicXML is still the only practical interchange format. 4.0 (June 2021) is the last final report, and 4.1 is a community-group draft (April 2025). MNX is still a draft under active development in 2026, so it isn't ready to ship on. Real apps (Soundslice, Flat) import and export MusicXML but convert it to their own internal model, which is the pattern Scale should follow.

### Cited Findings
- MusicXML is maintained by the W3C Music Notation Community Group. The last *final* report is MusicXML 4.0 (1 June 2021). MusicXML 4.1 exists only as a draft community-group spec dated 3 April 2025, "not a W3C Standard nor … on the W3C Standards Track". No final 4.1 release was found. — [w3c.github.io/musicxml](https://w3c.github.io/musicxml); [Wikipedia: MusicXML](https://en.wikipedia.org/wiki/MusicXML)
- MEI 5.1 was announced on 23 Jan 2025 as a maintenance release: mostly guideline and infrastructure fixes, plus new tablature elements (`tuning`, `course`, `string`, `tabDurSym`, `tabGrp`). A Zenodo record shows a conflicting date. — [MEI-L: MEI 5.1 Released](https://lists.uni-paderborn.de/pipermail/mei-l/2025/002789.html); [MEI v5 guidelines intro](https://music-encoding.org/guidelines/v5/content/introduction.html); [Zenodo 5.1](https://zenodo.org/records/10040258/latest)
- MNX is still a *draft* spec ("MNX Draft Specification") under the W3C Music Notation CG. The CG decided to focus MNX on the semantic format (formerly "MNX-Common") and move MNX-Generic to a separate spec. — [MNX draft spec](https://w3c.github.io/mnx/specification/common/); [Co-chair minutes Jan 2025](https://www.w3.org/community/music-notation/2025/01/03/co-chair-meeting-minutes-january-2-2025/)
- MNX work was still ongoing through 2025–2026: an in-person workshop in London (4 Jul 2025), cleanup of spec "infrastructure" pages (Oct 2025), ID character rules settled in 2026 (issue #503), and a working-group meeting scheduled for 26 May 2026. — [Workshop Jul 2025](https://lists.w3.org/Archives/Public/public-music-notation/2025Jul/0000.html); [Minutes Oct 2025](https://www.w3.org/community/music-notation/2025/10/09/co-chairs-meeting-minutes-october-9-2025); [List 2026-Feb](https://lists.w3.org/Archives/Public/public-music-notation/2026Feb/0002.html); [List 2026-May](https://lists.w3.org/Archives/Public/public-music-notation/2026May/0000.html)
- **Soundslice:** "Once you've imported a MusicXML file into Soundslice, it gets converted into our own internal format." It also reads Guitar Pro, PowerTab and TuxGuitar natively, because their MusicXML exports drop information. — [Soundslice help: MusicXML](https://www.soundslice.com/help/en/creating/importing/63/musicxml/)
- Soundslice stores chord symbols "very flexibly (basically any set of characters)", which caused round-trip problems with Dorico's MusicXML import (user forum reports). — [Steinberg forum: missing chord symbols](https://forums.steinberg.net/t/importing-musicxml-from-soundslice-missing-chord-symbols/962694); [Steinberg forum: big mess](https://forums.steinberg.net/t/musicxml-import-always-makes-a-big-mess-from-soundslice-com-exports/1042498)
- **Flat.io:** `loadMusicXML` converts the score "into Flat's internal format". Flat also has a native JSON format (`loadJSON`/`getJSON`) that "preserves all score data", and it exports MusicXML (`getMusicXML`) and MIDI. A community client describes Flat JSON as MusicXML-like. — [Flat embed API: score management](https://flat.io/developers/docs/embed/api/score-management); [flat-embed npm](https://www.npmjs.com/package/flat-embed)
- Verovio's input formats include MEI, MusicXML, ABC, Humdrum and PAE, so all of these can be rendered through one engine. — [verovio_flutter on pub.dev](https://pub.dev/packages/verovio_flutter)

### Inferences
- **Interchange (import/export):** use MusicXML 4.0, both `.musicxml` and compressed `.mxl`. Finale, Dorico, Sibelius and MuseScore all import and export it, and OMR tools (e.g. Audiveris, PlayScore, MuseScore's import) output it (prior knowledge, not re-verified). Add MIDI import/export because the app is MIDI-first. ABC is worth a cheap importer for folk/lead-sheet material, but it is a niche for piano scores. Humdrum and MEI are mainly academic and musicology formats. Verovio reads them for free, but they aren't worth targeting for export.
- **Internal model:** follow Soundslice and Flat. Keep a small, app-specific Dart model, serialised as JSON, built for what Scale needs: notes with MIDI pitch, onset/duration in ticks, voice/staff, chord symbols, measure/time/key, plus stable note IDs for cursor and highlight mapping. Convert to MusicXML on export, and to MusicXML or MEI for rendering. Do not use raw MusicXML as the internal model. It is verbose and layout-laden, and the same music can be encoded in several ways.
- MNX's semantic, JSON-based direction matches this kind of internal model and could become a future export target. In Nov 2026 it is still a moving draft with little tool support, so don't depend on it.
- Plain MIDI as a *source* has no spelling (C# vs Db), voices, beaming or measures. Turning recorded MIDI into notation needs quantisation plus pitch spelling and voice separation. That is a separate problem from rendering (prior knowledge).

### Gaps
- No official 2026 "Status of this document" for MNX was retrieved, and no list of tools shipping MNX import/export was found.
- Internal formats of MuseScore (`.mscz`, zipped XML), Newzik and forScore were not verified in this session. forScore and Newzik are largely PDF-centric with annotation, and Newzik offers MusicXML/"LiveScore" conversion (prior knowledge, not re-verified).
- ABC 2.1 vs 2.2 status on abcnotation.com was not checked. ABC 2.1 (2011) is the last widely cited standard (prior knowledge).

## 2. Renderers: OSMD, Verovio, VexFlow, abcjs, alphaTab, native Flutter packages (versions, licenses, maintenance)

### Takeaway
All the main JS/C++ engines are actively maintained in 2026. OSMD 2.3.0 (7 Nov 2026) is MusicXML-only and BSD-3. Verovio 6.x (6.3.0 Aug 2026, 6.4.0 on PyPI) is LGPL-3.0 and multi-format. alphaTab 1.8.x is MPL-2.0 (prior knowledge), mature on MusicXML, but guitar-oriented. A Flutter FFI wrapper for Verovio exists (`verovio_flutter` 0.3.3, LGPL-3.0) but has no Windows support. The pure-Dart notation packages are toy-level or stale.

### Cited Findings
**OpenSheetMusicDisplay (OSMD)**
- BSD-3-Clause. Renders MusicXML "in browsers and headless with NodeJS", built on VexFlow, by PhonicScore. The audio player is "early access for GitHub Sponsors" and still a work in progress. Native React Native, Kotlin/Android and Swift/iOS modules are also sponsor early access. Note re-colouring is supported through SVG node manipulation. — [OSMD GitHub](https://github.com/opensheetmusicdisplay/opensheetmusicdisplay)
- Recent releases, years taken from the changelog:

  | Version | Date | Notes |
  |---|---|---|
  | 1.9.8 / 1.9.9 | 4–5 May 2026 | — |
  | 2.0.0 | 15 Jun 2026 | ~2x faster (geometric skyline); incremental rendering `renderNext`; cross-staff slurs; nested tuplets |
  | 2.1.x | Jul–Sep 2026 | 2.1.2 ~40% median speedup; 2.1.3 cursor-jump fix and ~14% faster `load()` |
  | 2.2.0 | 2 Oct 2026 | ~10% faster; 89 fixes, including cursor fixes for multiple instances and fade |
  | 2.2.1 | 12 Oct 2026 | — |
  | 2.3.0 | 7 Nov 2026 | ~13% faster median render; `dispose()`; leaner SVG with `osmd-` CSS classes (breaking for some CSS selectors) |

  — [OSMD releases](https://github.com/opensheetmusicdisplay/opensheetmusicdisplay/releases)

**Verovio**
- Release dates per piwheels/Zenodo:

  | Version | Date | Notes |
  |---|---|---|
  | 5.6.0 | 2025-09-09 | timemap/MIDI-output fixes |
  | 5.7.0 | 2025-12-02 | — |
  | 6.0.0 | 2026-01-28 | ossia staves; expansion generation in the MusicXML importer |
  | 6.0.1 | 2026-01-29 | — |
  | 6.1.0 | 2026-03-12 | — |
  | 6.2.0 / 6.2.1 | 2026-05-21 / 22 | — |
  | 6.3.0 | 2026-08-19 | — |
  | 6.4.0 | — | listed on PyPI, artifacts verified 30 Oct 2026; no notes found |

  — [piwheels verovio](https://www.piwheels.org/project/verovio/); [PyPI verovio](https://pypi.org/project/verovio); [Zenodo 6.0.0](https://zenodo.org/records/18403240); [Zenodo 6.2.1](https://zenodo.org/records/20348206)
- Licensed LGPL-3.0: "any derivative work must comply with the same obligations". — [verovio_flutter](https://pub.dev/packages/verovio_flutter)

**VexFlow**
- VexFlow 5.0.0 is on npm under the MIT licence ("Copyright (c) 2023-present VexFlow contributors"). Fonts are loaded at runtime, e.g. `VexFlow.loadFonts('Bravura', 'Academico')`. Petaluma is one of the supported fonts. — [vexflow npm](https://npmjs.com/package/vexflow); [VexFlow 5.0.0 README](https://app.unpkg.com/vexflow@5.0.0/files/README.md); [VexFlow getting started](https://vexflow.github.io/vexflow-examples/guides/getting-started)

**abcjs**
- 6.7.0 is published on npm. Its release notes fix a "TimingCallbacks gets one last call after it has been stopped" bug. 6.6.3 fixed a wrong TimingCallbacks `startTime`, and 6.4.4 fixed cursor movement with synth plus tablature. — [abcjs 6.7.0 RELEASE.md](https://unpkg.com/abcjs@6.7.0/RELEASE.md); [abcjs 6.6.4 RELEASE.md](https://cdn.jsdelivr.net/npm/abcjs@6.6.4/RELEASE.md)

**alphaTab**
- The MusicXML docs (for 1.9.0) rate support "Mature, good test coverage", with 62% of all features and 52% of relevant features supported. Supported: partwise/timewise/compressed MXL, multiple parts, staves and voices, lyrics (partial), `harmony` chord symbols (root/kind/degree only), dynamics, repeats, ties, slurs, and common ornaments and articulations. Not supported: page/system/staff layout and `default-x/y` ("no strict print-page display"), figured bass, cue notes, and many mid-measure key/time/clef changes. — [alphaTab MusicXML](https://alphatab.net/docs/formats/musicxml)
- NuGet has AlphaTab and AlphaTab.Windows 1.8.4. alphaTab ships Web, .NET (including Windows) and Android getting-started guides. — [NuGet AlphaTab](https://www.nuget.org/packages/AlphaTab/); [NuGet AlphaTab.Windows](https://www.nuget.org/packages/AlphaTab.Windows/); [alphatab.net](https://alphatab.net/)
- The 1.5 release reimplemented the MusicXML parser, noting "MusicXML supports a lot more than alphaTab does". — [alphaTab 1.5 release notes](https://alphatab.net/docs/releases/release1_5)

**Native Flutter packages (pub.dev)**

| Package | Version | Licence | Platforms | Status |
|---|---|---|---|---|
| `verovio_flutter` | 0.3.3 (~4 months before Nov 2026) | LGPL-3.0 | Android (API 21+), iOS 13+, Web (WASM). **Windows/Linux/macOS not listed** | Verified publisher csa8820.top; 150 pub points, 2 likes, 244 downloads |
| `simple_sheet_music` | 1.0.1 (~2 years old) + 2.0.0-dev.1 | MIT | All platforms | Unverified uploader; 21 likes, 150 points |
| `flutter_music_notation` | 0.1.0 | BSD-3-Clause | — | — |
| `sheet_music` | 0.3.0 | MIT | — | Verified publisher |

- `verovio_flutter` details: an FFI plugin that renders MEI/MusicXML/ABC/Humdrum/PAE to SVG *strings*, which you "render … with any SVG widget of your choice (e.g. flutter_svg, jovial_svg, a WebView…)". APIs include `loadData`, `renderToSvg(pageNo)`, `VerovioPageCache`, `VerovioAsyncService.spawn` (isolate), and on web `renderPageWithHitMap()`/`hitTestPoint()`. It mentions MIDI and time-map support ("All 38 Verovio API actions" on Web). Web uses Verovio 6.2.0 and native uses 6.2.1. Bundled size is 43.2 MB. — [verovio_flutter](https://pub.dev/packages/verovio_flutter)
- `simple_sheet_music` is a "Flutter package for rendering sheet music on canvas". Its dependencies (`svg_path_parser`, `xml`) suggest SVG-path glyphs. The page doesn't mention grand staff, chords, ties, beams or MusicXML import. — [simple_sheet_music](https://pub.dev/packages/simple_sheet_music)
- `flutter_music_notation` offers a `NotationView` widget configured by measures and a config object. — [flutter_music_notation docs](https://pub.dev/documentation/flutter_music_notation/latest/)
- `sheet_music` covers "all major flat and sharp scales, notes from 5 below and 5 above the bar, Treble and Bass Clef". — [sheet_music](https://pub.dev/packages/sheet_music/install)

### Inferences
- **Licences.** OSMD (BSD-3), VexFlow (MIT) and abcjs (MIT, prior knowledge) are permissive. Verovio is LGPL-3.0. That is fine for a free or personal app, and fine for a closed app if Verovio is dynamically linked (a separate .so/.dll) or loaded as separate JS/WASM so users can swap it. Static linking into a closed binary is the risky case. alphaTab is MPL-2.0 (prior knowledge, not re-verified): file-level copyleft, which is fine to use unmodified.
- **Engraving quality.** Verovio is the strongest engraver for piano/classical repertoire and has a first-class timemap. OSMD is the most "MusicXML-faithful" in the browser and now fast (2.x). alphaTab is strongest for guitar/tab and has a built-in synth and player cursor, but it ignores MusicXML layout and is less suited to piano grand-staff engraving. abcjs is great for ABC/lead sheets, not for MusicXML piano scores.
- `verovio_flutter` is very young (2 likes, a few hundred downloads). It proves the FFI path works on Android but doesn't cover Windows. Scale would either have to add a Windows build of Verovio (Verovio is portable C++ built with CMake, so a Windows DLL is feasible; prior knowledge) or use a WebView there.
- The pure-Dart packages can't import MusicXML or engrave real scores. At most, they're useful as references for drawing a small staff.

### Gaps
- No official alphaTab 1.8/1.9 release date was retrieved. Licence (MPL-2.0) and Android native status were not re-verified.
- OSMD bundle size (minified JS, roughly 1–1.5 MB from prior knowledge) and the VexFlow version bundled inside OSMD 2.x were not stated on the pages fetched.
- abcjs licence and current latest version beyond 6.7.0 were not verified.
- `verovio_flutter`'s GitHub repo, issue activity and whether Windows is planned were not checked.

## 3. Cursor and highlighting for live play-along (note IDs ↔ time ↔ screen coordinates)

### Takeaway
Every serious engine supports it. Verovio is the cleanest fit for "follow the player": `renderToTimemap`/`getElementsAtTime(ms)` return note IDs that match `<g class="note" id=…>` in the SVG. OSMD has a step-wise `cursor` API (`cursor.next()`, `cursor.iterator`) and per-note colouring. abcjs has `TimingCallbacks` with beat/event callbacks, and alphaTab has a built-in player cursor. For live MIDI following (the player drives the time, not a clock), Scale needs its own note-ID → onset map. Verovio's timemap or OSMD's iterator can supply it.

### Cited Findings
- **Verovio.** `renderToMIDI()` returns base64 MIDI. `getElementsAtTime(ms)` returns `{page, notes:[ids]}`. Rendered notes are `g.note` elements whose `id` matches those IDs. The official example highlights by adding a `playing` class (`g.note.playing { fill: crimson; }`) and re-renders when `page` changes. — [Verovio book: Playing MIDI](https://book.verovio.org/interactive-notation/playing-midi.html)
- Verovio 5.6.0 focused on fixes "particularly in the timemap and MIDI output". — [piwheels / Verovio news via search](https://www.piwheels.org/project/verovio/)
- `verovio_flutter` exposes time-map and MIDI, plus on web `renderPageWithHitMap()`/`hitTestPoint()` for tap → element mapping. — [verovio_flutter](https://pub.dev/packages/verovio_flutter)
- **OSMD.** Recent releases fix cursor behaviour: 2.1.3 fixed cursor jumping and an iterator timestamp bug; 2.2.0 added cursor fade, screen-reader handling and multiple-instance correctness. Note colouring via SVG nodes is a listed feature. — [OSMD releases](https://github.com/opensheetmusicdisplay/opensheetmusicdisplay/releases); [OSMD GitHub](https://github.com/opensheetmusicdisplay/opensheetmusicdisplay)
- **abcjs.** `TimingCallbacks` gives event and beat callbacks. The cursor position is interpolated between notes, and "the higher the number of beatSubdivisions the smoother the cursor will be". Elapsed time is reported in ms and whole notes. — [abcjs timing callbacks docs](https://docs.abcjs.net/animation/timing-callbacks); [abcjs RELEASE.md](https://unpkg.com/abcjs@6.7.0/RELEASE.md)

### Inferences
- OSMD cursor API details, from prior knowledge (not re-verified): `osmd.cursor.show()`, `.next()`, `.reset()`, `.iterator.currentTimeStamp`, `cursor.NotesUnderCursor()`, and `GraphicalNote.getSVGGElement()` for colouring. These suit "advance the cursor when the player hits the right notes" (Synthesia-style wait mode) very well.
- Verovio's `renderToTimemap()` (prior knowledge) returns entries with `tstamp` (ms), `qstamp` (quarter notes), `on`/`off` note-ID arrays and `tempo`. That table is the ideal bridge between incoming MIDI note-ons and score note IDs. Verovio's `getMIDIValuesForElement(id)` returns pitch/time (prior knowledge).
- In a WebView, highlighting is cheap: toggle CSS classes on existing SVG nodes. With flutter_svg, every highlight change re-parses and re-draws the whole SVG page. That is a performance concern, so a native approach would want an overlay layer (cursor and highlights drawn by Flutter on top of a static picture) using element bounding boxes. Verovio can emit bounding boxes (`svgBoundingBoxes` option; prior knowledge, not re-verified).

### Gaps
- Not verified this session: alphaTab's player cursor API (`playerPositionChanged`, `activeBeatsChanged` events; prior knowledge) and whether it can be driven by external MIDI input rather than its own synth.
- No benchmark found for highlight/cursor update rates on mid-range Android tablets.

## 4. Embedding in Flutter: WebView vs flutter_svg vs FFI; Android, Windows and web

### Takeaway
Two workable stacks:
- **(A) WebView + bundled JS.** OSMD or Verovio-WASM run as offline assets, with `webview_flutter` on Android and `flutter_inappwebview` (WebView2) on Windows. This is fastest to build and reuses the mature JS APIs, and it carries over to Flutter web. On Windows, WebView2 must be present: built into Windows 11, may be missing on Windows 10.
- **(B) Verovio through dart:ffi, then SVG, then a Flutter SVG widget.** The `verovio_flutter` package proves this on Android, iOS and web, but Windows isn't supported, and flutter_svg's `<use>`/`<symbol>` support is historically partial.

### Cited Findings
- `flutter_inappwebview` on Windows uses WebView2 and is an endorsed federated plugin. The WebView2 Runtime ships with Windows 11 but may be absent on Windows 10. The docs advise a `WebViewEnvironment` with a custom user-data folder, because the default (next to the exe) can crash apps installed in read-only directories. — [flutter_inappwebview_windows](https://pub.dev/documentation/flutter_inappwebview_windows); [inappwebview docs](https://www.inappwebview.dev/docs/webview/in-app-webview)
- `webview_flutter_windows` 1.1.1 is a maintained community fork of `webview_windows`, not affiliated with the Flutter team. 1.1.0 requires Dart 3.12+/Flutter 3.44+. — [webview_flutter_windows changelog](https://pub.dev/packages/webview_flutter_windows/changelog)
- `webview_win_floating` implements the `webview_flutter` interface on Windows with a native WebView2 control on top of the window. As a result, "Flutter widgets cannot show on top of the webview". — [webview_win_floating](https://pub-web-s1.flutter-io.cn/packages/webview_win_floating)
- No official Flutter-team Windows implementation of `webview_flutter` was found. — [search summary of above pages](https://pub.dev/documentation/flutter_inappwebview_windows)
- Verovio SVG references glyphs through `<use>` → `<symbol>` defs. A SharpVectors issue about Verovio SVG points to the `overflow="visible"` header attribute as a source of clipping problems. — [SharpVectors issue #284](https://www.github.com/ElinamLLC/SharpVectors/issues/284)
- flutter_svg added `<use>`, `<symbol>` and `<defs>` support early on, "with some limitations". A fork (`flutter_svg_plus`) lists a fix for "incorrect fills in some cases of `<use>` elements". — [flutter_svg 0.8.2 changelog](https://pub-web-s2.flutter-io.cn/packages/flutter_svg/versions/0.8.2/changelog); [flutter_svg_plus changelog](https://pub.dev/packages/flutter_svg_plus/changelog)
- Verovio's SMuFL text font is embedded as base64 by default. If text glyphs (e.g. dynamics, tempo marks) rely on that embedded font rather than paths, a non-browser SVG renderer may fail to draw them. This is an inference from the Verovio docs. — [Verovio book: SMuFL fonts](https://book.verovio.org/advanced-topics/smufl.html)
- `verovio_flutter` suggests flutter_svg, jovial_svg, a WebView or a custom renderer for its SVG output. It runs Verovio in a background isolate (`VerovioAsyncService.spawn`) and caches pages (`VerovioPageCache`). Package size is 43.2 MB. — [verovio_flutter](https://pub.dev/packages/verovio_flutter)
- OSMD can render headless in Node, and sponsor-only native modules exist for Kotlin/Android. — [OSMD GitHub](https://github.com/opensheetmusicdisplay/opensheetmusicdisplay)

### Inferences
- **Recommended for Android + Windows now:** use `flutter_inappwebview` on both platforms, so there is one API (Android WebView plus Windows WebView2). Load a local HTML page from Flutter assets with OSMD or Verovio-WASM bundled; no network needed. Use `addJavaScriptHandler`/`callHandler` for Dart↔JS messaging (prior knowledge). The MIDI stack stays in Dart (existing USB-MIDI code), and Dart just sends "highlight these note IDs / advance cursor" messages to the page. Avoid `webview_win_floating` if Flutter UI must overlay the score.
- **Flutter web later:** the same HTML/JS can run in an `HtmlElementView`/iframe, or Verovio-WASM can be called directly through `verovio_flutter`'s web backend. The WebView approach therefore ports to web with little effort.
- **Native FFI path (B):** best long-term for smoothness and a "no web engine" app. However, Scale would need (1) its own Windows build of Verovio (CMake → DLL; prior knowledge says Verovio builds with CMake on Windows), (2) an SVG renderer that handles `<use>`/`<symbol>`, which must be tested (jovial_svg or flutter_svg 2.x with vector_graphics), and (3) a custom overlay for cursor and highlights, since re-rendering the SVG per MIDI event is wasteful. An alternative is to ask Verovio for SVG with glyphs inlined as paths, or to parse Verovio's SVG into Flutter `Path`s once and draw with `CustomPainter`, colouring by note ID.
- **Mid-range tablet performance:** OSMD 2.x's large speedups (2x in 2.0, then ~40%, ~10%, ~13%) make WebView rendering of multi-page piano scores more viable than in the 1.x era. Expect initial `load()+render()` of a long score to take noticeable time on low-end ARM, and render page by page (OSMD `renderNext`, Verovio per-page SVG). This is an inference; no tablet benchmarks were found.

### Gaps
- No direct confirmation (issue, test) that flutter_svg 2.x renders Verovio SVG correctly. A quick spike is needed: render a Verovio SVG with flutter_svg and jovial_svg on Android and Windows.
- No measured WebView render times for OSMD or Verovio on Android tablets were found.
- Whether `verovio_flutter` plans Windows desktop support was not checked (its GitHub repo was not fetched).

## 5. SMuFL music fonts and licences

### Takeaway
All the main free SMuFL fonts (Bravura, Petaluma, Leland, Leipzig, Sebastian, the Finale fonts) are SIL OFL. They are safe to bundle in an app, including a commercial one, as long as the font isn't sold on its own and renamed derivatives also stay OFL.

### Cited Findings
- SIL OFL: Bravura, Petaluma, Leland, Leipzig, Sebastian, Eugene, and the Finale Ash/Maestro/Broadway/Engraver/Jazz/Legacy fonts. Commercial: November 2.0, Norfonts, LS Iris, and the Music Type Foundry fonts. — [smufl.org/fonts](https://www.smufl.org/fonts/)
- Bravura 1.482 implements SMuFL 1.4. — [smufl.org/fonts](https://www.smufl.org/fonts/)
- Bravura/Petaluma derivatives may not use the reserved name and must also be OFL. — [smufl.org/fonts](https://www.smufl.org/fonts/)
- VexFlow 5 loads Bravura, Petaluma and others at runtime. — [VexFlow getting started](https://vexflow.github.io/vexflow-examples/guides/getting-started)
- Verovio supports multiple SMuFL fonts. — [Verovio book: SMuFL](https://book.verovio.org/advanced-topics/smufl.html)

### Inferences
- For a native Flutter renderer, bundle Bravura or Leland (`.otf`) as a Flutter font asset. Draw glyphs by SMuFL codepoint (Private Use Area, e.g. U+E050 gClef, U+E062 fClef, U+E0A4 noteheadBlack; prior knowledge). Position them with the font's metadata JSON (`bravura_metadata.json`: `engravingDefaults`, `glyphBBoxes`, `anchors` such as `stemUpSE`; prior knowledge).

### Gaps
- The latest SMuFL spec version (1.4 vs a newer one) was not confirmed. The fonts page only states that Bravura implements 1.4.

## 6. Native "current chord" grand-staff display (CustomPainter + SMuFL glyphs): is it practical?

### Takeaway
Yes, and it's a well-trodden approach. Pure-Dart packages like `simple_sheet_music`, `sheet_music` and `flutter_music_notation` already draw staves, clefs and notes on a canvas. For Scale's live "current chord" widget (a grand staff with a handful of simultaneous notes and accidentals), a custom `CustomPainter` with Bravura/Leland glyphs is simpler and faster than any engraving engine and keeps WebViews out of the hot path.

### Cited Findings
- `simple_sheet_music` is a "Flutter package for rendering sheet music on canvas", MIT-licensed, on all six Flutter platforms. — [simple_sheet_music](https://pub.dev/packages/simple_sheet_music)
- `sheet_music` renders treble and bass clef, all major sharp/flat key signatures, and notes ±5 ledger positions. — [sheet_music](https://pub.dev/packages/sheet_music/install)
- `flutter_music_notation` provides a `NotationView` widget built from measures plus config, BSD-3. — [flutter_music_notation](https://pub.dev/documentation/flutter_music_notation/latest/)
- SMuFL fonts are OFL and freely bundleable. — [smufl.org/fonts](https://www.smufl.org/fonts/)

### Inferences
- The minimum work for a chord display is:
  - 5+5 staff lines with a brace.
  - G and F clef glyphs.
  - A diatonic position for each MIDI note, using the current key for sharp/flat spelling. Middle C goes on a ledger line between the staves; split notes at C4 or by hand.
  - Ledger lines.
  - Accidental stacking: column offsets for clashing accidentals.
  - Seconds displacement: notehead on the opposite side of the stem for adjacent notes.
  - Optional stems.

  This is roughly a few hundred lines of Dart. The tricky parts are accidental collision ordering and seconds; everything else is geometry from SMuFL `engravingDefaults` (staff-space units).
- Spelling should come from Scale's existing key/chord detection: the detected chord root and quality choose sharps vs flats.
- A sensible split for Scale: a native CustomPainter for the live chord widget (low latency, 60 fps, no WebView), and a WebView with OSMD or Verovio (or Verovio FFI later) for full scores.

### Gaps
- None of the pure-Dart packages was code-reviewed for accidental stacking or seconds handling. Their pub.dev pages don't document these features, so they're probably better used as references than as dependencies. `simple_sheet_music` stable is ~2 years old.
