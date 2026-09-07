# iOS 26 Liquid Glass — Verified SwiftUI API Reference

Compiled 2026-09-05 from live Apple developer documentation.

## How this was verified (read this first)

Apple's doc site serves a JavaScript shell; the HTML has no content. Three reliable channels
were used instead:

1. Markdown twin — append `.md` to any doc URL (Apple advertises it via
   `<link rel="alternate" type="text/markdown">`). Gives prose, omits member lists.
2. Raw DocC JSON — `https://developer.apple.com/tutorials/data/<doc-path>.json`.
   Gives the exact declaration tokens, per-platform availability, and `topicSections`.
3. Full symbol index — `https://developer.apple.com/tutorials/data/index/swiftui`
   (1.4 MB). Authoritative for "does symbol X exist".
4. Wayback Machine (`web/<ts>id_/…`) to separate WWDC25-beta spellings from shipped 26.0.

**CRITICAL FRAMING:** today is 2026-09-05, so live Apple docs describe the **iOS 27 SDK**
(WWDC June 2026). Every entry below was filtered to `introducedAt <= 26.0`. See
"Appendix A: iOS 27-only APIs — do not use" before copying anything from current web
tutorials or blog posts.

**CRITICAL BETA WARNING:** most Liquid Glass code on the public web (blogs, StackOverflow,
LLM output) uses the WWDC25 beta spelling `glassEffect(_:in:isEnabled:)` with
`in shape: some Shape = .capsule`. That signature **does not exist in shipping iOS 26** and
will not compile. Verified by Wayback diff:

- 2025-06-12 (WWDC25 beta): `glassEffect(_ glass: Glass = .regular, in shape: some Shape = .capsule, isEnabled: Bool = true)`
- 2025-09-06 and later (26.0 GA): `glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())` — **no `isEnabled:`**
- `https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:isenabled:)` returns HTTP 404 today.

---

## 1. `glassEffect(_:in:)` and the `Glass` type

**Availability of every symbol in this section: iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0,
macOS 26.0, tvOS 26.0, watchOS 26.0. NOT visionOS** — visionOS keeps
`glassBackgroundEffect(displayMode:)`.

```swift
nonisolated func glassEffect(
    _ glass: Glass = .regular,
    in shape: some Shape = DefaultGlassEffectShape()
) -> some View
```
Source: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)

```swift
struct Glass                                   // Sendable, SendableMetatype, Equatable
static var regular: Glass                      // the default, adaptive material
static var clear: Glass                        // more transparent; needs a dimming layer
static var identity: Glass                     // no glass; useful to conditionally disable
func tint(_ color: Color?) -> Glass
func interactive(_ isEnabled: Bool = true) -> Glass
```
Source: https://developer.apple.com/documentation/swiftui/glass

```swift
struct DefaultGlassEffectShape                 // documented as "a capsule"; never named directly
```
Source: https://developer.apple.com/documentation/swiftui/defaultglasseffectshape

Shapes accepted: any `Shape`. Apple's own examples use `.rect(cornerRadius:)`, `.capsule`,
`.circle`, and `ConcentricRectangle()`.

Apple's canonical snippets, verbatim from
https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views

```swift
Text("Hello, World!").font(.title).padding().glassEffect()
Text("Hello, World!").font(.title).padding().glassEffect(in: .rect(cornerRadius: 16.0))
Text("Hello, World!").font(.title).padding().glassEffect(.regular.tint(.orange).interactive())
```

`.clear` legibility pattern, verbatim from https://developer.apple.com/documentation/swiftui/glass/clear

```swift
Label("Flag", systemImage: "flag.fill")
    .padding()
    .glassEffect(.clear)
    .background(.black.opacity(0.3))     // Apple: clear glass REQUIRES a dimming layer
```

Conditional glass without an `isEnabled:` parameter (the shipping idiom):

```swift
.glassEffect(isProminent ? .regular : .identity, in: .capsule)
```

---

## 2. `GlassEffectContainer`

Availability: iOS/iPadOS/Mac Catalyst/macOS/tvOS/watchOS 26.0. Not visionOS.

```swift
@MainActor @preconcurrency
struct GlassEffectContainer<Content> where Content : View

@MainActor @preconcurrency
init(spacing: CGFloat? = nil, @ContentBuilder content: () -> Content)
```
Source: https://developer.apple.com/documentation/swiftui/glasseffectcontainer

Note: the live (iOS 27 SDK) docs render the closure as `@ContentBuilder`. In the Xcode 26
SDK it is `@ViewBuilder`. Call sites are byte-identical, so this is cosmetic.

