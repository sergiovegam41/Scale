# Performance MIDI to readable piano score: state of the art and practical approaches (as of Nov 2026)

Scope: turning a live keyboard performance captured over USB MIDI (note on/off + timestamps, velocity, CC64 sustain) into an editable two-staff piano score with correct rhythm, meter, key and spelling, for the "Scale" Flutter/Dart app. Research numbers (benchmarks on the ASAP classical piano dataset) are kept apart from real-world/user reports.

## 1. Core sub-problems of performance-MIDI-to-score (PM2S)

### Takeaway
PM2S breaks into beat/tempo tracking, meter/downbeat, rhythm quantization (onsets and note values), voice and staff (hand) separation, key and pitch spelling, and notation details such as ties, rests, beams and ornaments. Rhythm and metre (the "metrical alignment" part) is by far the weakest link in every published system. Pitch, voices, key and hands are much easier.

### Cited Findings
- PM2S (Liu, Kong, Morfi, Benetos, ISMIR 2022, best paper award) splits the problem into: beat tracking (a CRNN predicts which notes fall on beats or downbeats, then beats between notes are filled in by dynamic programming), musical onset time and note value per note, time-signature changes (numerators {0,2,3,4,6}, denominators), key-signature changes (12 classes) and hand part per note — [PM2S paper, ISMIR 2022](https://archives.ismir.net/ismir2022/paper/000047.pdf); [QMUL record](https://qmro.qmul.ac.uk/xmlui/handle/123456789/80694)
- Of the PM2S beat-tracker's inputs, note onset time matters most. Encoding onset as a one-hot "onset shift" works best, and of the data augmentations, tempo change helps most. Pitch and velocity help a little: "beats are more probable to be concurrent with heavy notes" — [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf)
- Typical PM2S rhythm errors: "double/half tempo error and errors introduced by missing/extra beat predictions". The authors say rhythm quantisation performance (MV2H Fme) "is far from satisfactory" — [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf)
- MuseScore's poor scores come from quantising against a single constant tempo estimated over the whole piece. That causes time shifts, low pitch-alignment Fp and low metrical Fme. Finale has a similar limitation — [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf)
- The Beyer & Dai (ISMIR 2024) end-to-end model covers note values, tempo regression, rhythm quantization, voice/staff assignment and typesetting details (stem direction, trills, grace notes, staccato). It does **not** predict key or time signatures or tempo marks, which the authors leave to future work — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1)
- Ornaments are hard. Trills are about 0.15% of notes. Beyer & Dai report trill F1 54.64, grace-note F1 27.80 and staccato F1 18.19 — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1)
- Voice and staff separation are their own tasks. Most methods assume a voice cannot cross staves, which fails for complex piano music. The CPJKU GNN treats voices as possibly containing chords (homophonic) and handles cross-staff voices — [Karystinaios & Widmer, arXiv 2407.21030](https://arxiv.org/html/2407.21030v1)
- Note duration versus written value: on MIDI import, notation software has to guess durations, ties and rests. Representing overlapping notes needs several voices "or an unreadable mess of ties" — [MuseScore forum threads](https://musescore.org/en/node/24960); [MuseScore forum](https://musescore.org/en/node/8279)
- Evaluation metrics: MV2H (multi-pitch Fp, voice Fvo, metre Fme, note value Fva, harmony Fha, averaged into F) — [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf). MUSTER error rates (pitch, missing, extra, onset, offset, average) and ScoreSimilarity (Cogliati & Duan: missing/extra/duration/staff/stem/spelling errors) — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1)

### Inferences
- In a sustained piano performance, MIDI note-off time (key release) does not match the written value. With CC64 held, the sounding length is longer still. Written durations should be inferred from the next onset in the same voice and the metrical grid, not taken from raw key-release or pedal-extended length. Keep the pedal as a separate notation element ("Ped." marks or MusicXML `<pedal>`) and do not lengthen notes with it. (Design inference. No source here measures the pedal effect directly.)
- Dynamics: none of the systems above output dynamics marks. A simple per-phrase velocity-to-dynamic mapping (pp…ff) would be a heuristic of the app's own, with no benchmark to lean on.

### Gaps
- No source found that quantifies how much CC64 handling helps or hurts note-value accuracy.
- No research system that produces dynamics markings from velocity was found.

## 2. Research systems and their accuracy (2016–2026)

### Takeaway
As of late 2026, the strongest open end-to-end system is Beyer & Dai's transformer (ISMIR 2024): about 11.3% average MUSTER error on ASAP, against about 14% for Nakamura/Shibata-style HMM pipelines and 20–23% for Finale and MuseScore. Onset placement is still wrong for about 15% of notes on expressive classical playing. Models that receive beat information up front (Wachter et al. 2025–26) reach about 97% onset F1. That strongly supports recording to a metronome.

### Cited Findings
**PM2S, Liu et al., ISMIR 2022 (CRNN plus neural beat tracking)**
- Beat-level F-measure (±70 ms): baseline audio-style beat tracker on pianoroll fb 66.9 / downbeat 57.6. PM2S fb 85.7 / fdb 63.3. With joint tempo output, fb 86.2 / fdb 69.8 — [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf)
- MV2H on PM2S conversion (Fp / Fvo / Fme / Fva / Fha / overall F) — [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf):
  - Finale v27: 82.2 / 54.6 / 9.9 / 92.2 / 86.2 / 65.0
  - MuseScore v3: 10.0 / 65.0 / 15.3 / 95.0 / 84.5 / 54.0
  - PM2S: 99.8 / 87.0 / 61.7 / 99.9 / 91.1 / 87.9
- Code: github.com/cheriell/PM2S. MIT license, Python 3.8 / PyTorch 1.12, pre-trained model with a demo notebook, about 87 stars, no releases. It outputs a MIDI score, not MusicXML — [GitHub PM2S](https://github.com/cheriell/PM2S); [ISMIR 2022 paper](https://archives.ismir.net/ismir2022/paper/000047.pdf)
- Beyer & Dai note that PM2S "assumes overly regular performance data and struggles with real recordings" — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1)

**Beyer & Dai, "End-to-end Piano Performance-MIDI to Score Conversion with Transformers", ISMIR 2024 (TU Munich)**
- Seq2seq RoFormer encoder–decoder, 4+4 layers, 8 heads, d=512, FFN 3072 (SwiGLU). It uses compound tokens that quantize continuous values. Trained on ASAP (822 train / 86 val / 59 test performances) plus 58,646 unpaired public-domain MuseScore MusicXML files — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1)
- MUSTER results on the ASAP test set (lower is better). Columns are E_p / E_miss / E_extra / E_onset / E_offset / E_avg — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1):
  - Neural Beat Tracking (PM2S, improved): 2.02 / 6.81 / 9.01 / 68.28 / 54.11 / 28.04
  - MuseScore: 2.41 / 7.35 / 9.64 / 47.90 / 49.44 / 23.35
  - Finale: 2.47 / 10.10 / 13.46 / 31.85 / 45.34 / 20.64
  - HMMs + heuristics (Nakamura/Shibata, classical model)†: 2.11 / 6.47 / 8.75 / 22.58 / 29.84 / 13.95
  - Beyer & Dai: 3.11 / 7.56 / 6.44 / **15.55** / **23.84** / **11.30**
  - † flagged by the authors as "slightly optimistic": some test pieces were in the HMM pipeline's training data.
