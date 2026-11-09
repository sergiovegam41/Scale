# Live score following, play-along and chord-as-notation for a MIDI keyboard learner app (state as of Nov 2026)

## 1. Which symbolic (MIDI) score-following algorithms work, and how do they handle chords, errors, repeats/jumps and latency?

### Takeaway
For MIDI input, the proven family is a **chord-level HMM with a fast Viterbi/forward update** (Nakamura et al.'s uniform-skip / outer-product HMM). It tolerates pitch errors, insertions and deletions, and allows **arbitrary repeats and jumps** at O(D·N) cost per note, so it fits easily on-device in Dart. OLTW (Dixon/Arzt) is better for expressive concert tracking against a reference performance, but it is a poor fit for a learner who stops, restarts and jumps. A learner app can also combine a simple deterministic "wait mode" matcher with an HMM relocalizer for jumps.

### Cited Findings
**Nakamura et al., Outer-product HMM (arXiv 1404.2313), the most directly implementable reference**
- Performers in practice "start playing from a score position at will and generally make arbitrary repeats and/or skips". Earlier repeat/skip-capable algorithms "cannot be applied to scores of practical length" because of their computational cost — [Nakamura et al., arXiv 1404.2313](https://arxiv.org/abs/1404.2313)
- State = one **chord** of the score, meaning "a set of one or multiple notes performed (almost) simultaneously". The observation is each performed MIDI note, and the hidden variable is the intended chord index — [arXiv 1404.2313 PDF](https://arxiv.org/pdf/1404.2313)
- **Chord asynchrony.** Notes in a chord are emitted through *self-transitions* of the chord state. The measured IOIs between notes of one chord "spread out within about 40 ms", so the model uses a threshold tlimit = 35 ms: notes closer than 35 ms are forced to stay in the same state. Larger gaps are not forbidden; they are treated as chord insertions — [arXiv 1404.2313 PDF](https://arxiv.org/pdf/1404.2313)
- **Transitions**
  - Straight progression: i→i+1.
  - Chord/note insertion: self-transition (i→i).
  - Chord deletion: i→i+2.
  - Repeats/skips: transitions to arbitrary states.
  - Empirical transition probabilities a(j−i) from practice data: a(+1)=0.845, a(0)=0.113, a(−1)=0.0089, a(−2)=0.0052, a(−3)=0.0051, a(+2)=0.0061, a(+3)=0.00073. Values for |jump| beyond about −17..+6 are "very small".
  - [arXiv 1404.2313 PDF, Table 3](https://arxiv.org/pdf/1404.2313)
- **Uniform-skip model.** Set a(i,j)=ε for every j outside a band [i−D1, i+D2]. The Viterbi max then splits into a band term plus one global max, so the cost drops from O(N²) to O(D·N) with no pruning. Reference values (D, D1, D2, ε·N):
  - D=4: D1=1, D2=2, ε·N=0.0263.
  - D=10: D1=7, D2=2, ε·N=0.00981.
  - D=20: D1=15, D2=4, ε·N=0.0048.
  - [arXiv 1404.2313 PDF, Table 4](https://arxiv.org/pdf/1404.2313)
- **Outer-product HMM.** The skip probability factorizes as s_i·r_j: a probability of stopping at position i times a probability of resuming at position j. Resumption tends to happen at bar starts and phrase beginnings. The same fast Viterbi applies. To avoid zero frequencies, a constant 0.01 was added to every bin of the s and r histograms before normalising — [arXiv 1404.2313 PDF](https://arxiv.org/pdf/1404.2313)
- **Wrong-note (emission) model**, tied across states. Each note is classed as correct (in chord), off by a semitone, off by a whole tone, off by an octave, or "rest". P(o|i) = p_A / |c_i^A|, with p_chord=0.9497, p_semitone=0.0145, p_wholetone=0.0224, p_octave=0.0047, p_rest=0.0086 — [arXiv 1404.2313 PDF, Table 5](https://arxiv.org/pdf/1404.2313)
- **Latency budget.** For accompaniment in practice, delay must stay "within a few tens of milliseconds", so score following should take about 10 ms. Conventional Viterbi allows only O(100) chords within that budget. Fast Viterbi stays "within a few tens of milliseconds up to about 10000 chords", and D≈10 is the practical upper bound for 10,000 chords (2014 PC hardware) — [arXiv 1404.2313 PDF](https://arxiv.org/pdf/1404.2313)
- **Accuracy.** On play-through performances with D=10, online error rates were all under about 5%:
  - Debussy: O 3.24%, U 2.78%, N 2.05%.
  - Mozart: about 5.0%.
  - Mussorgsky: about 1.8%.
  - Offline (with backtracking): 0.5–3%.
  - On practice sessions full of skips, the outer-product model beat uniform-skip, which "greatly outperforms" the model without skips.
  - Main error sources: arpeggios and arpeggiated chords, trills and short appoggiaturas, inserted notes, and loose hand synchrony in fast passages.
  - [arXiv 1404.2313 PDF, Tables 6–7](https://arxiv.org/pdf/1404.2313)
- **Relocalization after a jump.** After a jump, at least a few notes must be heard before the position can be identified. The expected "following time" grows roughly as ln(N)/entropy-rate, and knowing likely resumption points shortens it — [arXiv 1404.2313 PDF §3.5](https://arxiv.org/pdf/1404.2313)
- **Follow-up models for ornaments.** A later model handles ornaments (trills, grace notes, arpeggios) and is "highly accurate" on performances "with many ornaments and relatively frequent errors, repeats, and skips" — [Nakamura et al., arXiv 1404.2314](https://arxiv.org/pdf/1404.2314). An autoregressive hidden semi-Markov model was argued to suit trills, tremolos and arpeggios — [ISMIR 2015 paper](https://ismir2015.uma.es/articles/15_Paper.pdf). The Eurydice MIDI piano accompaniment system used HMM score following with "arbitrary repeats and jumps" — [summary](https://sonicfield.org/library/automatic-music-accompaniment-allowing-errors-and-arbitrary-repeats-and-jumps)

**Dixon OLTW (2005)**
- On-line time warping computes a partial row or column of the DTW matrix within a band of width c. A `GetInc` routine chooses whether to advance the row, the column or both, and `MaxRunCount` limits consecutive steps in one direction. Dixon used MaxRunCount=3 "to allow for moderate but not arbitrary differences in tempo", with 20 ms frames and c=500 frames (10 s). Time and space are linear — [Dixon, IJCAI 2005](https://webspace.eecs.qmul.ac.uk/s.e.dixon/pub/2005/ijcai05.pdf); [DAFx 2005](https://dafx.de/paper-archive/details/o-kAKlRZ1QVrnYxd28nF0g)

**ACCompanion (JKU, IJCAI 2023), a symbolic MIDI accompanist**
- Incoming MIDI is grouped into **non-overlapping 10 ms windows**. All notes in a window are treated as one chord with one onset — [Cancino-Chacón et al., arXiv 2304.12939](https://arxiv.org/pdf/2304.12939)
- **HMM follower.** A switching Kalman filter (HMM plus tempo) observes the pitches in each window and the IOI. Each score onset has an extra hidden state for insertions, and the forward algorithm gives the position. It is "very reliable for relatively simple sequential input" but struggles with cross-rhythms, ornaments and large tempo changes — [arXiv 2304.12939](https://arxiv.org/pdf/2304.12939)
- **OLTW follower.** It aligns to *pre-recorded reference performances* (an ensemble of OLTWs, averaged) rather than to the score. Median asynchrony was 60.6 ms (OLTW) vs 645.7 ms (HMM). The share of notes within 25/50/100 ms was 38.0/63.3/86.7% for OLTW and 5.5% for HMM. For context, asynchrony between two human performers is 30–40 ms — [arXiv 2304.12939, Table 1](https://arxiv.org/pdf/2304.12939)
- **Tempo smoothing.** A tempo model smooths "erratic score follower outputs due to embellishments or player mistakes". The variants tested were linear synchronization, linear tempo expectation, JADAM, a moving average and a Kalman filter. The key tension from live demos is being "highly reactive and precise" while remaining a "reliable musical partner" — [arXiv 2304.12939](https://arxiv.org/pdf/2304.12939); [abstract](https://arxiv.org/abs/2304.12939)

**Matchmaker (ISMIR 2025, JKU/KAIST), the current open-source reference implementation**
- Python library (`pip install pymatchmaker`, Apache-2.0). Output is the score position in **beats** (partitura `onset_beat`), plus a final `(perf_time, score_beat)` alignment path — [Matchmaker docs](https://pymatchmaker.readthedocs.io/en/latest/usage.html); [PyPI](https://pypi.org/project/pymatchmaker/); [ISMIR 2025 poster](https://ismir2025program.ismir.net/poster_92.html)
- **MIDI methods available:**
  - `pthmm`: pitch-based HMM, the default.
  - `outerhmm`: Nakamura 2014.
  - `hmm`: Cancino-Chacón 2023.
  - `arzt` and `dixon`: OLTW, using the `chord_onset` processor by default.
  - `pfkorz`: Korzeniowski particle filter.
  - `SL_OLTW` / `SLT_OLTW`: symbolic note matchers from parangonar, the second with tempo.
  - `OTM` / `OPTM`: online transformer note matchers.
  - Processors: `pitch`, `chord_onset`, `pianoroll`, `pitchclass`, …
  - The parangonar matchers run event-based, one performed note at a time.
  - [Matchmaker usage](https://pymatchmaker.readthedocs.io/en/latest/usage.html)
- **Audio benchmark** (not MIDI) from the Matchmaker paper:
  - Alignment latency: OLTWDixon 1.22 ms, OLTWArzt 0.07 ms, HMM 3.59 ms.
  - On (n)ASAP, ≤100 ms accuracy: Dixon 58.5%, Arzt 58.3%, HMM 22.2%.
  - The paper notes that small differences in how error is computed shift reported accuracy noticeably.
  - [Park et al., arXiv 2510.10087](https://arxiv.org/html/2510.10087v1)

### Inferences
- **Recommended Dart design** (my synthesis of the sources above):
  1. **Pre-process the score into chord events.** Each event holds its pitch set, beat onset, staff/hand, measure and note IDs. Tied continuations are not new events. Grace notes and trills become optional events with high skip probability, or an "any of these pitches, any count" state.
  2. **Group incoming note-ons** into chords using a 35–40 ms window, or ACCompanion's 10 ms windows plus the self-transition rule.
  3. **Run a uniform-skip HMM** with D≈10 (D1=7 back, D2=2 forward), the Table 3 transition values, the Table 5 semitone/whole-tone/octave emission table, and ε ≈ 0.01/N for jumps. Each update is one band max plus one global max: about 10·N operations per note. For N=2000 chords that is roughly 20k multiply-adds, well under 1 ms in Dart AOT.
  4. **Weight resumption** for the outer-product variant toward bar starts, phrase starts, section/repeat starts and any loop start the user has set.
- **Repeats.** Unroll repeats and D.S./coda in the score into a linear performance order (as Nakamura's "performance score" does). Map each unrolled event back to its notation element ID for the cursor. Arbitrary jumps are then handled by the skip transitions.
- **Wait mode vs follow mode.** Wait mode only needs a deterministic rule: "has the expected chord's pitch set been covered (pitch-exact or pitch-class) since the cursor arrived?" The HMM is needed for **free follow mode** (the cursor tracks the player, who can restart anywhere). A practical hybrid: in wait mode, if the HMM's posterior strongly prefers a remote position for 3 or more consecutive chords, offer or perform a relocation.
- **When to prefer OLTW.** OLTW to reference performances (ACCompanion style) suits concert-like expressive following. A learner app has no reference performance and the player stops often, so OLTW's "sticky" monotonic band is a mismatch. Matchmaker's `outerhmm`/`pthmm` can serve as Python references to port and test against.
- **Display smoothing.** To keep the cursor from jittering, only move it forward when the posterior is confident (for example, max-posterior ratio above a threshold). Optionally use a tempo model (moving average or Kalman, as ACCompanion does) to animate the cursor between events.

### Gaps
- Antescofo (IRCAM, Cont): not researched in this pass. Its approach is audio-oriented with a reactive language, so it is less relevant to MIDI.
- partitura/parangonada: confirmed only indirectly, as Matchmaker's data model (`note_array`, `onset_beat`). Parangonada itself (an alignment visualisation tool) was not investigated.
- Exact Matchmaker MIDI benchmark numbers for `pthmm`/`outerhmm` were not found; the paper reports audio results only.
- The Nakamura ornament model's (1404.2314) parameter values were not extracted.

## 2. Which practice modes do learner apps offer, and which features do users value?

### Takeaway
Every major app converges on the same toolkit:
- **wait mode** (the cursor stops until the right notes are played);
- **hand selection** (practise one hand while the app plays or omits the other);
- **slow-down** and **loop a passage**;
- **jumping via a timeline**;
- a **metronome**;
- **highlighting the keys to play** on an on-screen keyboard;
- **percentage scoring** of note and rhythm accuracy.

MIDI is consistently presented as more reliable than the microphone.

### Cited Findings
- **Synthesia**
  - "Melody Practice" waits for the correct key "without any concern about the tempo".
  - Coloured dots appear on keys to play; left hand is blue and right hand green; numbered blocks show fingering.
  - Timeline click/tap jumps to a section; +/− speed control; Pause; "Song Only" / "My Keyboard" zoom; hands can be practised separately; sheet music can be shown.
  - [Synthesia guide](https://www.synthesiagame.com/support/guide/firstSong); [App Store](https://apps.apple.com/us/app/synthesia/id579518445); [Yamaha Hub](https://hub.yamaha.com/?p=44644)
- **Flowkey**
  - Wait Mode, slow motion, loop and hand selection.
  - Wait Mode works with the microphone or MIDI; MIDI gives "smoother note recognition".
  - On Windows only one MIDI app can use the device at a time; MIDI on the web requires Chrome-class browsers.
  - [flowkey help: connect to PC/Mac](https://help.flowkey.com/en/articles/412925-connect-your-instrument-with-your-pc-mac); [flowkey headphones article](https://help.flowkey.com/en/articles/651019-practicing-with-headphones); [BleepingComputer](https://www.bleepingcomputer.com/offer/deals/this-piano-lesson-app-gives-you-live-feedback-and-its-on-sale-for-7999/amp/)
- **Tomplay**
  - Cursor moves across the real score with live-recorded (not MIDI) backing tracks.
  - Tempo change "with no loss of sound quality"; tempo displayed per bar; loop a passage.
  - Practise one hand while a recording plays the other; mute and unmute backing-track parts.
  - Wait Mode: "the cursor only moves when you play the right notes".
  - Integrated metronome, annotations, recording.
  - [Tomplay how it works](https://tomplay.com/how-it-works); [crosseyedpianist review](https://crosseyedpianist.com/2016/04/30/tomply-an-app-for-an-immersive-learning-and-playing-experience/); [kraftgeek](https://kraftgeek.com/en-eu/blogs/musician-guide/what-is-tomplay-interactive-sheet-music-app-for-musicians)
- **Piano Marvel**
  - Scoring assesses **note accuracy and rhythm accuracy** only, not dynamics or articulation. Medals: 80% bronze, 90% silver, 96% gold, 100% "super gold".
  - SASR sight-reading test: 30 s preparation; scoring 80% or more advances to harder pieces; 18 levels / 90 sublevels.
  - Common "incorrect" marks come from wrong accidentals, wrong octaves and duration errors. Pedal is not read via MIDI.
  - [Piano Marvel Play Mode](https://pianomarvel.com/feature/play-mode); [SASR](https://pianomarvel.com/feature/sasr); [support: scoring issues](https://support.pianomarvel.com/portal/en/kb/articles/scoring)
- **Simply Piano.** A review praises its "hands separately" then "hands together" progression — [techwalls review](https://www.techwalls.com/simply-piano-honest-review-teach-you-to-play-piano/). Official docs on wait/loop/slow-down were not found.
- **Playground Sessions.** An undated user forum post asks for a "Wait" function, which suggests it was missing at the time — [Playground forum](https://forums.playgroundsessions.com/viewtopic.php?p=17790)
- **Page turning**
  - Newzik "listens" through the microphone, locates the bar and turns the page ahead of time. It also offers tempo-based turning, pedal and face gestures — [Newzik audiomatching blog](https://en.blog.newzik.com/blog/audiomatching-tourne-page-cest-quoi); [newzik.com](https://newzik.com/en/)
  - forScore turns pages from a metronome (beats per page) or from an attached audio track (Replay), not by listening — [forScore](https://forscore.co/?p=371)

### Inferences
- **Must-have set for Scale** (synthesis): wait mode (with a "rhythm" variant that keeps tempo and scores timing), choice of hand (right/left/both, with the unplayed hand optionally sounded by MIDI out), A–B loop, tempo slider (for example 25–150%), count-in plus metronome, keys highlighted on the on-screen keyboard (colour-coded by hand), and a percentage score split into notes and rhythm.
- **Scoring tiers.** Piano Marvel's 80/90/96/100% tiers are a well-known reference.
- **Scoring tolerance.** Since timing errors and octave errors dominate false negatives, the matcher needs a configurable timing window and possibly an "octave-tolerant" setting for beginners.

### Gaps
- Official help-centre pages for Simply Piano, Skoove and Playground Sessions features were not retrieved, and no 2025–2026 changelogs were checked.
- No published data on which features users value most (surveys or retention); the evidence is feature convergence across apps, not user studies.
- Exact wait-mode semantics (whether wrong notes are penalised, whether partial chords count, timeouts) are undocumented for all apps.

## 3. How do apps sync the cursor with the rendered score and with playback?

### Takeaway
The standard pattern is a **time map**: every note or rest element has a stable ID, a score onset (beats or quarter notes), a performance time in ms at the current tempo, and a page/system location. Playback, the follower and the cursor all communicate through the score position (beats or event index) and these element IDs.

### Cited Findings
- **Verovio** (C++/WASM/JS engraver):
  - `renderToMIDI()` returns base64 MIDI.
  - `getElementsAtTime(ms)` returns `{page, notes:[ids]}`; `page: 0` signals an error.
  - Its tutorial highlights by adding a CSS class to the SVG `g.note` elements with those IDs and re-renders the page when `page` changes.
  - `renderToTimemap()` gives entries with element IDs, onset/offset times and page numbers, with options to include rests and measures.
  - Tempo changes only at measure starts in the MIDI/timemap code.
  - [Verovio book: playing MIDI](https://book.verovio.org/interactive-notation/playing-midi.html); [Verovio toolkit methods](https://book.verovio.org/toolkit-reference/toolkit-methods.html); [pypi-verovio docs mirror](https://tessl.io/registry/tessl/pypi-verovio/files/docs/data-access.md)
- **Matchmaker/partitura** expresses follower output in score **beats** (`onset_beat` from `note_array()`), interpolated within the onset array — [Matchmaker usage](https://pymatchmaker.readthedocs.io/en/latest/usage.html)
- **ACCompanion score representation.** Each score note is a triple (pitch, onset in beats, duration in beats); chord notes share one score onset. Each performed note is (pitch, onset s, duration s, velocity) — [arXiv 2304.12939](https://arxiv.org/pdf/2304.12939)
- **Newzik** maps the recognised sound to bars and anticipates the turn — [Newzik blog](https://en.blog.newzik.com/blog/audiomatching-tourne-page-cest-quoi)
- **Flutter notation packages (pub.dev):**
  - `flutter_notemus`: SMuFL/Bravura, grand staff, JSON import; Apache-2.0.
  - `crisp_notation` (0.4.x): every element "identifiable, hit-testable, highlightable".
  - `flutter_music_notation` (0.1.0): claims MIDI and synchronised playback; unverified.
  - [flutter_notemus](https://pub.dev/packages/flutter_notemus); [crisp_notation docs](https://pub.dev/documentation/crisp_notation/0.4.4/); [flutter_music_notation](https://pub.dev/packages/flutter_music_notation)

### Inferences
- **Recommended data model** (synthesis):
  - `ScoreEvent { idx, beat, measure, staff/hand, pitches[], noteIds[], performanceOrderIdx }`, built once after unrolling repeats.
  - `TimeMap`: beat ↔ ms at tempo factor k (piecewise from tempo marks), and beat → x-position/system/page from the renderer's layout.
- **Who drives the cursor.**
  - Playback: the scheduler's current beat.
  - Wait mode: the current event index.
  - Follow mode: the HMM argmax event.
  - All three resolve through the same map to a cursor rectangle and to highlighted note IDs. Auto-scroll or page-turn fires when the next event's system differs, ideally one or two events ahead, as Newzik "anticipates".
- **Renderer choice.** In Flutter, either render natively with an ID-aware package (crisp_notation's hit-testable elements suit highlighting) or embed Verovio (WASM in a WebView, or FFI to the C++ library). Verovio already provides timemap and IDs, at the cost of a WebView/FFI bridge.

### Gaps
- How Synthesia, Flowkey and Tomplay internally map cursor to score is proprietary and not documented. Tomplay appears to use hand-aligned cursors over pre-engraved pages, but that is unconfirmed.
- OpenSheetMusicDisplay's cursor API was not researched in this pass.
- The maturity and performance of the Flutter notation packages were not tested; version info on pub.dev was inconsistent between cached pages (flutter_notemus 2.5.1 vs 2.8.0).

## 4. How should a played chord be displayed on a grand staff?

### Takeaway
Engraving conventions are well established and can be implemented in a small renderer:
- **One stem per chord**, direction set by the note farthest from the staff's middle line.
- In a **second**, the lower note sits left of the stem and the upper note right (the "displaced" notehead).
- **Accidentals stack** in columns left of the chord: the top accidental nearest the noteheads, then the bottom, then working inward.
- **Pitch spelling** must come from key or chord context (ps13 and Chew–Chen reach about 99% on corpora; for a single chord, spelling from the chord root and key signature is simpler).

### Cited Findings
- **Stem direction (single voice).** "If the note furthest from the middle line is above the middle line, the stem of the chord points downwards." When balanced, Dorico follows adjacent notes, otherwise its default — [Dorico stem direction](https://archive.steinberg.help/dorico/v2/en/dorico/topics/notation_reference/notation_reference_stems_direction_c.html); [music-theory-practice](https://music-theory-practice.com/guides/note-stem-direction); [Colorado College engraving notes](https://sites.coloradocollege.edu/musicengraving/engraving-convention/notes-and-stems). Sources disagree on ties: some say stem down, Dorico uses context.
- **Seconds.** "In an interval of a second on a single stem the lower note is placed on the left of the stem, the upper note on the right… the note head on the wrong side of the stem is called a 'displaced' note." Finale aligns the chord to the non-displaced heads and slightly overlaps seconds — [Finale Notational Defaults](https://www.finalemusic.com/UserManuals/Finale2011Mac/Content/Finale/Finale_Notational_Defaults.htm). Several style guides say to align on the "correct" notehead — [Steinberg forum](https://forums.steinberg.net/t/note-position-in-chord-stack/919262)
- **Accidental stacking**
  - Order: top accidental closest, then bottom, then second from top, then second from bottom, "working inward". Second priority is keeping each accidental close to its notehead.
  - Vertical alignment depends on the intervals in the chord, the note count (2, 3, 4+) and whether notes are displaced.
  - [notat.io thread](https://www.notat.io/viewtopic.php?p=11947); [MuseScore forum](https://musescore.org/en/node/254781)
  - Dorico stacks in columns and treats chords with 6 or more accidentals within an octave as "dense" — [Dorico stacking of accidentals](https://steinberg.help/dorico/v4/en/dorico/topics/notation_reference/notation_reference_accidentals/notation_reference_accidentals_stacking_c.html)
  - General reference: [MPA standard practice engraving](https://www.mpa.org/wp-content/uploads/2018/06/standard-practice-engraving.pdf)
- **Pitch spelling**
  - ps13 (Meredith) uses local key plus voice-leading and spelled 99.31% of 195,972 notes correctly (best variant 99.43%) — [ps13, Goldsmiths](https://research.gold.ac.uk/id/eprint/1007); [Meredith ISMIR 2005](https://archives.ismir.net/ismir2005/paper/000004.pdf)
  - Chew & Chen's Spiral Array picks the nearest spelling to a moving centre of effect; its best version spelled 99.15% on the broad corpus — [Meredith 2007 comparison](https://research.gold.ac.uk/1006/1/COMP_Meredith_2007a.pdf)

### Inferences
- **Algorithm for Scale's free-play grand staff** (synthesis; no single source):
  1. **Staff split.** With no hand information from MIDI, split at middle C: MIDI ≥ 60 goes to treble and < 60 to bass. Add hysteresis or a "gap" heuristic: if the chord has a large gap (for example ≥ a fifth) near middle C, split at the gap so a left-hand cluster around C4 stays together. Optionally let the user choose "split at C4" or "split at gap". If a split point is configured on the Yamaha (split/dual voice), reuse it.
  2. **Spelling.** If a chord was detected (root, quality), spell each pitch as a chord tone relative to the root letter (third = root letter +2, fifth = +4, seventh = +6). This yields, for example, E♭–G–B♭ in E♭ and D♯–F♯–A♯ in D♯m. Choose the root's own spelling from the song or detected key (sharps for sharp keys, flats for flat keys). If no chord is recognised, fall back to the key signature's preference plus a ps13-like rule (prefer the spelling closest on the line of fifths to the key centre).
  3. **Notehead columns per staff.** Sort pitches by staff position (diatonic step, not semitone). Walk from the stem end: for stem up, go bottom to top; whenever a note is one diatonic step from the previous note that stayed in the normal column, place it on the opposite side. Two notes with the same letter but different accidentals (augmented unison, for example G and G♯) also need side-by-side heads.
  4. **Stem.** Compare the outermost note distances from the middle line (B4 for treble, D3 for bass). The farther one wins; on a tie, stem down.
  5. **Accidentals.** Show an accidental only when it differs from the key signature (each displayed chord is its own measure, so courtesy rules do not apply). Assign columns in the order top, bottom, 2nd from top, 2nd from bottom, …; a new column is needed when two accidentals are within about a sixth vertically.
  6. **Ledger lines.** Draw for notes above F5 or below E4 (treble), and above A3 or below G2 (bass). Ledger lines for a displaced head must extend across both columns.
- **Note value.** For free play, whole notes (no stem) avoid stem logic entirely, as many chord-identifier displays do. That is a valid simplification; stem rules are only needed if note values are shown.

### Gaps
- No authoritative source was found on how chord-identifier apps or MuseScore's input preview choose the staff for live MIDI chords (split at middle C vs gap). The heuristics above are my own suggestion.
- Tenuto / musictheory.net chord-display behaviour was not investigated.
- Exact accidental column spacing values (in staff spaces) were not extracted from engraving references; SMuFL font metadata (Bravura `engravingDefaults`) would provide glyph-based spacing.

## 5. How should the score be played back through MIDI out (tempo, metronome, per-hand muting)?

### Takeaway
Commercial apps expose tempo scaling, a metronome, looping and per-part or per-hand muting. In Tomplay this means muting backing-track parts and playing one hand against a recording of the other. For MIDI out, this means scheduling score events from the time map at tempo factor k and filtering by staff, hand or part.

### Cited Findings
- Tomplay: tempo slow-down and speed-up, tempo shown per bar, loop, metronome, mute and unmute parts, and play one hand with the other recorded — [Tomplay](https://tomplay.com/how-it-works); [kraftgeek](https://kraftgeek.com/en-eu/blogs/musician-guide/what-is-tomplay-interactive-sheet-music-app-for-musicians)
- Synthesia: +/− speed, pause, timeline seek, hands separately — [Synthesia guide](https://www.synthesiagame.com/support/guide/firstSong)
- Verovio generates MIDI from the score, with tempo changes honoured only at measure starts — [Verovio book](https://book.verovio.org/interactive-notation/playing-midi.html); [pypi-verovio docs](https://tessl.io/registry/tessl/pypi-verovio/files/docs/data-access.md)
- ACCompanion adapts accompaniment tempo, dynamics and articulation to the soloist via the follower and a tempo model. This is the "accompaniment follows you" mode, as opposed to fixed-tempo playback — [arXiv 2304.12939](https://arxiv.org/pdf/2304.12939)
- Accompaniment that reacts to the player needs end-to-end delay of a few tens of ms. Score following itself should take about 10 ms — [arXiv 1404.2313 PDF](https://arxiv.org/pdf/1404.2313)

### Inferences
- **Implementation in Dart** (synthesis):
  - Build a lookahead scheduler, for example a 25 ms tick with a 100 ms window, that sends note-on/off from `ScoreEvent`s whose ms-time (beat × 60000 / (bpm × k)) falls in the window.
  - Per-hand muting means skipping events whose staff equals the muted hand.
  - Send the metronome on MIDI channel 10 (GM percussion, for example note 37 or 76/77) or as a local click.
  - **Play-along "you play the right hand"**: the scheduler plays the left hand, and in wait mode it pauses scheduling until the right-hand chord is matched.
  - **Follow-accompaniment**: drive scheduler time from the follower's beat estimate through a smoothed tempo (moving average or Kalman, per ACCompanion).
- **Feedback-loop hazard.** Notes sent to the keyboard may echo back on MIDI in (local control or MIDI thru). The follower must ignore notes the app itself just sent (match by pitch within about 50 ms), or the user should turn local echo off. This is a practical hazard, not covered by the sources above.

### Gaps
- No source was found documenting Yamaha-specific MIDI echo/local-control behaviour, or how the commercial apps avoid self-triggering when playing through the student's keyboard.
- No data was found on what tempo range, count-in length or metronome subdivisions learners prefer.
