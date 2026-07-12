# Idea: Audio spectrum visualizer (reintroduction)

Status: **removed from the product** (as of `v0.11.0-beta.5`). This note captures why the first attempts failed and the recommended architecture if we bring a visualizer back.

Related history: experimental toggle under Settings → Experimental; mutual exclusion with multi-audio mix; `AudioSpectrumService` + `AudioSpectrumVisualizer` (deleted).

---

## Why it was removed

The feature looked small in Dart (settings toggle + bar painter + mpv `af` segment), but it was not small in packaging or correctness:

1. **It was not a real spectrum.** The working path shaped one overall RMS/Peak (`astats`) into ~32 synchronized bars. Product copy said “frequency / spectrum,” which overclaimed.
2. **Bundled Win/mac FFmpeg is filter-starved.** media_kit’s libmpv builds FFmpeg with `--disable-filters` and only re-enables a tiny whitelist (historically `overlay` + `equalizer`). Filters like `astats`, `asplit`, `showfreqs`, `showspectrum` are **absent from the binary linked into libmpv**. Installing a full `ffmpeg` on `PATH` does not help — libmpv uses its own libavfilter.
3. **`setAudioFilter` “success” lied.** Echoing the `af` property back often meant the string was accepted or stored, not that the lavfi graph was live and exporting metadata.
4. **`af-metadata` polling was unreliable** on the bundled mpv (nested `af-metadata/label/key` reads, empty polls → flat UI / resting ticks that looked “broken”).
5. **Unit tests could not catch it.** Fakes returned whatever metadata we injected; CI never exercised real libmpv/FFmpeg filter capability.
6. **Cost vs. value.** A trustworthy visualizer needs custom native packaging (Win/mac), album-art / `lavfi-complex` conflict handling, and honest UX. Too much for a small experimental strip.

Linux often “worked better” only because system libmpv/FFmpeg usually ships a fuller filter set — not because the Dart design was solid cross-platform.

---

## What we already tried (do not revive as-is)

| Approach | Idea | Outcome |
| -------- | ---- | ------- |
| Passthrough `@dacxstats:lavfi=[astats=…metadata=1]` | Poll `af-metadata` for Overall RMS/Peak; shape bars in Dart | Best of the bad options on machines that had `astats`; still pseudo-spectrum; still dead on stock Win/mac media_kit FFmpeg |
| Multiband `asplit` → per-band `astats` → `anullsink` | True-ish bands via analysis splits | Analysis path never exposed usable RMS on mpv’s filter output; bars stayed flat while UI painted resting ticks |
| Capability probe + OSD + auto-disable | Fail soft when metadata empty | Probe false positives/negatives; turning the preference off after cold start annoyed users; did not fix missing filters |

**Do not** reintroduce Dart-only `af` + `af-metadata` polling against stock media_kit Win/mac binaries. That path is a known dead end.

---

## Recommended path: Option A — `lavfi-complex` + `showfreqs` as video

Goal: a **true** frequency visual that reuses the existing media_kit `VideoController` texture path, with **zero cost when off**.

### Architecture

```
audio decode (mpv)
        │
        ▼
 lavfi-complex graph
   ├─► playback output (speakers)  [passthrough / EQ as today]
   └─► showfreqs / showspectrum    [renders spectrum as video frames]
        │
        ▼
 mpv video output → media_kit VideoController → Flutter texture
```

Sketch (illustrative — tune labels/filters when implementing):

```text
lavfi-complex =
  "[aid1]asplit[a][viz];
   [viz]showfreqs=s=1280x200:mode=bar:ascale=log:fscale=log[vo]"
```

- **When off:** do not set `lavfi-complex` for viz; no extra filters; current EQ-only `af` chain stays as-is.
- **When on (audio files):** set a viz graph that splits audio, keeps audible path clean, and produces a video plane for the spectrum.
- **UI:** show that video texture in the player chrome (bottom strip or full audio backdrop) instead of a custom `CustomPainter` driven by polled floats.

### Why this is better than metadata bars

- Spectrum computation stays inside FFmpeg (real FFT / freq display), not a Dart fake.
- Display uses the path Dacx already trusts for video (`VideoController`).
- No fragile `af-metadata` polling loop; no native crash risk from reading missing labels.
- Honest product language: “spectrum visualizer” matches what users see.

### Native packaging requirement (the real work)

Option A **does not** require patching libmpv source. It **does** require shipping an FFmpeg/libavfilter that includes at least:

- `asplit` (or equivalent split)
- `showfreqs` and/or `showspectrum` / `showcqt` (pick one and stick to it)

**Windows / macOS**

- Replace or overlay media_kit’s prebuilt FFmpeg/libmpv artifacts with a custom build that enables those filters (and keeps `equalizer` for EQ).
- Document the build recipe next to release tooling (filters enabled, license implications if GPL filters pull the binary GPL).
- Version-pin and smoke-test filter presence in CI (`avfilter_get_by_name("showfreqs")` / runtime probe against the **bundled** lib, not PATH ffmpeg).

