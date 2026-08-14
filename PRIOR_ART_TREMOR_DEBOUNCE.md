# Defensive Publication — Prior Art Disclosure

**Title:** Physiologically derived, per-control input debouncing for tremor-affected touch and key input

**Author / discloser:** Halfmarble LLC (gerard ziemski, Cofounder | Bioenergetics OS Architect)

**Effective publication date:** 2026-08-09 — the date this document became publicly accessible in the HalfmarbleKit repository (`github.com/halfmarble/HalfmarbleKit`), which is its **first public disclosure** and therefore its governing prior-art date. It was deposited the same day in the Technical Disclosure Commons Defensive Publications Series, where it was still unpublished and login-gated at the moment the repository went public; the TDCommons posting supplies the indexed, examiner-searchable record and does **not** re-date this disclosure.

**TDCommons:** posted 2026-08-11 as **[dpubs_series/11329](https://www.tdcommons.org/dpubs_series/11329)** (deposited 2026-08-09 as submission #12667). Recommended citation: ziemski, gerard, "Physiologically derived, per-control input debouncing for tremor-affected touch and key input", *Technical Disclosure Commons*, (August 11, 2026) https://www.tdcommons.org/dpubs_series/11329 — the indexed, examiner-searchable record. It does **not** re-date this disclosure, whose governing date remains 2026-08-09 as stated above.

**Independent archival of the publication date.** A git repository cannot establish its own publication date — commit timestamps are author-settable and the hosting platform exposes no "made public at" field — so the date asserted above is corroborated by third-party, content-addressed records made on 2026-08-09:

- **Software Heritage**, snapshot `swh:1:snp:1f012d5d06f24827636ba19853afb3cc656f438d` (visit status *full*), archiving `refs/heads/main` at commit `7ed11b2a0dabb6e0c333d5316a5126d875fe9f98` together with release tags `1.0.0` and `1.0.1`. The first-published text of this disclosure within that snapshot is the content object `swh:1:cnt:130ee9a06bd16fde93d29439d7a4458db63b0b51`. (That archived revision predates this paragraph, which was added afterwards; the body of the disclosure — §A–§D, the prior-art analysis, and the dedication — is unchanged from it.)
- **Internet Archive**, repository landing page captured at `web.archive.org/web/20260809191456/https://github.com/halfmarble/HalfmarbleKit`.

**Status:** Defensive publication. The method described herein is dedicated to the public domain (see *Dedication*, below).

---

## Purpose

This document is a **defensive publication**. Its sole purpose is to place the method described below into the public record as **prior art**, so that it remains freely practicable by anyone and **cannot be patented by any third party**.

It is **not** a product description, a license grant for any software, or a statement about the availability or price of any application.

**Point of novelty.** Input debouncing is old and well-anticipated art, and this disclosure does not claim it (see *Closest known prior art*). The two elements published here as a **combination** are:

- **§A — sizing the debounce window from the characteristic frequency of the tremor being filtered**, `W = 1/f`, together with the coverage rule that follows from it (a window of width `W` suppresses every tremor *faster* than `1/W`, so the exposed edge of any such filter is the **slow** side of the band, not the fast side); and
- **§B — scoping the debounce per control rather than globally**, on the ground that a tremor burst re-triggers the *same* control, so per-control scoping filters the tremor while leaving fast *deliberate* sequences across *different* controls untouched. **This one is already anticipated in the keyboard domain** — Bounce Keys has scoped to the same key for decades (see *Closest known prior art*) — so it is published here for its application to touch controls and for the combination with §A, not as an independent novelty claim.

Neither element is exotic, and the base mechanism is anticipated and patented by others. Both are published because the combination is the difference between an accessibility filter that works and one that silently eats skilled input, and because a third party should not be able to claim that combination.

---

## Scope and what this does *not* do

This dedication applies **only to the input-filtering method described in this document.** To avoid any ambiguity, this disclosure:

- **Does NOT** dedicate, and is expressly carved out from, the applicant's **retained tremor-sensing and neuromotor-observer methods** — in particular the **estimation or measurement of tremor from inertial or other sensor data**, including band-power tremor indexing over a DFT detection band, rest-floor thresholding, and any derived tremor metric. This document dedicates the *use* of a tremor-frequency figure to size an input filter; it does **not** dedicate any method of *obtaining* that figure by measurement.
- **Does NOT** dedicate the applicant's broader bioenergetic, motor-control biomarker, or closed-loop sensory-cuing methods, which are outside the scope of this document and unaffected by it.
- **Makes no health claim of any kind.** The method is input filtering for hands that tremble. It does not treat, diagnose, mitigate, or prevent any condition, and nothing here should be read as asserting otherwise. The software in which it is embodied is entertainment software.

---

## Disclosure

### §A — Sizing the window from tremor physiology (the central method)

A repeated, unintended activation caused by a hand tremor arrives as a burst of discrete input events. Where the tremor oscillates at frequency `f`, successive events in the burst are spaced approximately `1/f` apart.

The method sets the debounce window to one full period of the tremor frequency to be covered:

> `W = 1 / f`

and accepts the coverage consequence that follows directly from it:

> a window of width `W` rejects every repeat whose interval is shorter than `W`, and therefore suppresses every tremor **faster** than `1/W`. Faster tremor is *easier* to filter, not harder; the uncovered tail of the band is always the **slow** side.

A worked example, for the classical rest tremor band of approximately 4–6 Hz, using `f = 5 Hz` and therefore `W = 0.20 s`:

| tremor rate | event interval | 0.20 s window |
|---|---|---|
| 7 Hz | ~0.14 s | rejected |
| 6 Hz | ~0.17 s | rejected |
| 5 Hz | 0.20 s | boundary — everything strictly faster is rejected |
| 4 Hz | 0.25 s | passes |
| 3 Hz | 0.33 s | passes |

The window width is therefore an explicit, statable trade rather than a tuned-by-feel constant: `W = 0.20 s` covers the fast half of the band completely and concedes the slow tail, in exchange for preserving deliberate re-activation. Widening to `W = 0.25 s` (one 4 Hz period) covers the full 4–6 Hz band at a measurable cost to deliberate re-press latency. Any `f` in the band may be chosen; the method is the derivation, not the particular constant.

**Corollary disclosed as part of the method:** a constant derived this way must carry its derivation with it at the point of definition. A window labelled as "one period of an `f` Hz tremor" whose value is not `1/f` is a defect that a reader cannot detect without redoing the arithmetic.

### §B — Per-control scoping (the element that preserves skilled input)

The debounce state is keyed by the identity of the control being activated, rather than held once for the whole interface:

- a second activation of the **same** control within `W` of an accepted activation counts as a tremor bounce and is **rejected**;
- an activation of a **different** control within `W` counts as deliberate input and is **always accepted**.

The ground for this is behavioural rather than aesthetic: a tremor burst is a mechanical oscillation of the hand at rest on or near one target, so its repeats land on the *same* control. A globally scoped debounce cannot distinguish that from a fast, deliberate two-control sequence, and will discard the second activation of the latter — which presents to the user as an interface that randomly ignores them, and to a skilled user as lost input during exactly the sequences that require speed.

Stated as a rule: **filtering the symptom must not filter the skill.**

### §C — Leading-edge arming, applied at activation onset

Two details of the timing, disclosed as part of the combination:

- **Leading edge.** Only an *accepted* activation arms the cooldown. A rejected activation does not extend the window, so a sustained burst cannot hold the control shut beyond one window past its last accepted event.
- **Onset, not completion.** The filter is applied at activation *onset* (touch-down / key-down) and rejects by cancelling the control's own tracking before any visual state change occurs, so the after-shocks of a burst produce no highlight flicker. Filtering at completion would render the rejected activations visible as stutter.

### §D — Default-on, application-level placement

The filter is applied by the application (or its shared UI layer) to its own controls, on by default, with no user configuration required and no dependency on a platform accessibility setting having been discovered and enabled by the user. The rationale is that the population most helped by the filter is the least likely to have navigated a settings tree to switch it on, and that a window sized from `§A` is defensible as a default in a way that an arbitrary one is not.

### Variations within scope

The following are disclosed as variations of the same method, so that they are equally foreclosed to a third party:

- any `f` within or beyond the 4–6 Hz rest-tremor band, including windows sized for the faster (~6–12 Hz) action/postural tremor band;
- **adaptive sizing** — setting `W = 1/f̂` from a tremor-frequency estimate `f̂` for the individual user, **however that estimate is obtained**, including from a user setting, a calibration gesture, or a sensor. *(The disclosure covers the sizing of the input filter from such an estimate. It does **not** cover any method of producing the estimate by measurement — see* Scope *above.)*
- per-control-*class* scoping (all controls of one commit class sharing a key) as an intermediate between global and per-control;
- application to any discrete input modality where an unintended repeat is mechanically driven — touch, hardware keyboard, game controller, switch, pointer;
- rejection accompanied by no feedback, or by deliberately distinct feedback, on the rejected event.

---

## Closest known prior art (what a third party would have to design around)

Presented honestly: debouncing is ancient and **substantially anticipated**, including by an issued patent. None of the following is claimed here.

- **Apple, "Touch accommodation options"** — US 9,961,239 B2, and the continuations US 10,986,252 and US 11,470,225. This is the closest art and it is *patented*, not merely published. Its independent claim covers precisely the base mechanism: *"in accordance with a determination that the second touch input meets the set of one or more ignore-repeat criteria, which include a criterion that is met when the amount of time between the first touch input and the second touch input is less than the ignore-repeat duration time period, forgoing providing the second data to the application."* It ships as iOS **Settings → Accessibility → Touch → Touch Accommodations → Ignore Repeat**, with a user-adjustable interval. The claims recite the interval as corresponding to a *user setting*; they do not recite deriving it from a tremor frequency, and they do not recite per-control scoping.
- **Bounce Keys / Filter Keys** — the keyboard accessibility filter in X11/XKB, GNOME, and Windows (as part of FilterKeys). It "introduces a delay during which the system will not acknowledge repeated key presses **of the same key**", explicitly for users whose tremor causes them to bounce on a key. **This anticipates §B in the keyboard domain**: same-control scoping is decades old there. What it does not do is carry that scoping to touch controls, or derive its interval from anything but a user setting.
- **Hardware and firmware switch debounce** — ignoring contact transitions within a fixed interval. Universal, and the direct ancestor of all of the above.
- **Tremor-frequency signal filtering** — low-pass and 4–8 Hz band-pass filtering of continuous motion or pressure signals to suppress tremor, including for gesture recognition (e.g. US 11,106,283; US 12,001,611). These use the tremor band to shape a *continuous-signal* filter, not to size a *discrete-event* rejection window.
- **Adaptive touch-delay research** — e.g. a self-service-kiosk technique that samples a user's first five touches to decide whether to retain a 1200 ms touch delay. Adaptive, but adapting a hold delay rather than deriving a repeat window from tremor period.
- **Application-level tap throttling** — double-submit prevention, generally sized by feel or animation duration and global to a screen.

**Net.** The base mechanism — reject a repeat inside a window — is anticipated and, for touch, claimed by Apple. What the search did **not** find is the bridge between the **physiology** and the **parameter**: the explicit derivation `W = 1/f` from the tremor's characteristic frequency, and the coverage rule that follows (a window `W` suppresses everything *faster* than `1/W`, so the uncovered tail is the **slow** side of the band). Every repeat filter located above exposes its interval as an arbitrary user setting. Publishing §A–§D forecloses a clean novelty claim over that derivation and over its pairing with per-control scoping applied by default at the application layer — the obviousness combination (a platform repeat filter plus a published tremor frequency) now has an express teaching in the record instead of having to be assumed.

### Scope of the search behind this section

Run 2026-08-09, in two passes.

**The Apple family, mapped.** `US 9,961,239 B2` (filed 2015-09-23, priority **2015-06-07**) → `US 2018/0213126` (15/924,769) → `US 10,986,252` (16/534,291) → `US 11,470,225` (17/224,997, filed 2021). Anticipated expiry **2035-09-23**. Inventors Fleizach, Kasemset, Kannamangalam Sundara Raman. The successive continuations mean the family has been kept in prosecution, so claim scope in this area is not necessarily settled.

Across the family, the independent claims recite three accommodations — hold duration, ignore-repeat, and tap assistance. **None recites scoping the ignore-repeat per UI element**, and **none recites deriving the duration from a tremor frequency or any physiological measurement**; the duration corresponds to a user setting throughout. That is what leaves §A standing.

**On implementation layer.** The Apple specification states that the accommodations are, *in some embodiments*, implemented in a software layer separate from the application layer, such as the operating system. Recorded here as a characterisation of that disclosure's scope, since the method published below is applied by an application to its own controls.

**Academic literature.** Located and reviewed at the abstract level: swabbing for elderly users with tremor (CHI '11); shared user models for touch interaction (ASSETS '12); reducing fine pointing and steady tapping on Android (W4A '15); motion-sensor input correction for tremor (Plaumann et al.); PersonalTouch (CHI '19); BrushLens (UIST '23); and a self-service-kiosk technique adapting a 1200 ms hold delay over a user's first five touches. None sizes a discrete-event rejection window from the tremor period. Full text of the W4A '15 paper was not retrievable (publisher paywall), so it is assessed from its abstract only.

**Unresolved.** No international (EP/WO/CN/JP) family members for the Apple patents were confirmed either way from the sources reachable here; a non-US search is still owed if this matters for a non-US filing.

> **This is not a freedom-to-operate analysis and must not be used as one.** A defensive publication establishes prior art; it does not clear a path through anyone else's claims. Anyone relying on this commercially should obtain a professional opinion, starting from `US 9,961,239` and its continuations.

---

## Reference implementation

The method is embodied in shipping code, published under Apache 2.0:

- `Sources/HalfmarbleKit/MenuButtons.swift` — `HMMenu.menuTapCooldown` (0.20 s, carrying its derivation at the point of definition) and `HMMenu.acceptMenuTap(now:)`, a leading-edge throttle applied at touch-down to every kit control. This instance is process-global (§B is *not* applied here: one pointing hand, one cooldown, and the kit's controls are not used in fast cross-control sequences).
- StringFusor `BoardMirror.acceptMenuTap(_ key:)` — the same 0.20 s window, **keyed per control** (§B), guarding the in-game commit controls, where fast deliberate cross-control sequences are routine play.

The two sites are kept in lockstep as an explicit contract; the divergence in scoping between them is the deliberate application of §B where it is needed and its omission where it is not.

---

## Supporting science

The frequency figures used to size the window are drawn from the clinical literature and are not original to this disclosure:

- Deuschl G, Bain P, Brin M. Consensus statement of the Movement Disorder Society on tremor. *Movement Disorders* 1998;13(S3):2–23.
- Jankovic J. Parkinson's disease: clinical features and diagnosis. *J Neurol Neurosurg Psychiatry* 2008;79:368–376.
- Bhatia KP, et al. Consensus statement on the classification of tremors, from the task force on tremor of the International Parkinson and Movement Disorder Society. *Movement Disorders* 2018;33:75–87.

---

## Dedication to the public domain (CC0)

To the greatest extent possible under law, Halfmarble LLC hereby **dedicates the method described in this document to the public domain** under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/), waiving all copyright and related or neighboring rights in this disclosure, and **irrevocably disclaims any intention to seek patent protection** on the method disclosed herein.

Anyone may make, use, sell, or distribute implementations of this method without permission or attribution.

This dedication is limited to the method disclosed in this document and does not extend to the carve-outs listed under *Scope*, above.
