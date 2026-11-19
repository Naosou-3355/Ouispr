# Ouispr Pro: purchase, hub and trial

- **ID:** `pro.subscription`
- **Tier:** Pro
- **Targets:** OuisprApp + OuisprCore
- **Screens:** `app.pro.hub`, `app.paywall`, `app.pro.trial-announcement` — see [screens.md](screens.md)

## Sub-features

- `pro.hub`: Ouispr Pro hub: the four Pro features with their state and settings.
- `pro.paywall`: Three plans to buy Pro.
- `pro.restore`: Restore purchases.
- `pro.trial`: A 14-day trial announced at the end of onboarding.
- `pro.trial-end`: End-of-trial paywall.
- `pro.demo`: « Voir la démonstration » on each Pro feature's page.

## How to get to it (user POV)

1. Ouispr → Réglages → Ouispr Pro (once Pro is on sale).
2. Choose a plan; or start the trial offered at the end of onboarding.

## Driving it with axe + Argent

```bash
.claude/skills/verify-ouispr-ios/scripts/launch.sh --skip-onboarding
.claude/skills/verify-ouispr-ios/scripts/drive.sh set-default ouispr.debugProEntitlementForced -bool YES
.claude/skills/verify-ouispr-ios/scripts/drive.sh tab Réglages
.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-label "Ouispr Pro, Pro actif"
.claude/skills/verify-ouispr-ios/scripts/evidence.sh pro-hub
.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-id xmark
```

Trial states can be forced from Réglages → Developer → « Reverse trial (#593) » (Debug builds).

## Gotchas

- **Prices need simslim's `store` category.** On the slimmed device `launch.sh` creates, `loadProducts` fails with « Impossible de communiquer avec une application d'aide » (StoreKit's daemon is disabled) and the paywall's buy button stays at « … ». `simslim on <udid> --keep com.apple.remindd --except store` (reboots the device, keeps the install) brings the prices back: on 2026-10-22 an iPhone 17 / iOS 26.5 device showed Yearly $39.99 and Lifetime $79.99 (US storefront). That proves the paywall renders its plans, not that App Store Connect serves the real prices to a French account: that stays a device check.
- **Not driven in the simulator:** a purchase or a restore.
- **Trial states (#593):** the end-of-onboarding announcement raises itself (`proTrial action=announcementShown details=kind=newUser`). Réglages → Developer → « Reverse trial (#593) » drives the rest: « Move to the last 2 days » (Home card, Settings badge and the keyboard panel's « Pro · 2 days left » pill), « End the trial now » (end-of-trial paywall, recap then offers), « Forget the trial » + « Forget What's new » then relaunch (What's new, then `kind=existingUser`).
- **An ineligible device cannot be simulated.** `SmartModeAvailability.deviceIsCapable` reads Apple Intelligence availability, which a simulator takes from the host Mac: a device created as `iPad-Pro--11-inch-` (A12X, `iPad8,1`) still reports capable and shows every promotion. The ineligible branch is covered by `ProTrialTests.testAnIneligibleDeviceNeverStartsATrialAndIsNeverPromotedTo` and the `deviceCanRunSmartModes: false` cases of `OnboardingStepTests` and `WhatsNewTests`; the device check stays on the iPad.
- **Reinstall over an ended trial (#837):** the Keychain record survives `xcrun simctl uninstall`, the App Group does not. Seed with « End the trial now », uninstall, reinstall, `set-default ouispr.onboardingStep -string completion`, tap `onboarding.primary`: the **ordinary** paywall opens, no « essai terminé », no recap. Log: `proTrial action=restoredEndedBeforeInstall` at launch, then `endOfTrialPaywallShown details=framing=standard`. Closing it (cross or « Continuer gratuitement ») shows the monthly offer once, as the end-of-trial paywall does; the same ordinary paywall opened from Réglages or Home never does. An install that lived through its trial still logs `framing=trialEnded`.
- Do not set `ouispr.proActive`: `SubscriptionManager` resets it at launch.
- **The four paywall entry points (#279)** show together only for a non-subscriber with no running trial: « End the trial now », then « Continuer gratuitement ». Home Pro card, Home locked « Historique » hint, Réglages → Ouispr Pro, and the keyboard panel's « Ouispr Pro » pill (☰ held, left of the gear). The pill opens `ouispr://open?source=keyboard&intent=pro`: the log shows `<KBD> … openOuisprApp details=intent=pro` then `<APP> … keyboardProIntent`. Captures of all four in FR, EN and iPad: `docs/agents/screens/279/`.
- **English device:** `drive.sh full-access` and `select-keyboard` look for French system labels. On `--lang en` they are « Allow Full Access », « Allow » / « Don’t Allow », « Next keyboard » and « Ouispr, Multiple languages ».
- **iPad (`iPad-Pro--11-inch-`):** Ouispr runs in a 375×667 iPhone compatibility window, and `axe describe-ui` reports frames in that window, so `axe tap --label` lands in the wrong place: scale by 1194/667 and centre horizontally. In Safari the Ouispr bar sits under the system shortcut bar, about 66 pt below `inputView`'s top, so `kbd` offsets miss it. The pill opens Ouispr as a window over Safari, and Safari's keyboard covers the paywall's plans until Ouispr is brought forward.