**Linux**

- AppImage / deb / rpm / Flatpak: either ship the same custom libmpv stack **or** rely on system libmpv **only if** capability probing proves `showfreqs` exists; otherwise disable the toggle with a clear message.
- Prefer one strategy long-term (ship consistent libs) so behavior matches Win/mac.

See also [`docs/NATIVE_DEPENDENCIES.md`](../NATIVE_DEPENDENCIES.md).

### Album art and VO ownership

Today, audio playback often shows Flutter-drawn album art while mpv has little/no useful video. Option A makes mpv the owner of a **video** plane for the visualizer.

Implications:

- Cache album-art image bytes in Dart (already partly done for media session) and composite in Flutter **above or beside** the spectrum texture — do **not** expect mpv cover-art VO and `showfreqs` VO to coexist cleanly without an explicit layout plan.
- Decide one primary visual for audio mode: spectrum strip + art card, or spectrum as full backdrop with art overlay. Document the choice in UI before coding.

### Conflict with multi-audio mix

Multi-audio mix already uses `lavfi-complex`. Two complex graphs cannot own the same property without a merge strategy.

Options when reintroducing:

1. **Mutual exclusion** (simplest): mix on ⇒ visualizer off (and vice versa), with OSD/copy that says so.
2. **Merged graph**: one `lavfi-complex` that mixes `aid*` **and** feeds `showfreqs` — harder, must be tested per track-count.

Start with (1) unless mix + viz is a hard requirement.

### EQ coexistence

Keep EQ on the `af` chain (`equalizer=…`) when possible. Order matters: decide whether spectrum samples pre- or post-EQ and document it (users usually expect **post-EQ** “what I hear”).

If EQ and `lavfi-complex` interact badly on a given mpv build, apply EQ inside the complex graph instead of separate `af` — treat that as an implementation detail with tests.

### Product / UX rules (non-negotiable if it returns)

- Off by default; Experimental until packaging + QA are solid on Win, mac, and Linux.
- Copy must not say “spectrum / frequency” unless the implementation is real FFT/`showfreqs`-class output.
- Capability failure: leave preference on if desired, but **do not** paint fake resting bars that look like a bug; show a one-shot OSD / settings subtitle (“unavailable on this build”).
- Zero cost when off: no timers, no complex graph, no video texture churn.

---

## Alternatives (not recommended first)

| Option | Summary | Why secondary |
| ------ | ------- | ------------- |
| **B – PCM tap + Dart FFT** | Patch libmpv / custom plugin to expose PCM; FFT in Dart/FFI | Heavier maintenance than custom FFmpeg filters; still needs custom natives |
| **C – Second decoder** | Decode file twice for analysis | Drift, CPU, battery; bad for a desktop player |
| **D – Cosmetic animation** | Fake bars from playhead / random | Dishonest; only OK if labeled as decoration, not “audio visualizer” |

---

## Acceptance criteria for a future PR

- [ ] Bundled Win/mac libs expose `showfreqs` (or chosen filter); CI probe fails the build if missing.
- [ ] Linux strategy documented and verified on AppImage (and at least one distro package).
- [ ] Visualizer off ⇒ no `lavfi-complex` viz graph, no extra CPU vs current EQ-only path.
- [ ] Visualizer on + local audio file ⇒ visible frequency motion correlated with content (not overall-loudness morph).
- [ ] Seek / pause / stop clear or freeze appropriately; no crash on rapid open/close.
- [ ] Multi-audio mix: exclusion or merged graph works; no silent `lavfi-complex` clobber.
- [ ] Album art still shows via Flutter composite when present.
- [ ] EQ still works; spectrum vs EQ ordering documented.
- [ ] Settings + README + QA checklist updated; Experimental until all above pass on the three desktop targets.
- [ ] No reliance on `af-metadata` polling for the happy path.

---

## Suggested implementation slices (when prioritized)

1. **Packaging spike:** custom FFmpeg/libmpv with `asplit`+`showfreqs` for macOS *or* Windows; prove `lavfi-complex` renders into `VideoController`.
2. **Player integration:** audio-only layout, off-by-default setting, mix exclusion, EQ ordering.
3. **Linux / release:** same libs or probed system mpv; AppImage + Flatpak notes.
4. **Polish:** themes, height, reduced-motion, OSD/capability copy.
5. **Graduate or keep Experimental** based on burn-in — not a `1.0` blocker either way.

---

## References (investigation notes)

- media_kit / libmpv Darwin & Windows builds historically use FFmpeg `--disable-filters` with a minimal enable list — analysis/viz filters are not in that list.
- Stock `equalizer` remaining in the whitelist is why EQ works today while `astats`/`showfreqs` do not on those bundles.
- Nested mpv property reads for `af-metadata/<label>/…` on older bundled mpv were a second failure mode even when filters existed.
- This feature was removed rather than left “experimental but broken” to avoid trust erosion; reintroduction should be packaging-first, UI-second.
