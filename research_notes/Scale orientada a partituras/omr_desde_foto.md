# Optical Music Recognition (OMR) from photos and screenshots: state as of November 2026

Scope: turning a photo or screenshot of printed or handwritten sheet music into an editable score (MusicXML) for Scale, a Flutter app on Android and Windows that already uses Claude vision for chord charts. Research date: 2026-11-08. About 20 searches and fetches. Product and vendor pages are labelled as vendor claims. Independent evaluations are labelled as independent.

## 1. Open-source OMR engines and research models (Audiveris, oemer, homr, SMT, LEGATO and others)

### Takeaway
The open-source options all carry licensing or quality caveats. homr (AGPL-3.0) is the most practical open engine for camera photos. It supports grand staff and multiple voices, but it drops beams, octave lines and dynamics, and its released weights were trained partly on non-commercial data. Audiveris (AGPL-3.0, v5.11 July 2026) is mature and Java-based, but it is best on clean scans, does not support handwriting, and is better treated as a desktop or server tool. SMT/SMT++ (MIT) is the main permissively licensed research model for piano (grand staff). LEGATO (ICLR 2026) and LEGATO 2 (July 2026) are the new state of the art in research, and I could not confirm that their code or weights have been released.

### Cited Findings
**Audiveris**
- Release history: 5.4 (Feb 2025) added MusicXML 4.0 export (earlier 5.x wrote MusicXML 3.0). 5.5 (Apr 2025) started shipping installers for the main operating systems with a bundled Java runtime. 5.7 (Sep 2025) moved to Java 24. — [Audiveris updates (search summary)](https://audiveris.github.io/audiveris/_pages/reference/updates)
- 5.8 (Nov 2025): Java 25 and Gradle 9.1, key-signature changes, and reworked annotations for training an external model. 5.9 (Dec 2025): parallel processing of systems and swapping sheets to disk. 5.10 (Mar 2026): rehearsal marks, more clefs, and Windows packaging on Scoop Extras. 5.11 (Jul 2026): L2 regularization added to the glyph classifier, plus a fix for exporting imperfect scans. No 6.x release exists. — [Audiveris software updates](https://audiveris.github.io/audiveris/_pages/reference/updates)
- A third-party page mentions a "5.10.2 with neural-network classifiers". This is not confirmed by the project's own pages. — [search summary of Audiveris pages](https://audiveris.github.io/audiveris/_pages/reference/updates)
- Handbook (for 5.11 and later): "Handwritten scores aren't supported (only printed scores are)". Only common Western notation and common symbols are handled. Accuracy is imperfect, so a GUI is provided for verification and correction. A CLI with batch mode exists. License is AGPL v3. — [Audiveris Handbook](https://audiveris.github.io/audiveris/_pages/handbook)
- Also distributed on Flathub for Linux. — [Flathub](https://flathub.org/apps/org.audiveris.audiveris)

**oemer**
- oemer is an end-to-end deep-learning OMR system that outputs MusicXML. The README says it is "able to transcribe on skewed and phone taken photos". It probably will not work on handwriting. License is MIT. It uses ONNX Runtime by default, with TensorFlow optional. A GPU run "usually takes around 3~5 minutes", and the first run downloads checkpoints. The citation refers to v0.1.7 (Oct 2023). The README itself recommends homr as an improved successor. — [BreezeWhite/oemer](https://github.com/BreezeWhite/oemer)
- The last push to the repository was on 18 Apr 2025, according to an aggregator. — [gittrend](https://gittrend.io/repo/BreezeWhite/oemer)
- MusiXQA measured oemer at about 62 s per page and reported that it omits accidentals (independent academic observation). — [MusiXQA arXiv 2506.23009](https://arxiv.org/html/2506.23009v1)

**homr**
- homr converts camera pictures or PDFs to MusicXML. It uses UNet segmentation (taken from oemer) to find staff lines, note heads and stems, dewarps each staff, and then runs a transformer based on Polyphonic-TrOMR to read the symbols. It supports grand staff (piano, organ) and multiple voices per staff. It does NOT read octave lines, octave clefs, beams or glissandos, and it focuses on pitch and rhythm, leaving out dynamics and articulation. It requires Python 3.11/3.12. It has a CPU install option (`homr[cpu]`) and optional CUDA 12.1 or ROCm. There is an online demo (homr.site), a Colab notebook, and a third-party Android app called "Andromr" that uses homr. — [liebharc/homr](https://github.com/liebharc/homr)
- Licensing: both the code and the weights are AGPL-3.0, and no commercial license is offered because there are many contributors. All released transformer checkpoints include Camera-PrIMuS data, which the Hugging Face copy lists as CC BY-NC 4.0 (non-commercial). Other training data: DeepScoresV2 (CC BY 4.0), OpenScore Lieder/StringQuartets (CC0), GrandStaff (license unclear; the Hugging Face copy says MIT), and PDMX (CC BY 4.0). The project suggests running homr as a separate process or Docker container to keep a cleaner AGPL boundary. Title OCR uses RapidOCR. — [homr LICENSE_FAQ](https://github.com/liebharc/homr/blob/main/LICENSE_FAQ.md)
- The TrOMR paper (NetEase, ICASSP 2023) introduced the transformer that homr adapts. — [TrOMR arXiv 2308.09370](https://arxiv.org/abs/2308.09370)

**SMT / SMT++ (Sheet Music Transformer, Universidad de Alicante / PRAIG)**
- SMT uses a ConvNeXt encoder and a Transformer decoder and loads through Hugging Face Transformers (`SMTModelForCausalLM`). Checkpoints include `antoniorv6/smt-grandstaff` and `antoniorv6/smt-camera-grandstaff` (pianoform, camera-distorted). The model card license is MIT. — [HF smt-camera-grandstaff](https://huggingface.co/antoniorv6/smt-camera-grandstaff/blob/main/README.md); [HF smt-grandstaff](https://huggingface.co/antoniorv6/smt-grandstaff)
- SMT++ (full-page pianoform, no layout-analysis step) is in a separate repository, fp-smt. — [antoniorv6/fp-smt](https://github.com/antoniorv6/fp-smt); [arXiv 2405.12105](https://arxiv.org/abs/2405.12105v1); original SMT paper [arXiv 2402.07596](https://arxiv.org/abs/2402.07596)
- The output is **kern (Humdrum), not MusicXML. A conversion step (for example music21 or verovio) would be needed. [Inference: the **kern output is stated in the SMB paper context below. I did not separately verify the converter tooling.]

**LEGATO (ICLR 2026) and LEGATO 2 (Jul 2026)**
- LEGATO by Yang, Ebert, Tamer, Zheng, Pozzobon and Smith (UW/AI2) pairs a pretrained vision encoder with an ABC-notation decoder, trained on more than 214K images. It was accepted at ICLR 2026. On the most realistic dataset it reports absolute error reductions of 68.2% (TEDn) and 48.1% (OMR-NED) over the previous state of the art. The abstract page gives no code or weights license. — [arXiv 2506.19065](https://arxiv.org/abs/2506.19065)
- LEGATO 2 (submitted 7 Jul 2026): segments the page into systems and then runs an autoregressive vision-language model on each system. It also transcribes titles and annotations, and claims to "consistently outperform prior state of the art". The abstract says symbolic transcriptions help "frontier language models" understand dense scores. The abstract gives no numbers and no confirmed code or weights. — [arXiv 2607.05769](https://arxiv.org/abs/2607.05769)

**Other open or academic items**
- copisteria (copista-28m) and transcoda appear as comparison systems in homr's benchmark. homr's author says copisteria currently outscores homr. — [homr Benchmark.md](https://github.com/liebharc/homr/blob/main/Benchmark.md)
- The notes2tone repository (`dasrinkana/notes2tone`) is described as the only known public benchmark comparing homr, oemer and Audiveris on a small set of scores. — [homr Benchmark.md](https://github.com/liebharc/homr/blob/main/Benchmark.md)
- ReadScoreLib (SeeScore/Dolphin) is a cross-platform commercial OMR library that outputs MIDI and MusicXML. It is the engine family behind PlayScore. — [seescore.co.uk](https://www.seescore.co.uk/?p=6)

### Inferences
- For a commercial app, homr's AGPL license plus non-commercial training data (PrIMuS) makes shipping it inside the app risky. Running it as a separate server-side process is the pattern its own FAQ suggests, and it still carries the training-data question.
- Running any of these engines on-device in Flutter is not realistic in 2026. Audiveris needs a Java runtime, oemer and homr are Python, ONNX or PyTorch pipelines that take minutes per page, and SMT is a large transformer. The existing Andromr app suggests homr on Android is technically possible, though I did not verify how it runs (on-device or remote).
- SMT/SMT++ (MIT) is the cleanest license choice for a self-hosted piano model. It would need **kern-to-MusicXML conversion and probably fine-tuning for real phone photos.

### Gaps
- I did not find an official accuracy number for Audiveris on phone photos, or its input requirements (DPI, interline). The handbook page does not state them.
- I could not confirm whether LEGATO or LEGATO 2 code or weights are public, or under what license.
- I did not research "Zeus" or OLiMPiC (the OLiMPiC pianoform dataset) in detail. No information was gathered on them.
- I did not verify whether Andromr runs homr on-device.

## 2. Commercial products and developer APIs

### Takeaway
I found one hosted OMR REST API aimed at developers: Flat's (Tutteo) OMR API. It costs 1 credit per page, accepts photos, PDFs and HEIC, outputs MusicXML or MIDI, does not handle handwriting, takes about 30–60 s per page, and lets you deliver the output to your own customers. The consumer apps (Soundslice, PlayScore 2, Newzik, ScanScore, SmartScore, Sheet Music Scanner) have no public scanning API. Soundslice and Newzik did best in the most recent independent review I found (Dec 2024), and PlayScore 2 was perfect on a piano piece.

### Cited Findings
**Flat OMR API (vendor documentation)**
- Converts a PDF or photo into a Flat score, MusicXML or MIDI using Tutteo's in-house deep-learning model. The vendor says the model reads rhythm, pitch and layout jointly and separates instruments, voices, lyrics and chords. Inputs: PDF, JPEG, PNG, WebP, TIFF, GIF, AVIF, HEIC and HEIF. Limits are 50 pages per job and 100 MiB per file. "Handwritten music and tablature are not supported." — [Flat OMR API](https://flat.io/developers/docs/api/omr/)
- Pricing: 1 credit per page, drawn from a Flat subscription's allowance or from one-off credit packs of up to 3,000 credits, with volume discounts and custom contracts. Packs don't expire. Usage-based billing is "planned". Prices per pack were not visible on the page. — [Flat OMR API](https://flat.io/developers/docs/api/omr/)
- Latency is about 30 s for a single page, sometimes up to about 1 min per page. Recommended flow is "Interactive Jobs": create a job, add pages one at a time (aimed at mobile capture), an optional details step, long-polling, then export MusicXML. There is also a simpler two-call flow. Credits are refunded on error. — [Flat OMR API](https://flat.io/developers/docs/api/omr/)
- Legal: you may process scores uploaded by customers who hold the rights and deliver the MusicXML/MIDI outside Flat. Files are kept for 30 days by default and are not used for training. — [Flat OMR FAQ legal](https://flat.io/developers/docs/api/omr/faq/legal); [OMR FAQ](https://flat.io/developers/docs/api/omr/faq/)

**Soundslice scanner (vendor page, Nov 2026)**
- Accepts JPG, PNG, GIF, BMP, PDF, HEIC, TIFF and WEBP, including non-vector PDFs and photos. Handwriting: "Maybe", and it "works best for published (engraved) music". Exports MusicXML and MIDI, with a built-in correction editor. When unsure it asks the user rather than guessing. Takes about 1 min per page. Free plan: 2 scans per month (1 page and 32 bars each). Plus: 100 pages per month. Teacher and Licensing: 200 pages per month. No scanning API is listed; the Licensing plan is for embedding the player. — [Soundslice sheet music scanner](https://www.soundslice.com/sheet-music-scanner/)

**Independent review: Scoring Notes, "Scanning the current OMR landscape" (Steve Morell, 10 Dec 2024)**
- Tested Newzik, Soundslice, PlayScore 2, Sheet Music Scanner, SmartScore Pro 64 NE and ScanScore Professional 3. Inputs were iPhone 15 photos of printed pages and Sibelius-exported PDFs, and output was judged by importing the MusicXML into Sibelius. — [Scoring Notes](https://www.scoringnotes.com/reviews/scanning-the-current-omr-landscape/)
- Results: on Beethoven's "Moonlight" piano score, PlayScore 2 got all notes 100% correct. ScanScore could not infer triplets and did not build a single piano staff. On the Eroica trumpet part (650+ measures), Soundslice had 1 wrong note or rhythm and Newzik accounted for every measure but missed some dynamics, rehearsal marks and endings. On the Nutcracker full score, Sheet Music Scanner needed about 10–20% of measures re-entered and SmartScore about 20–30%. The Soundslice and PlayScore phone-photo scans of the full score were "unusable" at default settings. — [Scoring Notes](https://www.scoringnotes.com/reviews/scanning-the-current-omr-landscape/)
- Prices in the review (Dec 2024): Newzik $49.99/yr or $149.99 lifetime. Soundslice Plus $5/mo or $50/yr for 100 pages/month. PlayScore 2 Professional $6.99/mo or $49.99/yr. Sheet Music Scanner $4.49 one-time on Android, $4.99/mo or $22.99/yr on iOS. SmartScore Pro 64 NE $399. ScanScore Professional $79/yr. PhotoScore/NotateMe Ultimate 2020 was excluded because it had not been updated since 2021. Musitek's president disputed the method in the comments, saying SmartScore's MusicXML is near-perfect in Finale. — [Scoring Notes](https://www.scoringnotes.com/reviews/scanning-the-current-omr-landscape/)
- Author's verdict: no single app is clearly best. The ML-based and mobile apps suit simpler workflows. — [Scoring Notes](https://www.scoringnotes.com/reviews/scanning-the-current-omr-landscape/)
- A 2026 review site lists PlayScore 2 tiers from $5.99/mo up to $59.99/yr, says MusicXML export requires Professional, and notes it runs on iOS, Android and Windows. — [sheetmusicapps.com PlayScore 2 review (2026)](https://www.sheetmusicapps.com/reviews/playscore/)
- A Japanese blog ranks Soundslice first and calls PlayScore 2 recognition "useless". This is an outlier opinion. — [note.com hirosawahills](https://note.com/hirosawahills/n/nc577e1b279aa?hl=en)

**MuseScore PDF import**
- MuseScore's "Import PDF" is a web service at musescore.com/import that, according to forum users, runs "an outdated and non-configurable version of Audiveris". Users report frequent failures. A WPS blog claims MuseScore 4 has Audiveris built in, which conflicts with the forum reports. — [MuseScore forum: Audiveris version](https://musescore.org/en/node/359667); [MuseScore forum: Import PDF](https://musescore.org/en/node/376686); conflicting [WPS blog](https://www.wps.com/blog/how-to-convert-pdf-to-midi-4-methods-that-actually-work/)

**Klangio**
- Klangio is mainly an audio-to-notation company. It has a limited free tier, and paid plans start around $9.99/mo according to a review aggregator. — [agent-finder.co](https://agent-finder.co/best/best-ai-music-transcription-software); its 2026 benchmark covers audio transcription, not OMR — [Klangio blog](https://klang.io/blog/music-transcription-benchmark-2026/)

### Inferences
- Flat's API is the lowest-effort way to get production-grade OMR for photos into a Flutter app through server calls. Its "Interactive Jobs" flow, built for adding pages one by one from a phone, fits Scale's import UX closely. Handwritten lead sheets would still need another route, such as an LLM.
- The PlayScore engine (ReadScoreLib from SeeScore/Dolphin) is the only commercial engine I saw marketed as an embeddable library. Licensing terms would have to be negotiated. [Inference from the seescore.co.uk listing; terms not verified.]

### Gaps
- Flat credit-pack prices per page were not shown on the docs page.
- I did not verify current 2026 pricing or features for Newzik "Maestria", SmartScore 64 / X2, ScanScore 3, PhotoScore (Neuratron), or a Klangio sheet scanner. I found no evidence that any of them offers a developer API.
- I did not obtain ReadScoreLib licensing prices.

## 3. Accuracy benchmarks and metrics; real-world error rates and failure modes

### Takeaway
The field has converged on edit-distance metrics: SER (symbol error rate), OMR-NED (introduced with the Sheet Music Benchmark at ISMIR 2025) and TEDn. On realistic pianoform benchmarks, the best open tools still show token-level errors of roughly 13–25% OMR-NED. Formal, independent error rates for real phone photos are scarce. In practice, multi-staff full scores photographed with a phone are where tools break down. Tuplets, beams, octave lines, dynamics and repeats/endings are the most commonly dropped elements.

### Cited Findings
- Sheet Music Benchmark (SMB) by Martinez-Sevilla, Calvo-Zaragoza, Sapp, Rizo and others (ISMIR 2025): 685 pages covering monophonic, pianoform and quartet textures, encoded in **kern. It introduces OMR-NED, which extends SER to give a finer breakdown of errors (note heads, beams, pitches, accidentals) and provides standard train/test splits. — [arXiv 2506.10488](https://arxiv.org/abs/2506.10488); dataset [Zenodo](https://zenodo.org/records/17706531)
- homr's own benchmark uses token-level OMR-NED = edit_distance / (N_ref + N_pred), scoring upper and lower staves separately. On polish-scores (112 samples) the reported values are about 15.3% (most likely homr), 23.8% (transcoda), 78% (oemer) and 20.8%. On SMB (685 pages) the values are 12.8% and 17.2%. The table was misaligned when extracted, so the tool-to-number mapping is uncertain except for oemer at 78%. Scores computed with musicdiff are much higher (about 26–75%). — [homr Benchmark.md](https://github.com/liebharc/homr/blob/main/Benchmark.md)
- LEGATO reports TEDn and OMR-NED, with 68.2% and 48.1% absolute error reductions on its most realistic dataset. — [arXiv 2506.19065](https://arxiv.org/abs/2506.19065)
- Real-photo failure modes from the independent review: unusable phone-photo scans of a multi-staff orchestral score (Soundslice, PlayScore 2 at defaults). Triplets not inferred and piano staves not joined into one grand staff (ScanScore). Missed dynamics, rehearsal marks and repeat endings (Newzik). Missed tempo marking (Soundslice). — [Scoring Notes Dec 2024](https://www.scoringnotes.com/reviews/scanning-the-current-omr-landscape/)
- homr does not output beams, octave lines or glissandos, and leaves out dynamics and articulation. — [homr README](https://github.com/liebharc/homr)
- oemer omits accidentals. — [MusiXQA](https://arxiv.org/html/2506.23009v1)
- Handwriting: Audiveris and Flat do not support it. Soundslice says "maybe". oemer probably does not work on it. — [Audiveris Handbook](https://audiveris.github.io/audiveris/_pages/handbook); [Flat OMR](https://flat.io/developers/docs/api/omr/); [Soundslice](https://www.soundslice.com/sheet-music-scanner/); [oemer](https://github.com/BreezeWhite/oemer)
- A 2025 Springer chapter on OMR for real-world manuscripts trained with synthetic data shows handwritten OMR is still an active research topic. — [Springer](https://link.springer.com/chapter/10.1007/978-3-032-36023-6_17)
- MV2H appears in the task's question list, but I found no 2025–26 OMR system reporting MV2H in my sources.

### Inferences
- A score with 15% token OMR-NED on a one-page piano piece means dozens of wrong or missing tokens, so a correction UI is mandatory whichever engine is used.
- Clean digital sources (website screenshots, vector PDFs) will do much better than phone photos of printed pages. Phone photos of dense multi-staff scores are the worst case.

### Gaps
- I found no independent, quantitative error rates for commercial apps on phone photos, only qualitative Scoring Notes judgments.
- I found no published numbers for handwritten lead sheets for any production engine.

## 4. General vision-language models (Claude, GPT, Gemini) reading sheet music

### Takeaway
Credible academic evaluations from 2025–2026 consistently find that general multimodal LLMs read sheet music poorly. GPT-4o's exact-match accuracy on OMR questions was 4% in MusiXQA. Gemini-pro-vision and GPT-4V scored about 16–18 on the NOTA benchmark. Studies report "pronounced modality gaps" between image input and ABC text input (MSU-Bench, ACL 2026). Models can produce well-formed ABC or MusicXML with wrong pitches and wrong chord roots. I found no rigorous public benchmark of Claude, GPT-5 or Gemini 3 on image-to-MusicXML. Fine-tuned or specialized VLMs (Phi-3-MusiX, LEGATO) do far better, which supports a specialist OMR engine plus LLM design.

### Cited Findings
- MusiXQA (28 Jun 2025, synthetic MusiXTeX scores). On the OMR task (G-Acc / PNLS): GPT-4o 4.0 / 42.0, GPT-4o+RAG 3.8 / 70.7, GPT-4o+RAG+oemer-OMR-in-prompt 8.4 / 48.4, and the fine-tuned Phi-3-MusiX (kern+) 68.4 / 99.2. On chord estimation GPT-4o scored 5.5 G-Acc against 84.9 for the fine-tuned model. The authors say GPT-4o "does not truly recognize music symbols" and mostly imitates the answer format; chord answers often have the right quality but the wrong root. Compact output formats (kern+) trained better than verbose JSON. — [MusiXQA arXiv 2506.23009](https://arxiv.org/html/2506.23009v1)
- NOTA (NAACL Findings 2025): a benchmark that includes converting score images to ABC. Average scores were Gemini-pro-vision 18.37 and GPT-4V 15.96. The best model (Gemini) reached only 33.34% on music information extraction. — [NOTA arXiv 2502.14893](https://arxiv.org/pdf/2502.14893); [ACL Anthology](https://aclanthology.org/2025.findings-naacl.399.pdf)
- MSU-Bench (Musical Score Understanding Benchmark; v1 Nov 2025, v4 Apr 2026, ACL 2026 Main): 1,800 questions on works from Bach to Debussy, each given as PDF image and as ABC text. More than 15 models were tested. Findings: "pronounced modality gaps", unstable performance across difficulty levels, and large gains from fine-tuning. The abstract does not name the models or give numbers. — [arXiv 2511.20697](https://arxiv.org/abs/2511.20697)
- "Music I Care About" (arXiv, Jul 2026) benchmarks LLM music perception, including Gemini 3.1 and GPT-5, across modalities (rendered, printed scan and handwritten scan scores), mainly on audio. The search summary did not surface image-to-notation results. — [arXiv 2607.06015](https://arxiv.org/html/2607.06015v1)
- LEGATO 2 positions specialized symbolic transcription as an input that helps frontier LLMs understand scores. — [arXiv 2607.05769](https://arxiv.org/abs/2607.05769)
- Vendor or practitioner claim (Songscription, a competitor): neither Gemini nor Claude can read a printed score note for note, and models "recognize symbols ... and still convert them into the wrong notes". — [Songscription blog](https://www.songscription.ai/blog/can-gemini-make-sheet-music)
- MLLMs answer an OMR question in about 1.1–1.5 s, compared with about 62 s per page for oemer. Speed favors LLMs and accuracy does not. — [MusiXQA](https://arxiv.org/html/2506.23009v1)

### Inferences
- For Scale, Claude vision is likely good enough for what it already does: lead-sheet chord symbols, titles, key and time signatures, and possibly simple monophonic melodies from clean screenshots. It is not reliable for note-accurate two-staff piano transcription from photos. This is consistent across MusiXQA, NOTA and MSU-Bench, although Claude itself was not named in the results I saw.
- The hybrid with the best support: a dedicated OMR engine produces MusicXML, and the LLM handles text recognition (titles, chord symbols, lyrics), consistency checks (bar durations, key, voice totals) and targeted fixes on regions it is given. MusiXQA shows that simply pasting raw OMR output into GPT-4o's prompt helped little, so the LLM should get structured, focused tasks rather than a raw dump.
- Handwritten lead sheets (melody plus chord symbols) are a gap for dedicated engines. There, an LLM with a user-verification step may be the only practical option, with the measured weakness on pitches in mind.

### Gaps
- I found no rigorous, public 2025–2026 evaluation of Claude (any version), GPT-5 or Gemini 2.5/3 on image-to-MusicXML or ABC transcription with note-level metrics.
- I found no published study of LLM post-correction of OMR output with measured error reduction.

## 5. Recommended architecture for a mobile app in 2026 (on-device vs. server, hybrid, correction UX)

### Takeaway
The evidence points to a server-side (or cloud API) OMR step, not on-device. Use a hosted API such as Flat's, or self-host homr, Audiveris or SMT behind your own endpoint, and accept the AGPL and training-data caveats if you do. Use the existing Claude integration for chords, text and lead sheets, and for sanity checks. Then require an in-app review and correction step, because even the best engines leave about 10–25% token error on realistic piano pages.

### Cited Findings
- On-device cost: oemer takes 3–5 min on a GPU and downloads large checkpoints on first run. homr needs Python 3.11+ (optional CUDA/ROCm). Audiveris needs a Java runtime, and its installers bundle one. — [oemer](https://github.com/BreezeWhite/oemer); [homr](https://github.com/liebharc/homr); [Audiveris updates](https://audiveris.github.io/audiveris/_pages/reference/updates)
- Server API option: Flat OMR takes about 30–60 s per page, supports adding pages one by one for mobile capture, returns MusicXML, and allows commercial redistribution of results to the customer. — [Flat OMR API](https://flat.io/developers/docs/api/omr/)
- AGPL guidance: run homr as a separate process or container. AGPL source-disclosure obligations apply even when it runs as a network service. — [homr LICENSE_FAQ](https://github.com/liebharc/homr/blob/main/LICENSE_FAQ.md)
- Correction UX precedents: Soundslice asks the user to clarify uncertain passages and offers a built-in editor. Audiveris ships a GUI for verification because accuracy is imperfect. homr adds an approximate image-position comment to each note, which allows linking notes back to the photo. Newzik takes "a few minutes" per conversion. — [Soundslice](https://www.soundslice.com/sheet-music-scanner/); [Audiveris Handbook](https://audiveris.github.io/audiveris/_pages/handbook); [homr](https://github.com/liebharc/homr); [Scoring Notes](https://www.scoringnotes.com/reviews/scanning-the-current-omr-landscape/)
- Accuracy drops sharply from clean PDF to phone photo for multi-staff scores. — [Scoring Notes](https://www.scoringnotes.com/reviews/scanning-the-current-omr-landscape/)

### Inferences
- Suggested pipeline for Scale:
  1. Capture: perspective-correct and crop the photo on-device, show a quality warning, and prefer screenshots or PDFs when available.
  2. Server OMR. Option A is Flat's API (fastest to integrate; per-page credits; no handwriting). Option B is self-hosting homr or SMT++ in a container (no per-page fee, but AGPL and non-commercial-data risk for homr, and **kern conversion plus fine-tuning work for SMT).
  3. Claude pass: extract chord symbols, title, tempo and lyrics (where Claude is already proven in Scale), validate bar durations, key and time signature against the OMR MusicXML, and flag suspicious measures.
  4. Correction UI: show the original photo next to the rendered score, with measures linked through position data (as homr provides), highlight flagged measures, and allow quick fixes to pitch, rhythm and chords. Melody and chords matter most for Scale's use case.
  5. Fallback: for handwritten lead sheets, send them straight to Claude for ABC or melody-plus-chords output with explicit user confirmation.
- Windows desktop could run Audiveris locally with its bundled-JRE installer as an "advanced" path, but the AGPL implications of bundling it into Scale would need review.
- Cost estimate: not computable without Flat pack prices (a gap). Claude API costs per image page should be checked with the claude-api reference before committing.

### Gaps
- I found no published case study of a Flutter or mobile app integrating OMR (other than the Andromr mention).
- I did not get Flat credit-pack prices or check whether Flat offers a trial for API developers.
