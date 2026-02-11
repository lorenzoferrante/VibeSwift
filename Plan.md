# SwiftLite + ViewTree IR + SwiftUI Renderer Plan (iOS 26)

This plan describes an architecture to build:

1. An interpreter that parses/evaluates **Swift-like code (Swift subset)**  
2. Scripts output a **ViewTree IR** + **Action handlers**  
3. A host app renders IR → **`AnyView`** (compiled SwiftUI)  
4. User interaction triggers **action → interpreter → state update → new IR → re-render**

The design is aligned with modern SwiftUI data flow on **iOS 26**, using **Observation (`@Observable`)** and **`@Bindable`** for two-way mutations where appropriate.

---

## Architecture overview

### Modules

1) **SwiftLite Interpreter**
- Parses/evaluates a Swift-like subset.
- Ships a small “standard library” that exposes `UI.*` constructors to build a `ViewTree` IR.
- Exposes an action system: scripts register handlers by name/id.

2) **ViewTree IR**
- Pure data model: nodes, props, modifiers, layout, accessibility, navigation, event hooks.
- Stable serialization (JSON or binary) for debugging, hot reload, and snapshot tests.

3) **SwiftUI Renderer**
- Converts IR → `AnyView` (compiled).
- Owns a single observable runtime store SwiftUI can observe.
- Updates happen by changing observable state → SwiftUI invalidates → renderer recomputes views.

4) **Runtime Store + Dispatcher**
- Holds script state (dynamic object/dictionary) + UI transient state (optional).
- Dispatches actions: UI event → interpreter handler → state mutation → new IR → publish.

---

## Phase 0 — Constraints & goals

Define the boundaries so you don’t accidentally require the full Swift compiler.

### Decide what the “Swift subset” includes
Recommended:
- Expressions: literals, arrays/dicts, arithmetic, boolean logic
- Control flow: `if` (optionally `switch`)
- Functions: defs/calls
- Closures: restricted (no escaping captures by default)
- Member access on dynamic values or host objects (limited)

Avoid in v1:
- Generics, macros, protocol conformances, `some View`, result builders
- Defining new Swift types that the host must compile (no runtime SwiftUI type synthesis)

### Decide what scripts are allowed to do
- Construct IR (pure)
- Maintain app state (mutable store)
- Handle actions/events
- Call a small set of host “native intrinsics” (time/random/logging; networking optional)

---

## Phase 1 — ViewTree IR v1 (design first, then implement)

### 1) IR schema (core)

Define a small but extensible node set.

#### Node
- `id: String` (stable across renders when possible)
- `type: String` (e.g., `Text`, `Button`, `VStack`, `Image`, `List`, `ForEach`)
- `props: [String: Value]` (text/font/spacing/url/etc.)
- `children: [Node]`
- `modifiers: [Modifier]`
- `events: [EventHook]` (e.g., `.tap -> actionId`, `.onAppear -> actionId`, `.onChange(path) -> actionId`)

#### Value
- Primitives + arrays/maps
- Plus references:
  - `StateRef(path: "cart.items[3].qty")`

#### Bindings
- `BindingRef(path: String)` representing two-way bindings (`TextField`, `Toggle`, `Slider`).

### 2) State model contract

Scripts **do not** produce `@State` / `@Binding` directly. Instead they:
- Read from a dynamic store:
  - `state.get("path")`
- Write via:
  - `state.set("path", value)`
- Create bindings via:
  - `state.bind("path")` returning a `BindingRef`

In the renderer, `BindingRef` becomes a real SwiftUI `Binding<T>`.

### 3) Versioning

Add:
- `irVersion`
- feature flags / capability list

This lets scripts and renderer evolve independently.

---

## Phase 2 — Runtime Store built on Observation (iOS 26) (3–7 days)

### 1) Create a single observable runtime

Use Observation for the source of truth SwiftUI watches.

Recommended shape:
- `@Observable final class RuntimeStore { var state: [String: Value]; var ir: ViewTree }`

Behavior:
- Changes to `ir` trigger re-render.
- Changes to `state` either:
  - recompute IR immediately, or
  - recompute on next action/tick (choose one policy and keep it consistent).

### 2) Bindings strategy (typed at the edge)

Because your state is dynamic, create typed binding helpers:
- `bindingBool(_ path: String) -> Binding<Bool>`
- `bindingString(_ path: String) -> Binding<String>`
- `bindingDouble(_ path: String) -> Binding<Double>`
- etc.

Internally these read/write `RuntimeStore.state` and can optionally dispatch “didSet” hooks.

