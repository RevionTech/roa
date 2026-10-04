# Changelog

## 0.3.1 — 2026-10-05

- Process ON/OFF requests and display service confirmations through filesystem
  events, retaining periodic safety checks and fallback polling.
- Show immediate pending feedback without claiming an unconfirmed power change.

## 0.3.0 — 2026-10-04

- Add timed sessions with presets and custom minute/hour entry, enforced by the
  service, with a menu bar countdown.
- Require explicit ON after a Mac restart; preserve unexpired sessions across
  service restarts within the same boot.
- Add optional charging-only sessions and optional start at login, both disabled
  initially; preserve the login preference during updates.
- Add live status/diagnostics and a privacy-conscious copy action.
- Add opt-in macOS and Telegram notifications for important events, with bot
  credentials in Keychain and no notification network dependency for power control.

## 0.2.3

- Remove local build paths from executable debug symbols before signing.

## 0.2.2

- Show one power action based on the current request and safety stop.
- Display an explicit checkbox for automatic update checks in both states.

## 0.2.1

- Clarify the menu bar tooltip for clicking and opening options.

## 0.2.0

- Native menu controls, command-line client and guarded power service.
- Signed, notarized universal PKG installation and Sparkle updates.
- Signed latest-only update feed and optional automatic update checks.
- Coordinated app/CLI/service replacement with OFF confirmation and recovery.
- Company namespace `net.reviontech.roa` and Revion Tech branding.
