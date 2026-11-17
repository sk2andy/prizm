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
