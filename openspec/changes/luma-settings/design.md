# Design

`AppPreferences` holds non-secret UserDefaults values shared by Settings and the root lifecycle.
`VaultAutomation` evaluates supplied dates; the root owns app-local event monitoring and a one-second
check. Native AppKit input monitoring is needed because SwiftUI has no app-wide idle-input API.
Existing sleep, screen-lock and screensaver notifications now respect individual preferences.

All refresh entry points use the existing sync use case. Locking hides the vault immediately, cancels
and waits for active authentication/sync work, then clears keys and cached vault data. Stale flow results
must not reopen the vault. Sync errors remain visible without replacing a successful sync timestamp.

PIN uses existing PBKDF2-SHA256 (600,000 iterations), HKDF and authenticated EncString encryption.
Only the PIN-derived key, encrypted under the vault key, persists in Luma's Keychain service.
The inverse wrapper exists only in memory after password unlock. Five failures discard that wrapper.
See SECURITY.md for the threat model. No new crypto dependency or account migration is introduced.

Defaults retain prior behavior: system appearance, lock on all three Mac events, idle/daily locks
and periodic synchronization disabled until selected. PIN setup is opt-in.

System appearance is observed on NSApplication, independently of per-window overrides. Scenes and
native split-view hosts receive the resolved color scheme explicitly so Light → System updates
SwiftUI content as well as the window chrome.