Why it is needed (Apple's stated reasons):
- Glass sampling is expensive. A container lets sibling glass views share **one** sampling
  pass instead of N passes. This is the primary performance lever.
- Only shapes inside the same container can **blend and morph** into each other.
- `spacing:` is the distance at which nearby glass shapes begin to merge. It should
  normally match (or exceed) the layout spacing of the children.

```swift
GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 40.0) {
        Image(systemName: "scribble.variable")
            .frame(width: 80.0, height: 80.0).font(.system(size: 36)).glassEffect()
        Image(systemName: "eraser.fill")
            .frame(width: 80.0, height: 80.0).font(.system(size: 36)).glassEffect()
            .offset(x: -40.0, y: 0.0)      // overlap -> the two capsules fuse
    }
}
```

---

## 3. Morphing: `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`

Availability: 26.0 (same platform set as above).

```swift
nonisolated func glassEffectID(
    _ id: (some Hashable & Sendable)?,
    in namespace: Namespace.ID
) -> some View
```
Source: https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)

```swift
@MainActor @preconcurrency
func glassEffectUnion(
    id: (some Hashable & Sendable)?,
    namespace: Namespace.ID
) -> some View
```
Source: https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)

How morphing works: give each glass view a stable `glassEffectID` in a shared
`@Namespace`, put them all inside one `GlassEffectContainer`, then insert/remove views
inside `withAnimation`. SwiftUI interpolates the glass shape between the old and new sets
rather than fading views in and out.

```swift
@State private var isExpanded = false
@Namespace private var namespace

var body: some View {
    GlassEffectContainer(spacing: 40.0) {
        HStack(spacing: 40.0) {
            Image(systemName: "scribble.variable")
                .frame(width: 80.0, height: 80.0).font(.system(size: 36))
                .glassEffect()
                .glassEffectID("pencil", in: namespace)
            if isExpanded {
                Image(systemName: "eraser.fill")
                    .frame(width: 80.0, height: 80.0).font(.system(size: 36))
                    .glassEffect()
                    .glassEffectID("eraser", in: namespace)
            }
        }
    }
    Button("Toggle") { withAnimation { isExpanded.toggle() } }
        .buttonStyle(.glass)
}
```

`glassEffectUnion` merges several glass views into **one** rendered capsule/shape while
they keep separate layout and hit-testing. Views sharing an `id` are unioned:

```swift
let symbolSet = ["cloud.bolt.rain.fill", "sun.rain.fill", "moon.stars.fill", "moon.fill"]

GlassEffectContainer(spacing: 20.0) {
    HStack(spacing: 20.0) {
        ForEach(symbolSet.indices, id: \.self) { item in
            Image(systemName: symbolSet[item])
                .frame(width: 80.0, height: 80.0).font(.system(size: 36))
                .glassEffect()
                .glassEffectUnion(id: item < 2 ? "1" : "2", namespace: namespace)
        }
    }
}
```

---

## 4. `glassEffectTransition(_:)`

Availability: 26.0.

```swift
@MainActor @preconcurrency
func glassEffectTransition(_ transition: GlassEffectTransition) -> some View

struct GlassEffectTransition
static var identity: GlassEffectTransition        // no glass-specific transition
static var matchedGeometry: GlassEffectTransition // default morph behaviour
static var materialize: GlassEffectTransition     // glass "grows in" / dissolves
```
Sources:
- https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)
- https://developer.apple.com/documentation/swiftui/glasseffecttransition

```swift
Image(systemName: "star.fill").padding().glassEffect()
    .glassEffectID("star", in: namespace)
    .glassEffectTransition(.materialize)
```

---

## 5. Glass button styles

All 26.0 (iOS/iPadOS/Mac Catalyst/macOS/tvOS/watchOS). Confirmed spellings — there is no
`.glassy`, no `.liquidGlass`, no `.prominentGlass`.

```swift
// on PrimitiveButtonStyle
@export(implementation) nonisolated static var glass: GlassButtonStyle
@MainActor @export(implementation) @preconcurrency static var glassProminent: GlassProminentButtonStyle
nonisolated static func glass(_ glass: Glass) -> Self
```
Sources:
- https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass
- https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent
- https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass(_:)

```swift
nonisolated struct GlassButtonStyle            // init()  ; init(_ glass: Glass)  <- init is iOS 26.1+
nonisolated struct GlassProminentButtonStyle   // init()
```
Sources:
- https://developer.apple.com/documentation/swiftui/glassbuttonstyle
- https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle

```swift
Button("Cancel") {}.buttonStyle(.glass)
Button("Save") {}.buttonStyle(.glassProminent)
Button("Button") {}.buttonStyle(.glass(.clear))          // Apple's own example
Button("Tinted") {}.buttonStyle(.glass(.regular.tint(.blue)))
```

Note the availability split: the **static member** `.glass(_:)` is annotated 26.0, but the
**initializer** `GlassButtonStyle.init(_ glass: Glass)` is annotated 26.1. Prefer
`.buttonStyle(.glass(...))` over `GlassButtonStyle(...)` to stay 26.0-safe.

Also: `.buttonBorderShape(_:)` is **not** new in 26 —
`nonisolated func buttonBorderShape(_ shape: ButtonBorderShape) -> some View`, iOS 15.0+.
Source: https://developer.apple.com/documentation/swiftui/view/buttonbordershape(_:)