- ScoreSimilarity staff-assignment error: Beyer & Dai 6.62%, PM2S 6.86%, MuseScore 21.87%, Finale 21.79%. Spelling error: 8.69% (Beyer & Dai), 9.69% (MuseScore), 15.34% (Finale). Duration error stays above 50% for every system — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1)
- Limitations: no key or time signature output. Trained on classical European piano. Generalisation to pop piano is only "preliminary". The ISMIR reviewers note ASAP is the only public paired performance-MIDI/MusicXML dataset — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1); [ISMIR 2024 poster page](https://ismir2024program.ismir.net/poster_158.html)
- Code: github.com/TimFelixBeyer/MIDI2ScoreTransformer, checkpoint `MIDI2ScoreTF.ckpt`. **No license stated** in the repo. It needs Python 3.11, a MuseScore install, and custom forks of music21, score_transformer and muster. Training instructions are incomplete ("More instructions to follow") — [GitHub MIDI2ScoreTransformer](https://github.com/TimFelixBeyer/MIDI2ScoreTransformer)

**Wachter, Murgul & Heizmann (2025–2026): transformer rhythm quantization using beat annotations**
- arXiv 2508.19262 (Aug 2025, AES AIMLA 2025 late-breaking demo): a transformer that takes beat and downbeat information and outputs metrically aligned scores. Trained on piano and guitar, it claims state-of-the-art MUSTER, but the abstract gives no numbers — [arXiv 2508.19262](https://arxiv.org/abs/2508.19262)
- arXiv 2604.22290 (Apr 2026, ICSM 2025): uses "a priori beat information" plus beat-based pre-quantization. On ASAP it reports **onset F1 97.3%** and **note-value accuracy 83.3%**. Code is not stated. Sebastian Murgul is the Klangio founder per Product Hunt, so this is probably Klangio-related research — [arXiv 2604.22290](https://arxiv.org/abs/2604.22290); [Product Hunt Klangio](https://www.producthunt.com/posts/941683)

**Nakamura, Yoshii, Sagayama and Shibata et al. (HMM pipelines)**
- Nakamura et al. (2017) "Rhythm Transcription of Polyphonic Piano Music Based on Merged-Output HMM for Multiple Voices": beats other methods by more than 12 points on polyrhythmic performances and is nearly equal to the best on non-polyrhythmic pieces (classical piano MIDI) — [DeepAI listing](https://api.deepai.org/publication/rhythm-transcription-of-polyphonic-piano-music-based-on-merged-output-hmm-for-multiple-voices)
- In the Nakamura line of work, a merged-output HMM handles staff placement and multi-voice rhythm quantization, with Markov random fields for note values. Shibata et al. add hand-crafted non-local statistics to estimate tempo and time signature. The pipelines are not trained end-to-end — [arXiv 2410.00210 related work](https://arxiv.org/html/2410.00210v1)
- A Sept 2026 re-implementation (the original code "is not publicly available") measured merged-output HMM hand separation at 67.4% mean accuracy on the PIG fingering dataset, taking about 498 s per piece. The same paper's "Synthesis" model reached 90.8% hand-separation accuracy — [Penner & Hindle, arXiv 2609.28787](https://arxiv.org/abs/2609.28787)

**Cogliati, Temperley, Duan (ISMIR 2016)**
- HMM-based meter estimation, then beat-snapping heuristics to quantize, with LilyPond output. Evaluated subjectively by five music-theory students, so there are no comparable numbers — [arXiv 2410.00210 related work](https://arxiv.org/html/2410.00210v1); [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf)

**Voice and staff separation (input already quantized)**
- Karystinaios & Widmer, "Cluster and Separate" GNN (2024). Staff accuracy on J-Pop / DCML: pitch-split baseline (below C4 goes to the lower staff) 89.9 / 80.7, Shibata et al. 92.8 / 88.5, GNN 96.3 / 91.0. Voice F1: baseline 85.4 / 78.2, Shibata 92.2 / 84.9, GNN 96.6 / 89.9. Code and pretrained models are at github.com/CPJKU/piano_svsep (license not checked) — [arXiv 2407.21030](https://arxiv.org/html/2407.21030v1)
- Hadjakos, Waloschek & Leemhuis (2019): an RNN assigns played MIDI notes to hands and beats an existing heuristic. An offline variant is slightly better than the real-time one. The abstract gives no numbers — [GI digital library](https://dl.gi.de/items/969b1f5c-6eb0-4761-a35c-ac1b067c4991/full)
- Suzuki's Score Transformer (2021) turns *quantized* note-level MIDI into notation (staff assignment, key estimation, voice segregation) — [arXiv 2112.00355](https://arxiv.org/pdf/2112.00355)

### Inferences
- Research numbers come from ASAP: expert classical performances with heavy rubato and no click. An amateur playing pop or chord-based material to a metronome is a much easier input on the rhythm axis, so real-world results with a click should be well above the ASAP onset figures. Wachter et al.'s 97.3% onset F1 with known beats is the closest proxy, but it is not proof for this use case.
- None of the research systems is a drop-in for a Dart app. They are all Python/PyTorch. Beyer & Dai has no license, and the HMM code is not public. PM2S (MIT, a small CRNN) is the only one with a clear license that could run on a server. Porting it on-device would mean ONNX/TFLite export plus porting its post-processing.

### Gaps
- Model parameter counts and on-device inference cost were not found for PM2S or Beyer & Dai.
- No independent 2025–2026 benchmark comparing these systems on non-classical, amateur, or metronome-aligned playing was found.
- No ISMIR 2025 paper on full PM2S was found in the program search.

## 3. What commercial/consumer products do, and what users complain about

### Takeaway
Notation programs (MuseScore, Finale, Dorico, Logic/Cubase score views) import MIDI with grid quantization, plus options for voices, tuplets and splitting the staff by pitch. On real performances they produce cluttered scores: ties, stray rests, clef jumping, and drift when the tempo was not constant. Audio-first "AI" apps (Klangio Piano2Notes, Melody Scanner, AnthemScore) get mixed reviews, with hand assignment and rhythm as the usual complaints. ScoreCloud is the consumer product most focused on live MIDI keyboard input.

### Cited Findings
- **MuseScore MIDI import panel options**:
  - **Quantization**: "Value from preferences" or quarter to 128th; the grid adapts to note length, capped by the maximum.
  - **Max. voices**.
  - **Search tuplets**.
  - **Is human performance**: favours readability over conversion accuracy, and uses automatic beat tracking to find bar positions in unaligned files.
  - **2x less measure count**; a manually set **time signature** for unaligned files.
  - **Split staff**: piano left/right hand by "constant or floating pitch separation".
  - **Clef changes**: based on average chord pitch.
  - **Simplify durations**; **Show staccato**; **Dotted notes** vs ties; **Recognize pickup measure**.
  - **Detect swing**: 2:1 and 3:1 patterns become straight eighths plus "Swing"/"Shuffle" text.
  - The settings cannot be re-applied after the score has been edited.
  — [MuseScore Handbook 3: MIDI import](https://musescore.org/en/handbook/3/midi-import)
- MuseScore 4 has a preference for "the shortest note value used in imported MIDI files" — [MuseScore 4 handbook (convert a file)](https://handbook.musescore.org/file-management/convert-a-file.md)
- Benchmarks: MuseScore v3 MV2H overall 54.0 and Finale v27 65.0, against PM2S 87.9. Metrical alignment Fme is 15.3 (MuseScore) and 9.9 (Finale) — [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf). On MUSTER, the onset error is 47.9% (MuseScore 4) and 31.9% (Finale), with staff error about 22% for both — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1)
- MuseScore user complaints span MuseScore 2 to 4, so some may be outdated:
  - unquantized recordings reproduce the "mathematical truthness" of the performance;
  - "loads of annoying ties";
  - rests for gaps that were not in the sequencer;
  - dotted notes imported as tied notes;
  - piano notation jumping between treble and bass clefs on one staff, or a single treble staff instead of a grand staff.
  Users suggest quantizing in a DAW before import, or using MusicXML — [MuseScore forum: MIDI import interpretation](https://musescore.org/en/node/24960); [6 MIDI import issues](https://musescore.org/en/node/1353); [Cleaning up MIDI imports](https://musescore.org/comment/697211); [Notes moved to other clef](https://musescore.org/en/node/324012); [MIDI ticks per beat problem](https://musescore.org/en/node/318640)
- Dorico has a "MIDI Quantize Options" dialog with a quantization unit setting — [Steinberg Dorico help](https://steinberg.help/dorico/v2/en/dorico/topics/project_file_handling/project_file_handling_midi_quantize_options_dialog_r.html)
- **ScoreCloud (Doremir)**:
  - Reviewers say live MIDI keyboard input is where it is strongest.
  - Sound on Sound's 2012 review of its predecessor ScoreCleaner found freely played MIDI turned into a score that was "in most cases, very nearly spot-on", and the product aimed at "intelligent handling of multi-voice contrapuntal and keyboard-based textures".
  - Polyphonic transcription from an instrument arrived in ScoreCloud 4 (2018).
  No quantitative accuracy figures were found — [Sound on Sound ScoreCleaner review](https://www.soundonsound.com/reviews/doremir-scorecleaner); [Sonicstate, ScoreCloud 4](https://www.sonicstate.com/news/2018/04/13/scorecloud-4-makes-music-notation-easier/); [Songscription vs ScoreCloud (competitor blog)](https://www.songscription.ai/blog/songscription-vs-scorecloud)
- **Klangio Piano2Notes** (audio-first) user reports:
  - "fixing a transcription full of mistakes is probably harder than starting from scratch";
  - basic time signatures wrong;
  - fine as a starting point but not professional;
  - a MuseHub reviewer said notes were accurate but it "didn't identify which hand played which notes" and had rhythm trouble.
  Positive reviews exist too, and no independent benchmark was found — [Trustpilot klang.io](https://uk.trustpilot.com/review/klang.io); [MuseHub Piano2Notes](https://musehub.com/app/piano2notes); [Google Play](https://play.google.com/store/apps/details?id=com.piano2notes)

### Inferences
- Most of the commercial failure modes trace to one global tempo plus a fixed grid. A tempo-locked recording (metronome) removes the root cause of the drift. The remaining issues (ties, rests, clef jumps) can be fixed with notation-level post-processing: duration simplification, staff assignment with hysteresis, and voice handling.

### Gaps
- No primary sources were gathered for Logic Pro / Cubase score-editor quantization, AnthemScore, or Melody Scanner (outside the 15-call budget). Their behaviour is not documented here.
- No measured accuracy of ScoreCloud or Klangio on MIDI input was found. All quality evidence is anecdotal.

## 4. Practical, robust strategies for an app (and how much each buys)

### Takeaway
The biggest simplification is a count-in and metronome at a user-chosen tempo and time signature. That removes beat tracking and downbeat detection, the step responsible for most research and commercial errors (MV2H Fme 10–62, MUSTER onset error 15–48%). After that, grid quantization with adaptive resolution and limited triplet detection, onset clustering for chords, split-point or pitch-based hand assignment, and key-based spelling give a usable first draft. Every estimate should be correctable in an editor.

### Cited Findings
- Beat-tracking errors (double/half tempo, missing or extra beats) are the main source of rhythm failure in PM2S — [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf). MuseScore and Finale's constant-tempo estimate causes time shifts and low metrical accuracy — [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf)
- When beats are known in advance, a transformer quantizer reaches 97.3% onset F1 and 83.3% note-value accuracy on ASAP — [arXiv 2604.22290](https://arxiv.org/abs/2604.22290). Note values are clearly harder than onsets even with beats known.
- Grid quantization: music21's `Stream.quantize(quarterLengthDivisors=(4,3), processOffsets=True, processDurations=True, inPlace=False, recurse=False)` snaps to the nearest multiple of 1/4 or 1/3 quarter (16ths or eighth-note triplets, whichever is closer). Since v7, duration processing looks at the next note's quantized offset to avoid unnecessary gaps — [music21 Stream docs](https://www.music21.org/music21docs/moduleReference/moduleStreamBase.html). Divisors (4, 12) are another documented option — [velog music21 quantization post](https://velog.io/@clayryu328/Music211-Quantization)
- MuseScore uses an adaptive grid (longer notes get coarser quantization, up to a max), optional tuplet search, and duration simplification — [MuseScore Handbook 3](https://musescore.org/en/handbook/3/midi-import)
- Hand and staff split: a fixed split at C4 already gives 89.9% staff accuracy on pop (J-Pop) and 80.7% on Romantic classical (DCML), against 96.3 / 91.0 for a trained GNN — [arXiv 2407.21030](https://arxiv.org/html/2407.21030v1). MuseScore offers "constant or floating pitch separation" — [MuseScore Handbook 3](https://musescore.org/en/handbook/3/midi-import). Learned hand detection (RNN) beats heuristics — [Hadjakos et al. 2019](https://dl.gi.de/items/969b1f5c-6eb0-4761-a35c-ac1b067c4991/full). A rule and statistics "Synthesis" model reached 90.8% hand accuracy on PIG — [arXiv 2609.28787](https://arxiv.org/abs/2609.28787)
- Chord grouping: treating notes with the same onset and duration as one chord in a voice is how partitura's `estimate_voices(monophonic_voices=False)` works. It is based on Chew & Wu's contig-mapping voice separation — [partitura musicanalysis docs](https://partitura.readthedocs.io/en/latest/modules/partitura.musicanalysis.html)
- `makeNotation` (music21) does the notation clean-up after quantizing: voices for overlaps, measures, ties, beams, accidentals and tuplet brackets — [music21 Stream docs](https://www.music21.org/music21docs/moduleReference/moduleStreamBase.html)

### Inferences (design proposals, not benchmarked)
- **Metronome and count-in, with fixed tempo and time signature.** This removes beat, downbeat, tempo and meter estimation entirely. Bar lines become exact, and the main remaining error is the player's own timing jitter relative to the grid size. It is the most valuable single simplification. Optional extension: allow a "free" mode that runs offline beat tracking (PM2S on a server) for rubato playing.
- **Latency compensation.** Measure USB MIDI and metronome output latency once (tap-along calibration) and shift onsets before quantizing. Otherwise everything lands systematically late or early.
- **Grid quantization.** Let the user choose the finest value (8th, 16th, 32nd) and whether triplets are allowed. Quantize onsets first (nearest grid point, with an adaptive grid: a 16th grid only where onsets are dense). Then set each written duration to the gap until the next onset in the same voice, capped by the actual release snapped to the grid. Only allow triplet grids per beat when ≥2 onsets in that beat fit the triplet grid better by a margin, so as not to over-detect tuplets.
- **Clean-up.** Drop notes shorter than about 30–50 ms or with very low velocity (accidental grazes). Merge near-simultaneous onsets (within about 30–60 ms, or within the same grid cell) into chords. Treat onsets spread over less than about 80 ms as an arpeggio, or a chord with an arpeggio sign. These thresholds need on-device tuning.
- **Sustain pedal.** Do not use pedal-extended length as written duration. Record CC64 down/up as pedal marks. Use the key release (note-off) for written length, clipped at the next onset in the same hand/voice.
- **Hands.** Start with a split point (default C4 or the middle of the played range), plus hysteresis and chord-span constraints: one hand cannot span more than about a 10th, and notes in one onset cluster above and below the split stay together if they fit within one hand's span. Also allow a "one hand per staff" pre-declaration, e.g. "left hand plays chords". Research suggests a simple split gives about 80–90% staff accuracy, and smarter heuristics or ML 90–96%.
- **Voices.** Start with one voice per staff (chords allowed). Add a second voice only when a sustained note overlaps later onsets in the same staff. That avoids MuseScore-style tie and rest clutter.
- **Grace notes and ornaments.** Detect very short notes (< 1/3 of the grid unit) immediately before a main note as grace notes. Research F1 for grace notes is only about 28% even for the best model, so default to dropping or merging them, with an editor option.
- **Editing.** Keep the raw performance (onsets in ms, velocities, pedal) alongside the derived score, so the user can re-quantize with different settings. MuseScore's inability to re-apply import settings after editing is a known pain point.

### Gaps
- No published measurement was found of accuracy for amateur playing against a metronome with plain grid quantization. The benefit of the metronome is inferred from the error analyses above, not measured directly.
- The thresholds above (ms values, spans) are engineering defaults, not sourced values.

## 5. Pitch spelling and key estimation

### Takeaway
Pitch spelling is largely solved for tonal music: 99.4% (ps13) to 99.9% (PKSpell) of notes spelled correctly on the MuseData corpus, falling to about 96.5% on harder ASAP piano data. A simple scheme (estimate the key with Krumhansl–Schmuckler, spell diatonic notes from the key, choose sharps or flats for chromatic notes by direction and context) is easy to implement in Dart. ps13 is the best-documented classical algorithm to port.

### Cited Findings
- Reported pitch-spelling accuracy on MuseData: ps13 99.41%, CIV (Teodoru & Raphael) 99.82%, PKSpell 99.87%. PKSpell drops to 96.50% on the ASAP piano dataset — [Engraving-oriented joint estimation of pitch spelling and keys, arXiv 2402.10247](https://arxiv.org/pdf/2402.10247)
- The PKSpell paper (Foscarin et al., data-driven pitch spelling and key signature) reports 256 errors, against 343 for CIV and 1064 for ps13 in its setup. The papers' setups differ, so the comparison is approximate — [PKSpell, arXiv 2107.14009](https://arxiv.org/pdf/2107.14009)
- Meredith's ps1303 spelled 99.43% of notes correctly on an eight-composer corpus. The reference is Meredith (2006), "The ps13 Pitch Spelling Algorithm", JNMR 35(2) — [Bohrium summary of ps13](https://www.bohrium.com/paper-details/the-ps13-pitch-spelling-algorithm/812063736708726784-2787); [partitura docs](https://partitura.readthedocs.io/en/latest/modules/partitura.musicanalysis.html)
- Comparative study: "Comparing pitch spelling algorithms" (Meredith & Wiggins), which covers Cambouropoulos, Temperley, Longuet-Higgins, Chew & Chen and ps13 — [AAU record](https://vbn.aau.dk/da/publications/comparing-pitch-spelling-algorithms-2)
- In end-to-end PM2S, spelling error per ScoreSimilarity is 8.69% (Beyer & Dai), 9.69% (MuseScore) and 15.34% (Finale) — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1)
- Partitura's `estimate_key` uses Krumhansl key profiles (refs: Krumhansl 1990; Temperley 1999, "What's key for key? The Krumhansl-Schmuckler key-finding algorithm reconsidered"). `estimate_spelling` implements ps13 (method 'ps13s1') and returns step/alter/octave — [partitura musicanalysis docs](https://partitura.readthedocs.io/en/latest/modules/partitura.musicanalysis.html)
- PM2S predicts key signature per note as one of 12 classes, so it covers major/relative-minor key signatures, not mode — [PM2S paper](https://archives.ismir.net/ismir2022/paper/000047.pdf)

### Inferences
- In Dart, a Krumhansl–Schmuckler correlation over duration-weighted pitch-class histograms (12 major + 12 minor profiles), computed over a sliding window, gives the key signature and local modulations. Spelling by "nearest on the line of fifths to the current key centre" (essentially the core idea of ps13 and Temperley's line-of-fifths approach) is about 50–150 lines of code. The app already detects chords, so chord roots can also inform spelling (e.g. spell the third of a detected E major chord as G♯, not A♭).
- The user should be able to override the key and respell individual notes (enharmonic toggle).

### Gaps
- No Dart or JS implementation of ps13 or PKSpell was found. Porting is required.

## 6. Data formats and libraries

### Takeaway
MusicXML is the right interchange and editable format: MuseScore, Finale, Dorico and Sibelius all read it, and the Verovio engine renders it. Python has mature toolkits (music21, partitura) for a server path. In Dart, the realistic stack is your own quantization and notation logic, MusicXML written by hand or with `music_xml` (parse/serialize), and `verovio_flutter` (LGPL-3.0) or `flutter_notemus` for rendering.

### Cited Findings
- **music21** (Python): `converter.parse(..., format='midi', quantizePost=True, quarterLengthDivisors=(4,12))`; `Stream.quantize`; `Stream.makeNotation` (voices for overlaps, measures, ties, beams, accidentals, tuplet brackets; `useKeySignature=True`); MusicXML export — [music21 Stream docs](https://www.music21.org/music21docs/moduleReference/moduleStreamBase.html); [velog quantization post](https://velog.io/@clayryu328/Music211-Quantization)
- **partitura** (Python, v1.9.0): `estimate_spelling` (ps13), `estimate_key` (Krumhansl), `estimate_voices` (Chew & Wu), `estimate_time` (tempo, meter numerator, beats), `estimate_tonaltension`, plus performance/score alignment ("match files") — [partitura docs](https://partitura.readthedocs.io/en/latest/); [partitura musicanalysis](https://partitura.readthedocs.io/en/latest/modules/partitura.musicanalysis.html)
- **PM2S** (MIT) outputs a MIDI score. Beyer & Dai depend on MuseScore and music21 forks for score output, with no license — [GitHub PM2S](https://github.com/cheriell/PM2S); [GitHub MIDI2ScoreTransformer](https://github.com/TimFelixBeyer/MIDI2ScoreTransformer)
- **CPJKU piano_svsep** (GNN voice and staff separation for quantized MIDI; code and pretrained models) — [arXiv 2407.21030](https://arxiv.org/html/2407.21030v1)
- **verovio_flutter 0.3.3** (pub.dev, verified publisher, LGPL-3.0): Flutter FFI plugin embedding Verovio 6.2.x. Android API 21+, iOS 13+, Web via WASM. Inputs are MEI, MusicXML, Humdrum, ABC and Plaine & Easie; output is SVG. Also hit-testing, MIDI export, a time map, and rendering on a worker isolate. Small user base (2 likes, 244 downloads) — [pub.dev verovio_flutter](https://pub.dev/packages/verovio_flutter)
- **music_xml** (pub.dev): parses and serializes MusicXML 4.0, both .xml and compressed .mxl. Parser only, not a renderer — [pub.dev music_xml docs](https://pub.dev/documentation/music_xml/2.9.0/)
- **flutter_notemus**: SMuFL-compliant notation renderer with MusicXML import (completeness unverified). **simple_sheet_music**: MIDI/MusicXML import with limited features — [pub.dev flutter_notemus](https://pub.dev/documentation/flutter_notemus/latest/); [pub.dev simple_sheet_music](https://pub.dev/packages/simple_sheet_music/score)
- MuseScore users report MusicXML imports more cleanly than MIDI — [MuseScore forum](https://musescore.org/en/node/24960)

### Inferences
- Suggested architecture:
  - **(a) On-device (Dart):** record the raw events, quantize to the metronome grid, form chords, split hands, choose voices, estimate key and spelling. Build an internal score model and serialize it to MusicXML (two staves in one `<part>` with `<staves>2</staves>`, `<staff>` per note, `<backup>` between staves, `<key>`, `<time>`, `<tie>`, `<pedal>`, `<dynamics>`). Render with Verovio, and keep the raw performance for re-quantizing.
  - **(b) Optional server for "free tempo" recordings:** a Python service running PM2S (MIT) or partitura plus music21 that returns MusicXML.
- LGPL-3.0 for verovio_flutter requires allowing relinking or replacement of the library. A dynamically linked FFI plugin generally complies, but the license obligations should be checked before shipping, especially on iOS. This is not legal advice and was not verified here.

### Gaps
- The `music_xml` package's license, maintenance status and write support were not verified in detail.
- No Dart library was found that does MIDI quantization or score "makeNotation"-style clean-up. That logic has to be written by hand.
