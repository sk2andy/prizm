- [x] Implement the approved sidebar, result list, and detail design.
- [x] Place native global search above results and cover folder search regression.
- [x] Verify native resizing, search, favorite selection, and existing code journeys.
- [x] Obtain approval for the fork name and icon, then apply branding.
- [x] Capture real app views using fictional data and update README imagery.
- [x] Run available checks, build/analyze Release, and install in /Applications.

## Validation — 2026-11-16

| Check | Result |
|---|---|
| Full unit suite with Address Sanitizer | 561 passed before final visual adjustments |
| Final Release build and analyzer | Passed; arm64 and x86_64, macOS 15 minimum |
| Final UI test compilation | Passed |
| Earlier UI runs | 19 distinct journeys passed across focused runs |
| Final automated test rerun | Blocked during XCTest/IDE session setup; no test assertions ran |
| Native checks | Three clean preview launches; dynamic column minimums, header actions, titlebar alignment, and mouse hit targets passed |
| Selected title / subtitle / badge contrast | 5.85:1 / 5.13:1 / 4.93:1 |
| Visual review | Light, dark, card, codes, and narrow layouts inspected; four README images and two marketing images refreshed |
| Installed app | /Applications/Luma.app; signature verified, previous build backed up |

The open macOS authentication dialog prevented a final XCUITest run. The installed
app also waits for the user's Keychain authorization while reading the existing
account; the dialog was not automated. Final captures render the isolated app's
own window with fictional data, including its inactive window controls.
Full-screen transitions, a complete VoiceOver audit, and live server writes were
not checked in this polish pass. See ACCESSIBILITY.md for the inherited assessment.

## Follow-up — 2026-11-17

- Use an 8-point outer inset on every edge and an 8-point inner top inset in each
  pane. Header content and native window controls keep their positions.
- Restore the default scene restoration behavior. After reopening and normally
  quitting the isolated preview, two consecutive screenshot journeys passed;
  the prior global-only saved window state had suppressed XCTest launches.
- Add explicit relaunch coverage and capture the collapsed-sidebar layout.

| Check | Result |
|---|---|
| Unit suite with Address Sanitizer | 561 passed on the committed redesign before this spacing follow-up |
| Updated Release build, analyzer, installed signature | Passed |
| Updated UI run | 9 cases passed; Escape-to-Codes, header actions, and list-to-detail failed; interrupted at the user's request |
| Desktop automation | Stopped; no remaining test runners |

The three UI failures remain untriaged; several interactions encountered the
foreground Codex window. Do not treat this interrupted run as a passing suite.
For subsequent small layout changes, use build and focused visual checks instead
of running the complete suite. Existing README images are from the previous pass.

### Sidebar polish — 2026-11-17

- Widen sidebar minimum to 300 points, remove its 320-point cap, and enlarge both divider hit areas.
- Add ⌘B and native sidebar collapse animation, respecting Reduce Motion.
- Align tree chevrons inside section cards and match their secondary color.
- Move native traffic lights to a 20-point left inset; restore native placement outside the vault.

| Focused check | Result |
|---|---|
| Incremental Release build | Passed |
| Hidden AppKit window: traffic-light inset/repeated layout/restoration, divider resizing, minimum widths, collapse/reopen | Passed |
| Offscreen disclosure rendering: alignment and secondary color | Passed |
| Full unit/UI suites | Not rerun, per request; no desktop UI automation |

### Separate Luma storage and signing — 2026-11-17

- Use bundle ID `de.sk2andy.Luma` and dedicated normal/biometric Keychain services.
- Inherit the developer team from ignored LocalConfig instead of the upstream author's team.
- Reset the installed fork's legacy credentials, preferences, HTTP caches and temporary files on request; no server operations.
- Sign the local app with Apple Development and a Personal Team provisioning profile.

| Focused verification | Result |
|---|---|
| Apple-signed Release build | Passed |
| Luma service separation and read/update/delete using production Keychain implementations | Passed with synthetic data |
| Rebuilt binary reads earlier data without authentication UI: legacy and data-protection Keychains | Passed with Apple Development |
| Self-signed experiment | Rejected: CDHash partition changes across builds |
| Full unit/UI suites | Not run, per request |

Personal Team profiles expire after seven days; renew through Xcode automatic signing.

### Divider dragging correction — 2026-11-17

- Lower sidebar/list holding priorities from 750 to 260, below native drag priority 490. Detail remains at 250 so window resizing expands it first.
- Add UI regression coverage that requires both dividers to actually move.

| Focused verification | Result |
|---|---|
| Native hidden-window hit test and queued mouse drag, before fix | Failed: first divider stayed at 300 points |
| Same native drag after fix | Passed: both columns moved from 300 to 350 points |
| Apple-signed Release build | Passed |
| Full UI suite / new XCUITest | Not run, per request |