---

## 6. TabView changes

```swift
nonisolated func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View
// iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, watchOS 26.0

struct TabBarMinimizeBehavior
static var automatic: TabBarMinimizeBehavior
static var never: TabBarMinimizeBehavior
static var onScrollDown: TabBarMinimizeBehavior
static var onScrollUp: TabBarMinimizeBehavior
```
Sources:
- https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)
- https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior

```swift
nonisolated func tabViewBottomAccessory<Content>(@ContentBuilder content: () -> Content) -> some View
    where Content : View
// iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0 ONLY (no macOS / tvOS / watchOS / visionOS)

nonisolated func tabViewBottomAccessory<Content>(isEnabled: Bool, content: () -> Content) -> some View
    where Content : View
```
Sources:
- https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)
- https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)

```swift
enum TabViewBottomAccessoryPlacement       // iOS/iPadOS/Mac Catalyst 26.0
case inline        // sits above the tab bar
case expanded      // tab bar minimized; accessory expanded into its place

var tabViewBottomAccessoryPlacement: TabViewBottomAccessoryPlacement?   // EnvironmentValues
```
Sources:
- https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement
- https://developer.apple.com/documentation/swiftui/environmentvalues/tabviewbottomaccessoryplacement

Full working shape (the "Music mini-player" pattern):

```swift
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { HomeView() }
            Tab("Library", systemImage: "square.stack") { LibraryView() }
            Tab(role: .search) { SearchView() }        // TabRole.search is iOS 18.0+
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { MiniPlayer() }
    }
}

struct MiniPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var body: some View {
        switch placement {
        case .expanded: FullPlayerControls()
        default:        CompactPlayerRow()
        }
    }
}
```

`Tab` initialisers and roles (all pre-existing iOS 18.0 API, unchanged in 26):
`Tab(_:systemImage:content:)`, `Tab(_:image:content:)`, `Tab(value:content:)`,
`Tab(role:content:)`; `TabRole.search` (iOS 18.0+).
`TabSection` for sidebar grouping. `.tabViewStyle(_:)` options: `.automatic`,
`.sidebarAdaptable`, `.tabBarOnly`, `.grouped`, `.page`, `.page(indexDisplayMode:)`,
`.verticalPage`, `.carousel`. **No new iOS 26 tabViewStyle case was added.**
Sources: https://developer.apple.com/documentation/swiftui/tabviewstyle ,
https://developer.apple.com/documentation/swiftui/tabrole/search

**Do not use `TabRole.prominent`** — that is a June 2026 / iOS 27 addition.

---

## 7. Scroll edge effects and `backgroundExtensionEffect()`

**The parameter type is `Edge.Set`, NOT `VerticalEdge.Set`.** Verified three ways: the
symbol page, the full SwiftUI index, and the 2025-06-12 WWDC25 Wayback snapshot (which
already read `Edge.Set`). Any code you find using `VerticalEdge.Set` here is wrong.

```swift
nonisolated func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View
// iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0

struct ScrollEdgeEffectStyle
static var automatic: ScrollEdgeEffectStyle   // system decides
static var hard: ScrollEdgeEffectStyle        // crisp division line at the edge
static var soft: ScrollEdgeEffectStyle        // gradual blur/fade

nonisolated func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> some View
```
Sources:
- https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)
- https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle
- https://developer.apple.com/documentation/swiftui/view/scrolledgeeffecthidden(_:for:)

```swift
ScrollView { content }
    .scrollEdgeEffectStyle(.soft, for: .top)
    .scrollEdgeEffectStyle(.hard, for: .bottom)
```

```swift
@MainActor @preconcurrency func backgroundExtensionEffect() -> some View     // 26.0
func backgroundExtensionEffect(isEnabled: Bool) -> some View
```
Source: https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()

Mirrors and blurs a view's own edges outward under adjacent bars/safe areas, so a hero
image appears to flow behind the sidebar or under the status bar. Apply it to the image,
not the container:

```swift
Image("hero").resizable().scaledToFill()
    .containerRelativeFrame(.horizontal)
    .backgroundExtensionEffect()
```

```swift
// Custom floating bars that correctly inset the safe area AND extend scroll edge effects
nonisolated func safeAreaBar(edge: VerticalEdge, alignment: HorizontalAlignment = .center,
                             spacing: CGFloat? = nil,
                             @ContentBuilder content: () -> some View) -> some View
nonisolated func safeAreaBar(edge: HorizontalEdge, alignment: VerticalAlignment = .center,
                             spacing: CGFloat? = nil,
                             @ContentBuilder content: () -> some View) -> some View
// both: iOS/iPadOS/Mac Catalyst/macOS/tvOS/visionOS/watchOS 26.0
```
Source: https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)
(and the disambiguated `-9hwgb` variant for `VerticalEdge`)

Prefer `safeAreaBar` over `safeAreaInset` for glass bars: only `safeAreaBar` extends the
scroll edge effect of the inset scroll view.

