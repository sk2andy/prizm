# Design

Keep native SwiftUI lists and split-view resizing. Use one `NSSplitViewController`
with three items: sidebar, result list, and detail. Round the result list's outer
left corners and the detail's outer right corners to form one content surface.
Enforce independent minimum widths: 300 points for the sidebar, 300 for results,
380 for verification codes, and 400 for details. The window minimum follows the
visible columns. Hide and show the sidebar by collapsing its native split item,
keeping the same controller and all three hosting controllers in place. ⌘B toggles
the sidebar with a short native animation, disabled for Reduce Motion. The sidebar
has no fixed maximum width; invisible divider hit areas extend four points per side.
Native divider hit targets stay available for dragging and accessibility; the
split view skips drawing their strokes. Embedded hosting controllers ignore the title-bar
safe area and do not derive native sizing constraints from their SwiftUI content.
The split items enforce column minimums; the representable accepts SwiftUI's
proposed width and height, falling back to the visible column minimums and a
620-point height when unspecified. The browser expands to fill the window.
The sidebar omits the redundant app-name and unlocked-status header.

Search uses a native `NSSearchField` with its built-in search icon disabled.
A decorative SwiftUI magnifying glass sits beside the field, reserving its own
space so focused text and the icon cannot overlap. Native editing, cancellation,
and the search-field accessibility role remain available.

Search always covers non-trashed vault items, including when opened from a folder,
organization, Codes, or Trash. Clearing search restores the prior sidebar scope.
Favorite shortcuts reuse the existing decrypted repository and selection model.
They never persist additional item data.

## Complexity tracking

| Choice | Why | Simpler alternative considered |
|---|---|---|
| `NSSearchField` inside a small `NSViewRepresentable` | SwiftUI's macOS search placement is tied to window chrome; the approved design needs native search/cancel semantics directly above results. | A plain `TextField` loses the native search control and its accessibility role. |
| One `NSSplitViewController` with three items | Independent column minimums, native sidebar collapse, and full-height hosting views within one layout. | `HSplitView` applied inconsistent title-bar insets to its nested hosts, clipping headers; nested native controllers add unnecessary sizing boundaries. |

The existing bundle and credential identity are retained for the installed build;
the approved display name is Luma, with a subtly brushed blue shield icon. UI tests use a separately
identified preview copy with isolated Keychain services.
