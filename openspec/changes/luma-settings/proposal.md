# Luma settings

Provide persistent appearance, vault locking, unlock, and sync controls in the macOS Settings window.
Keep the existing biometric implementation and crypto primitives. Retain original Prizm attribution
when publishing the fork README and support button.

- Lock after app-local inactivity (minutes/hours), at a daily local time, or on selected Mac events.
- PIN unlock retains its configuration but requires a master-password unlock after app restart.
- Manual and interval synchronization run only while unlocked and outside an open editor.
- System, Light, and Dark appearance apply to all app windows.
- No full UI suite or real-vault test data; use focused unit tests and an incremental signed build.