---

## 8. Navigation and toolbars

```swift
nonisolated struct ToolbarSpacer                       // iOS/iPadOS/Mac Catalyst/macOS 26.0 only
nonisolated init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic)

struct SpacerSizing                                     // 26.0
static var fixed: SpacerSizing
static var flexible: SpacerSizing
```
Sources:
- https://developer.apple.com/documentation/swiftui/toolbarspacer
- https://developer.apple.com/documentation/swiftui/spacersizing

In iOS 26 toolbar items automatically merge into a single shared glass capsule.
`ToolbarSpacer` is how you split them into separate glass groups:

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) { Button("Edit") {} }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)      // breaks the shared capsule
    ToolbarItem(placement: .topBarTrailing) { Button { } label: { Image(systemName: "plus") } }
}
```

```swift
nonisolated func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent
nonisolated func sharedBackgroundVisibility(_ visibility: Visibility) -> some CustomizableToolbarContent
// iOS/iPadOS/Mac Catalyst/macOS 26.0
```
Source: https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)

Applied to a `ToolbarItem`/`ToolbarItemGroup` to remove that item from the shared glass
background (e.g. a bare avatar image that should not sit on a capsule):

```swift
ToolbarItem(placement: .topBarTrailing) {
    Image("avatar").clipShape(.circle)
}
.sharedBackgroundVisibility(.hidden)
```

**Not new in 26** (do not present these as Liquid Glass API):

```swift
nonisolated func toolbarBackgroundVisibility(_ visibility: Visibility,
                                             for bars: ToolbarPlacement...) -> some View   // iOS 18.0+
nonisolated func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View // iOS 15.0+
nonisolated func toolbar(removing: ToolbarDefaultItemKind?) -> some View                    // iOS 18.0+
```
Source: https://developer.apple.com/documentation/swiftui/view/toolbarbackgroundvisibility(_:for:)

### NavigationStack large titles

No new iOS 26 API. `.navigationTitle`, `.navigationBarTitleDisplayMode(.large/.inline)`
are unchanged (iOS 14.0+/16.0+). What changed is **rendering**: the nav bar background is
now Liquid Glass, it is transparent when content is scrolled to top, and it condenses into
a glass capsule as you scroll. Recompiling against the iOS 26 SDK is what opts you in.
Custom `.toolbarBackground(.hidden, for: .navigationBar)` hacks written for iOS 15-18
usually need to be **deleted** — they defeat the new scroll edge effect.
Source: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass

### Search

```swift
nonisolated func searchToolbarBehavior(_ behavior: SearchToolbarBehavior) -> some View   // 26.0

struct SearchToolbarBehavior
static var automatic: SearchToolbarBehavior
static var minimize: SearchToolbarBehavior     // iOS/iPadOS/Mac Catalyst/visionOS 26.0
```
Sources:
- https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:)
- https://developer.apple.com/documentation/swiftui/searchtoolbarbehavior

**Documentation bug to be aware of:** Apple's own example on that page writes
`.searchToolbarBehavior(.minimized)`. The real symbol is `.minimize`. Use `.minimize`.

`.searchable` itself gained **no new overloads** in iOS 26. The full set is still the
iOS 16/18 family: `searchable(text:placement:prompt:)`,
`searchable(text:isPresented:placement:prompt:)`, and the `tokens:` /
`editableTokens:` / `suggestedTokens:` variants. `placement` and `prompt` have defaults, so
`.searchable(text: $query)` compiles. What changed in 26 is placement behaviour: on iPhone
a `.searchable` on the root of a `NavigationStack` renders as a **bottom** glass search
field; inside a `TabView` you should instead use a dedicated `Tab(role: .search)`.
Source: https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)

```swift
NavigationStack {
    List { /* ... */ }
        .searchable(text: $query)
        .searchToolbarBehavior(.minimize)     // collapse to a glass magnifier button
}
```

---

## 9. Sheets, presentation, and corner concentricity

Sheets are automatic. Recompiling against the iOS 26 SDK gives every `.sheet` the new
inset glass appearance with concentric corners; partial-height sheets get a glass edge
treatment and the content behind them scales back. **There is no `glassSheet` modifier and
no new sheet API.** Do not add `.presentationBackground(.clear)` "to get glass" — that
removes the system glass. Apple explicitly says to remove custom sheet backgrounds you
added on older OSes.
Source: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass

```swift
nonisolated func presentationBackground<S>(_ style: S) -> some View where S : ShapeStyle
nonisolated func presentationBackground<V>(alignment: Alignment = .center,
                                           content: () -> V) -> some View where V : View
