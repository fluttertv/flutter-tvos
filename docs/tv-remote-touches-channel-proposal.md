# Where should `flutter/tv_remote_touches` live? — explanation & proposal

**Question (Mehmet):** Move `flutter/tv_remote_touches` out of the engine into the
`flutter_tvos` plugin, so the engine only ships `flutter/tv_remote`. Detailed
swipe / coordinate capture would then require adding `flutter_tvos`.

**Short answer:** Good instinct, and the goal is right — the engine shouldn't pay
for advanced gestures. But the split should be by **event semantics**, not by
**which channel sits where**. Done literally, the move regresses basic navigation.
There's a cleaner way that gets you exactly what you want.

---

## How remote input flows today

The Siri Remote touchpad arrives as native `UITouch` on `FlutterViewController`
— the engine's view. On iOS/tvOS the engine intercepts these touches itself; they
do **not** reach Dart on their own. So the native capture + coordinate
normalization (`[-1,1]` against view bounds — this is what retired the old
`x-1000 / y-500` hardcodes) must live in the engine no matter what. "Move to the
plugin" can therefore only mean moving the **Dart-side interpretation**, never the
native capture.

From those same touches the engine does **two independent things**:

1. **Turns a held swipe into navigation.** `handleTouches → updateContinuousSwipe
   → keyRepeater` (`FlutterTvRemotePlugin.mm:700→758`) emits repeated arrow-key
   events on `flutter/keyevent`. The Focus / Shortcuts / Actions stack consumes
   them exactly like a held keyboard key — lists scroll. **This works with no
   plugin installed.** It is base TV navigation, not an app feature.

2. **Forwards raw coordinates** on `flutter/tv_remote_touches`
   (`FlutterTvRemotePlugin.mm:716`) for consumers that need detail: exact finger
   position, custom gestures, video scrubbing.

Why it's structured this way: commit `88cafb6` ("Extract Apple TV remote handling
into FlutterTvRemotePlugin") deliberately pulled ~200 lines of input handling out
of `FlutterViewController` into one engine-owned plugin, so channels are stable
across view-controller lifecycle and the repeat/bias/normalization logic isn't
split across layers.

## Why the literal move regresses

Both things above are fed by the *same* touches. "Remove touches handling from the
engine" takes the raw-coordinate forwarding (item 2 — what we want gone for
plugin-less apps) **and** the navigation repeater (item 1) with it. Result:
**anyone who hasn't added `flutter_tvos` loses swipe-to-scroll.** That's not an
advanced feature, it's core navigation — and re-splitting this logic across engine
and plugin reintroduces exactly the "mixed concerns" `88cafb6` fixed. It also
creates an engine×plugin version matrix: today both ends of the touches protocol
version together with the engine.

## Proposal — same goal, no regression: make the channel *lazy*

Keep the channel in the engine, but make it silent until something subscribes.

- **Engine keeps `flutter/tv_remote` + the swipe→arrow-key repeater.** These are
  the platform input contract; they must work plugin-less. Already thin, no change.
- **`flutter/tv_remote_touches` stays in the engine but becomes lazy.** It emits
  only when Dart opts in (`setTouchStreamEnabled(true)`, sent on the first
  `addRawListener`). No plugin → no subscription → the engine serializes **zero**
  touch messages. Same zero overhead as deleting it, with no version matrix.
- **`flutter_tvos` is the opt-in high-level layer** over the raw stream:
  `SwipeEvent`, coordinates, custom swipe zones, scrubbers — already behind
  `addRawListener` / `addSwipeListener` in the package today.

### The real distinction

Not "where does the channel live" but "who makes the decisions":

- **Navigation semantics** (focus, scroll, media) — the platform contract. The
  engine generates these always, for free, no plugin.
- **Gesture interpretation** (detailed swipe, coordinates) — an app UI feature.
  The plugin provides these on demand.

The raw-data channel stays in the engine but costs nothing while unheard.

### Why this beats both alternatives

| | Literal move (out of engine) | "Dumb channel" (always emits raw) | Lazy channel (this) |
|---|---|---|---|
| Plugin-less app: swipe-scroll | breaks | works | works |
| Touches overhead without plugin | none | always pays | none |
| Repeater logic | split across layers | duplicates native state | whole, in engine |
| Engine↔plugin version-locking | broken | partial | preserved |
| Engine thinner for upstreaming | yes | yes | yes (transport only, no policy) |

You get the outcome you asked for — **the engine doesn't pay for advanced
gestures; detailed swipe/coordinates require `flutter_tvos`** — while focus and
swipe-scroll keep working out of the box.

## Implementation sketch (small)

1. Engine: add a `touchStreamEnabled` BOOL on `FlutterTvRemotePlugin`, default
   `false`. Guard the `touchesChannel sendMessage:` at `:716` with it. The
   repeater path (`:700→758`) is untouched.
2. Engine: handle a `setTouchStreamEnabled` method on `flutter/tv_remote` to flip
   the flag.
3. Dart (`flutter_tvos`): send `setTouchStreamEnabled(true)` when the raw/swipe
   listener count goes 0→1, and `false` when it returns to 0.
4. Bonus for upstreaming: with the policy (swipe thresholds, click-bias) already
   in the engine and the raw stream gated, the engine surface is "transport +
   navigation contract" only — the cleanest shape to propose upstream.

## One thing to flag explicitly

Continuous swipe-scroll auto-repeat stays in the engine (item 1), so it keeps
working without the plugin — that's intended. If we ever decide auto-repeat itself
should be opt-in, that's a separate discussion; this proposal does **not** move it.