In SwiftUI views, use:
- `@Bindable var store: RuntimeStore`

…to mutate observable properties cleanly and keep the renderer simple.

---

## Phase 3 — SwiftUI Renderer v1 (IR → AnyView) (1–2 weeks)

### 1) Render pipeline
- `Renderer.render(ir: ViewTree, store: RuntimeStore) -> AnyView`
- A large `switch node.type` producing compiled SwiftUI primitives.
- Modifiers applied in a canonical order (important for consistent behavior).

### 2) Navigation & presentation
Model these as nodes/modifiers early:
- `NavigationStack`
- `NavigationLink(destinationId:)`
- `sheet`, `fullScreenCover`, `alert`, `confirmationDialog`

Keep it data-driven:
- presentation controlled by state paths (e.g., `state["ui.sheet"] = "settings"`).

### 3) Lists & identity
Implement `ForEach` with stable IDs:
- IR must supply an `id` or a key-path to compute it.
- Otherwise SwiftUI diffing becomes unstable and performance suffers.

### 4) Performance guardrails
- Cache subtrees by `(node.id + hash(props))` to avoid rebuilding huge sections.
- Track dirty state paths to selectively recompute IR or subtrees (optional optimization).

---

## Phase 4 — Interpreter v1 (Swift-like subset that outputs IR) (2–4 weeks)

### 1) Parser + AST
- Tokenizer → recursive descent parser
- AST nodes: literals, binary/unary ops, call expr, member access, `if`, function decl, return

### 2) Evaluation model
Use a **bytecode VM** (recommended) or direct AST evaluation.

Add safety limits:
- instruction limit / time slice
- max allocations
- recursion depth cap

### 3) UI DSL (in script)
Expose a Swift-like API that builds IR (not real SwiftUI):

```swift
func body() -> Node {
  VStack(spacing: 12) {
    Text(state.get("title"))
    Toggle("Enabled", isOn: state.bindBool("enabled"))
    Button("Save", action: "saveTapped")
  }
}
```

### 4) Action handlers
Scripts register actions in a dictionary:
- `actions["saveTapped"] = { ctx in ... }`

Handler behavior:
- mutate state
- return:
  - `nil` (host will re-run `body()`), or
  - a new IR directly (fast path)

---

## Phase 5 — Event loop & re-render semantics (1 week)

### 1) Single render entrypoint
- `recomputeIR(reason: RenderReason)`
  - calls interpreter `body()`
  - updates `store.ir`
  - SwiftUI updates automatically because `store` is observable.

### 2) Action dispatch
- UI event → `dispatch(actionId, payload)`
- Runs in a controlled context:
  - publish changes on `MainActor` (UI consistency)
  - interpreter may run off-main, but must publish on main

### 3) Dependency tracking (optional)
Track which state paths were read during `body()`:
- only recompute IR when those paths change

This mimics SwiftUI’s dependency tracking, but at the scripting layer.

---

## Phase 6 — “SwiftUI state management feel” mapping (ongoing)

How the SwiftUI concepts map in this architecture:

- **`@Observable`**  
  Use it for `RuntimeStore` (and optionally host models) so view invalidation is reliable.

- **`@Bindable`**  
  Use it inside the renderer layer when you need two-way mutations of observable properties.

- **`@State`**  
  Don’t replicate directly in scripts. Model “local view state” as either:
  - store-backed namespaced paths (e.g., `"local.<viewId>.isExpanded"`), or
  - host-only local state for performance (advanced later).

- **`@Binding`**  
  Represent as `BindingRef(path:)` in IR and turn into a real typed `Binding<T>` at render time.

- **Environment**  
  Make it explicit in IR via modifiers:
  - `.environment("locale", ...)`
  - `.environmentObjectRef("userSession")`

---

## Phase 7 — Tooling: hot reload, debugging, safety (1–2 weeks)

- **IR inspector overlay**: tap any view → show node id/type/props/state paths read
- **Script stack traces**: map VM frames back to source locations
- **Sandbox**: restrict native intrinsics and side effects
- **Persistence**: store script + state snapshots for crash repro

---

## MVP milestone checklist

A good first end-to-end MVP:

- Interpreter: literals, calls, `if`, functions, restricted closures
- IR nodes: `Text`, `Button`, `VStack/HStack`, `Image`, `Spacer`, `TextField`, `Toggle`
- Actions: button tap mutates `state`, triggers IR recompute
- Bindings: `TextField` edits `state["name"]`
- Renderer: `AnyView` output + basic modifiers (`padding`, `font`, `foregroundStyle`, `frame`, `background`)