// iOS 16.4+ — NOT new in 26
```
Source: https://developer.apple.com/documentation/swiftui/view/presentationbackground(_:)

### Concentric corners

**`RoundedRectangle(cornerRadius: .containerConcentric)` does not exist.** I verified this:
`/documentation/swiftui/containerconcentric` returns 404, and `RoundedRectangle` still has
only `init(cornerRadius:style:)` and `init(cornerSize:style:)`. Any snippet using
`.containerConcentric` as a `CGFloat` will not compile. The real API:

```swift
struct ConcentricRectangle          // iOS/iPadOS/Mac Catalyst/macOS/tvOS/visionOS/watchOS 26.0
init()                                                          // every corner individually concentric
init(corners: Edge.Corner.Style, isUniform: Bool)               // same style on all corners
// plus per-corner and uniform (top/bottom/leading/trailing) initialisers

// on Shape:
static func rect(corners: Edge.Corner.Style, isUniform: Bool) -> Self     // 26.0

struct Edge.Corner.Style                                    // 26.0
static var concentric: Edge.Corner.Style
static func concentric(minimum: CGFloat) -> Edge.Corner.Style
static func fixed(_ radius: CGFloat) -> Edge.Corner.Style

nonisolated func containerShape(_ shape: some RoundedRectangularShape) -> some View   // 26.0
struct RoundedRectangularShapeCorners                       // .concentric, .concentric(minimum:), .fixed(_:)
var GeometryProxy.concentricCornerRadii                     // 26.0, for manual math
```
Sources:
- https://developer.apple.com/documentation/swiftui/concentricrectangle
- https://developer.apple.com/documentation/swiftui/view/containershape(_:)

```swift
// A card whose corners stay concentric with whatever container it sits in
VStack { content }
    .padding(16)
    .glassEffect(in: ConcentricRectangle())

// Or drive it from the enclosing container's corner radius
ScrollView { cards }
    .containerShape(.rect(corners: .concentric(minimum: 12)))
```

---

## 10. `List` and `Form`

**Finding: iOS 26 added no new `List` / `Form` API.** I enumerated the full SwiftUI symbol
index; there is no new list style, no `glassRow`, no list-glass modifier. All changes are
rendering changes you get by recompiling. Apple's guidance
(https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass):

- Lists and forms adopt the new inset/rounded look with more generous spacing.
- Section headers and grouped-list backgrounds are redrawn; sidebars pick up glass.
- **Remove** custom row backgrounds, custom separators, and hard-coded row insets you added
  to imitate the system look on iOS 15-18 — they now fight the system rendering.
- Use `.listRowBackground(Color.clear)` (or nothing at all) rather than painting your own
  material behind rows.

```swift
nonisolated func listRowBackground<V>(_ view: V?) -> some View where V : View   // iOS 13.0+, not new
```
Source: https://developer.apple.com/documentation/swiftui/view/listrowbackground(_:)

**Do not put `.glassEffect()` on `List` rows.** Rows already sit on the list's own material;
stacking glass on glass produces muddy, low-contrast rows and multiplies the sampling cost
per visible row. Apple's rule is that glass is for the floating navigation/control layer,
not the content layer. If you need a card look inside a list, use
`.listRowBackground(RoundedRectangle(...).fill(.background.secondary))` instead.

---

## 11. The Info.plist opt-out key

```xml
<key>UIDesignRequiresCompatibility</key>
<true/>
```
Source: https://developer.apple.com/documentation/BundleResources/Information-Property-List/UIDesignRequiresCompatibility

- Setting it to `YES`/`true` makes an app built with the iOS 26 SDK keep the
  **pre-iOS-26 (legacy) appearance**. It is an escape hatch for apps that cannot be
  updated in time. Absence of the key (or `NO`) is the default and means full Liquid Glass.
- Availability: iOS 26.0, iPadOS 26.0, macOS 26.0, tvOS 26.0.
- Apple's warning, verbatim: "Temporarily use this key while reviewing and refining your
  app's UI for the design in the latest SDKs." And explicitly: "The system **ignores this
  key** when you build for iOS 27 or later, iPadOS 27 or later, Mac Catalyst 27 or later,
  macOS 27 or later, or tvOS 27 or later." So it is already a dead end.

**To ADOPT Liquid Glass you need nothing in Info.plist.** Adoption is automatic when you
build against the iOS 26 SDK with Xcode 26. There is no opt-in key, no entitlement, and no
build setting to enable. This is the single most common misconception.

---

## 12. App icons under Xcode 26

### What Xcode 26 expects

- A **single 1024x1024 universal PNG** in `Assets.xcassets/AppIcon.appiconset` is sufficient
  and is what Xcode 26 generates for new projects. The legacy 15-to-20-entry per-size
  matrix has not been required since Xcode 14 and is not required now.
- The system generates all smaller sizes, plus the Liquid Glass specular/refraction
  treatment, at build/render time from your 1024 artwork.
- An **Icon Composer `.icon` file is OPTIONAL**, not required. `.icon` is the new
  multi-layer format that lets the system produce proper depth, specular highlights and
  the Clear/Dark/Tinted variants. Without it you still ship a valid icon; you just get a
  flat single-layer icon that the system masks and lights generically.
- Build setting `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` selects the icon set. This
  is unchanged. If you ship an `.icon`, that same setting names it.

Sources:
- https://developer.apple.com/documentation/Xcode/configuring-your-app-icon
- https://developer.apple.com/documentation/TechnologyOverviews/app-icons
- https://developer.apple.com/icon-composer/

### Exact `Contents.json` for a single 1024 universal iOS icon

`Assets.xcassets/AppIcon.appiconset/Contents.json`

```json
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Notes verified against Apple's own sample-code repositories:
- There is **no `"scale"` key** for the single-size universal entry. Adding `"scale": "1x"`
  is what most hand-written examples get wrong.
