# Defensive Publication — Prior Art Disclosure

**Title:** Physiologically derived, per-control input debouncing for tremor-affected touch and key input

**Author / discloser:** Halfmarble LLC (gerard ziemski, Cofounder | Bioenergetics OS Architect)

**Effective publication date:** 2026-08-09 (the date this document was first published in the public HalfmarbleKit repository). A Technical Disclosure Commons deposit is pending; that deposit improves findability and does **not** re-date this disclosure.

**TDCommons:** _pending — article number to be backfilled here once posted._

**Status:** Defensive publication. The method described herein is dedicated to the public domain (see *Dedication*, below).

---

## Purpose

This document is a **defensive publication**. Its sole purpose is to place the method described below into the public record as **prior art**, so that it remains freely practicable by anyone and **cannot be patented by any third party**.

It is **not** a product description, a license grant for any software, or a statement about the availability or price of any application.

**Point of novelty.** Input debouncing is old and well-anticipated art, and this disclosure does not claim it (see *Closest known prior art*). The two elements published here as a **combination** are:

- **§A — sizing the debounce window from the characteristic frequency of the tremor being filtered**, `W = 1/f`, together with the coverage rule that follows from it (a window of width `W` suppresses every tremor *faster* than `1/W`, so the exposed edge of any such filter is the **slow** side of the band, not the fast side); and
- **§B — scoping the debounce per control rather than globally**, on the ground that a tremor burst re-triggers the *same* control, so per-control scoping filters the tremor while leaving fast *deliberate* sequences across *different* controls untouched.

Neither element is exotic. Both are published because the combination is the difference between an accessibility filter that works and one that silently eats skilled input, and because a third party should not be able to claim it.

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

Presented honestly: debouncing is ancient, and the elements below are **not** claimed here.

- **Hardware and firmware switch debounce** — filtering mechanical contact bounce by ignoring transitions within a fixed interval. Universal, decades old, and the direct ancestor of this method.
- **Platform accessibility repeat filters** — operating-system input-filtering features that ignore repeated activations within a user-configurable interval, including key-repeat filters of the "bounce keys" / "filter keys" family (which are keyed per key, and therefore anticipate the *per-control* idea in the keyboard domain) and touch-repeat filters on mobile platforms. These are user-enabled, globally scoped to the input device, and expose the interval as an arbitrary user setting rather than deriving it.
- **Application-level tap throttling** — widely used to prevent double-submission, generally sized by feel or by animation duration, and generally global to a screen.

**Net:** what the above do *not* supply is the bridge between the **physiology** and the **parameter** — the explicit derivation `W = 1/f` from a tremor's characteristic frequency, the coverage rule that the uncovered tail is the slow side of the band, and the pairing of that derivation with **per-control** scoping applied by default at the application layer. The most likely route to a third-party claim would be an obviousness combination of a platform repeat filter with a published tremor frequency; publishing §A–§D as prior art forecloses a clean novelty claim and supplies the express teaching that such a combination would otherwise have to assume.

> **A formal prior-art search has not been completed for this disclosure.** The categories above are stated from general knowledge of the field and are believed accurate, but the search that the applicant's other disclosures received is still owed here and should be completed before deposit. This note is deliberate: an unverified review presented as a completed one would weaken the record it exists to build.

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