- `"idiom" : "universal"` plus `"platform" : "ios"` is the shipping combination.
- The PNG must be exactly 1024x1024, sRGB, **fully opaque** (no alpha channel with
  transparency) — a transparent light-appearance icon fails App Store upload with
  ITMS error 90717.

Also required: `Assets.xcassets/Contents.json` must exist and contain only the info block:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Optional dark and tinted variants (add alongside the light entry in the same `images`
array; each needs its own `filename`):

```json
{
  "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
  "filename" : "AppIcon-Dark.png",
  "idiom" : "universal",
  "platform" : "ios",
  "size" : "1024x1024"
},
{
  "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
  "filename" : "AppIcon-Tinted.png",
  "idiom" : "universal",
  "platform" : "ios",
  "size" : "1024x1024"
}
```
The dark and tinted PNGs **may** have transparency (Apple expects them to omit the
background); only the light one must be opaque.

UNVERIFIED items in this section, with best guesses:
- Whether `"platform" : "ios"` is strictly *required* by `actool`, or merely what Xcode
  writes. Best guess: it is optional for a single-platform iOS target but harmless and
  safer to include. Keep it.
- The exact hand-authorable internal schema of an Icon Composer `.icon` bundle. It is a
  directory with a JSON manifest plus layer assets, but Apple documents no public schema.
  Best guess: do not hand-author `.icon`; ship the 1024 PNG asset catalog instead.
- The `actool` flag `--enable-icon-stack-fallback-generation=disabled`. I found references
  to icon-stack fallback generation but could not confirm this exact flag spelling on
  developer.apple.com. Best guess: do not pass it; leave defaults.

---

## 13. Toolchain, SDK, and CI

### Xcode and SDK

- **Xcode 26.0 or later is required** to compile against the iOS 26 SDK and therefore to
  get Liquid Glass. Xcode 26.0.1 is the first stable patch; 26.6 is current.
- iOS SDK canonical name: **`iphoneos26.0`** (simulator: `iphonesimulator26.0`). Later
  point releases follow the same pattern: `iphoneos26.1` … `iphoneos26.5`.
- `IPHONEOS_DEPLOYMENT_TARGET`: set to **`26.0`** if you want to use the new API
  unconditionally with no `@available` guards. Xcode 26 still *supports* deployment targets
  down to iOS 15, so a lower target is legal — you then need availability guards
  (see section 14). Note: "macOS 15.6" that circulates in this context is the **host**
  macOS requirement for running Xcode 26, not a deployment target.
- App Store requirement: since **28 April 2026** new submissions must be built with the
  iOS 26 SDK (Xcode 26) or later, so targeting the iOS 26 SDK is mandatory anyway.

### GitHub Actions runner

Use the **`macos-26`** label (Apple silicon; it is also what `macos-latest` currently
points at). Verified from actions/runner-images `main` today:

| Runner label | Arch | Xcode versions installed | Default Xcode |
|---|---|---|---|
| `macos-26` (= `macos-latest`) | arm64 | 26.0.1, 26.1.1, 26.2, 26.3, 26.4.1, 26.5, 26.6 | 26.6 |
| `macos-26-intel` / `macos-26-large` | x64 | same family | 26.6 |
| `macos-15` | both | Xcode 16.x only — **no iOS 26 SDK** | — |

Installed iOS SDKs on `macos-26`: `iphoneos26.0` … `iphoneos26.5` (26.0 comes with
Xcode 26.0.1). Installed **simulator runtimes** start at **iOS 26.2** — there is no
iOS 26.0 or 26.1 simulator runtime on the image, so do not pin `OS=26.0` in a destination.

Sources:
- https://github.com/actions/runner-images/blob/main/README.md
- https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md

Recommended workflow fragment:

```yaml
jobs:
  build:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode 26
        run: sudo xcode-select -s /Applications/Xcode_26.0.1.app
      - name: Build
        run: |
          xcodebuild clean build \
            -project MyApp.xcodeproj \
            -scheme MyApp \
            -destination 'generic/platform=iOS Simulator' \
            CODE_SIGNING_ALLOWED=NO | xcpretty
```

Pinning `Xcode_26.0.1.app` gives you exactly the 26.0 SDK. If you prefer the image default
(26.6), omit the `xcode-select` step. Use `generic/platform=iOS Simulator` rather than a
named device+OS pair so the job does not break when the image's simulator inventory rotates.

---

## 14. Pitfalls

Ordered by how likely they are to bite. Guidance sourced from
https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass and
https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views

1. **Wrong `glassEffect` signature.** Using the beta `isEnabled:` parameter or
   `in shape: .capsule` default is the single most common compile failure. See the warning
   at the top of this file. Use `.identity` glass to conditionally disable instead.

2. **Too many independent glass effects.** Each `glassEffect` outside a container is its own
   sampling + blur pass. Apple's explicit guidance: "Use Liquid Glass sparingly" and put
   related effects in a single `GlassEffectContainer`. Never apply glass in a `ForEach` over
   a long collection.

3. **Nesting `GlassEffectContainer`s or nesting glass in glass.** Apple warns against
   layering glass on glass — the refraction compounds and legibility collapses. One glass
   layer over content, never two.

4. **`glassEffect` on scrolling content.** Glass is for the *floating* layer above content:
   toolbars, tab bars, floating action buttons, `safeAreaBar` content. Putting it on rows
   or cells that scroll means the material re-samples every frame for every visible cell.
   It also looks wrong, because glass is supposed to read as "above" the content.

5. **`glassEffect` inside `List` rows.** Specifically discouraged: rows already sit on the
   list material, so you get glass-on-glass (pitfall 3) times N rows (pitfall 2). Use
   `.listRowBackground` with a solid or `.secondary` fill for card looks.

6. **Glass over custom / busy backgrounds.** `Glass.regular` adapts to what is behind it,
   but `Glass.clear` does not carry enough contrast on its own. Apple's own rule for
   `.clear`: it is intended for media-rich content and **requires a dimming layer** behind
   the content (their example adds `.background(.black.opacity(0.3))`). Over photos or
   gradients, prefer `.regular`, and verify with Increase Contrast and Reduce Transparency
   accessibility settings enabled.

7. **Fighting the system.** Delete iOS 15-18 era workarounds: custom `UIBlurEffect`/
   `.ultraThinMaterial` bar backgrounds, `.toolbarBackground(.hidden, ...)` hacks,
   custom sheet backgrounds, hand-drawn tab bars, hard-coded corner radii on sheets. Under
   iOS 26 these actively suppress the new look. Concentric corners are the correct
   replacement for hard-coded radii.

8. **Tinting for decoration.** `Glass.tint(_:)` is documented for conveying *meaning*
   (a prominent/primary action), not styling. Overusing tint on many controls destroys the
   visual hierarchy the design system is built on.

9. **Morphing without a container or without stable IDs.** `glassEffectID` only morphs
   inside a `GlassEffectContainer`, and only if the IDs are stable across the state change
   and the change happens inside `withAnimation`. Miss any of the three and you get a plain
   fade.

10. **`Edge.Set` vs `VerticalEdge.Set`** on `scrollEdgeEffectStyle` / `scrollEdgeEffectHidden`.
    It is `Edge.Set`.

11. **`.containerConcentric` does not exist.** Use `ConcentricRectangle` /
    `.rect(corners: .concentric)` / `containerShape(_:)`.

12. **visionOS is different.** `glassEffect`, `GlassEffectContainer` and the glass button
    styles are **not** available on visionOS. visionOS uses
    `glassBackgroundEffect(displayMode:)` and the `GlassBackgroundEffect` family
    (`.automatic`, `.plate`, `.feathered(padding:softEdgeRadius:)`). Do not `#if os(visionOS)`
    into the iOS API.

### `@available` guards

**Required only if `IPHONEOS_DEPLOYMENT_TARGET` is below 26.0.** Every symbol in this
document is annotated `iOS 26.0`, so with a 26.0 deployment target you call them directly
with no guards and no `if #available`.

If you support iOS 18 and earlier as well, the ergonomic pattern is a conditional
`ViewModifier` rather than duplicating whole view trees:

```swift
extension View {
    @ViewBuilder
    func glassCapsuleIfAvailable(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: .capsule)
        }
    }
}
```

Note that `@available(iOS 26.0, *)` on a `struct` that *stores* an iOS-26-only type
(e.g. a `Glass` property) is also needed; guarding only the `body` is not enough in that
case.

---

## Appendix A: iOS 27-only APIs — do NOT use in an iOS 26 app

These appear in the *current* live docs and in current blog posts, but were introduced in
the June 2026 (iOS 27 / Xcode 27) release. Using them breaks an iOS 26 build.
Source: https://developer.apple.com/documentation/updates/swiftui (the "June 2026" section;
the "June 2025" section is the authoritative iOS 26 new-API list).

- `TabRole.prominent`
- `ToolbarOverflowMenu`
- `toolbarMinimizeBehavior(_:for:)`
- `visibilityPriority(_:)`
- `NavigationTransition.crossFade`
- `@ContentBuilder` as a user-facing attribute (in Xcode 26 the same parameters are
  `@ViewBuilder`; call sites are identical, so this only matters if you write the attribute
  yourself)
- `contentToolbar(for:content:)` — UNVERIFIED which release; treat as post-26 and avoid

Also note `GlassButtonStyle.init(_ glass: Glass)` is iOS **26.1**, not 26.0. Prefer the
static member `.glass(_:)`.

## Appendix B: complete iOS 26 symbol checklist

Everything below was individually confirmed present with `introducedAt == 26.0`:

```
Glass, Glass.regular, Glass.clear, Glass.identity, Glass.tint(_:), Glass.interactive(_:)
DefaultGlassEffectShape
View.glassEffect(_:in:)
GlassEffectContainer, GlassEffectContainer.init(spacing:content:)
View.glassEffectID(_:in:)
View.glassEffectUnion(id:namespace:)
View.glassEffectTransition(_:)
GlassEffectTransition.identity / .matchedGeometry / .materialize
PrimitiveButtonStyle.glass / .glassProminent / .glass(_:)
GlassButtonStyle, GlassProminentButtonStyle
View.tabBarMinimizeBehavior(_:)
TabBarMinimizeBehavior.automatic / .never / .onScrollDown / .onScrollUp
View.tabViewBottomAccessory(content:) / (isEnabled:content:)
TabViewBottomAccessoryPlacement.inline / .expanded
EnvironmentValues.tabViewBottomAccessoryPlacement
View.scrollEdgeEffectStyle(_:for:)   [Edge.Set]
View.scrollEdgeEffectHidden(_:for:)  [Edge.Set]
ScrollEdgeEffectStyle.automatic / .hard / .soft
View.backgroundExtensionEffect() / (isEnabled:)
View.safeAreaBar(edge:alignment:spacing:content:)  [VerticalEdge and HorizontalEdge]
ToolbarSpacer, SpacerSizing.fixed / .flexible
ToolbarContent.sharedBackgroundVisibility(_:)
View.searchToolbarBehavior(_:), SearchToolbarBehavior.automatic / .minimize
ConcentricRectangle, Shape.rect(corners:isUniform:)
Edge.Corner.Style.concentric / .concentric(minimum:) / .fixed(_:)
View.containerShape(_:) [RoundedRectangularShape], RoundedRectangularShapeCorners
GeometryProxy.concentricCornerRadii
UIDesignRequiresCompatibility (Info.plist)
```

## Appendix C: source URLs relied on

Apple — design and adoption guidance:
- https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass
- https://developer.apple.com/documentation/TechnologyOverviews/app-icons
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/updates/swiftui

Apple — SwiftUI symbols:
- https://developer.apple.com/documentation/swiftui/glass
- https://developer.apple.com/documentation/swiftui/glass/clear
- https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- https://developer.apple.com/documentation/swiftui/defaultglasseffectshape
- https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)
- https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)
- https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)
- https://developer.apple.com/documentation/swiftui/glasseffecttransition
- https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass
- https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent
- https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass(_:)
- https://developer.apple.com/documentation/swiftui/glassbuttonstyle
- https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)
- https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior
- https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)
- https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement
- https://developer.apple.com/documentation/swiftui/environmentvalues/tabviewbottomaccessoryplacement
- https://developer.apple.com/documentation/swiftui/tabrole/search
- https://developer.apple.com/documentation/swiftui/tabviewstyle
- https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)
- https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle
- https://developer.apple.com/documentation/swiftui/view/scrolledgeeffecthidden(_:for:)
- https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()
- https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)
- https://developer.apple.com/documentation/swiftui/toolbarspacer
- https://developer.apple.com/documentation/swiftui/spacersizing
- https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)
- https://developer.apple.com/documentation/swiftui/view/toolbarbackgroundvisibility(_:for:)
- https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:)
- https://developer.apple.com/documentation/swiftui/searchtoolbarbehavior
- https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)
- https://developer.apple.com/documentation/swiftui/concentricrectangle
- https://developer.apple.com/documentation/swiftui/view/containershape(_:)
- https://developer.apple.com/documentation/swiftui/view/presentationbackground(_:)
- https://developer.apple.com/documentation/swiftui/view/listrowbackground(_:)
- https://developer.apple.com/documentation/swiftui/view/buttonbordershape(_:)

Apple — bundle resources, Xcode, icons:
- https://developer.apple.com/documentation/BundleResources/Information-Property-List/UIDesignRequiresCompatibility
- https://developer.apple.com/documentation/Xcode/configuring-your-app-icon
- https://developer.apple.com/icon-composer/

CI:
- https://github.com/actions/runner-images/blob/main/README.md
- https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md

Machine-readable channels used for exact declarations:
- https://developer.apple.com/tutorials/data/index/swiftui  (full SwiftUI symbol index)
- https://developer.apple.com/tutorials/data/<doc-path>.json  (raw DocC per symbol)
- http://web.archive.org/web/20250612042843id_/...  (WWDC25 beta signatures, for diffing)
