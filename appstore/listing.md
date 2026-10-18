# Contraction Traction: App Store listing

Copy for App Store Connect, version 1.0. Each field's text is the content of
its code block. Character counts were measured on that text (Unicode
characters, including spaces and newlines).

| Field | Limit | Count |
|---|---|---|
| Name | 30 | 20 |
| Subtitle | 30 | 27 |
| Promotional text | 170 | 162 |
| Description | 4000 | 2204 |
| Keywords | 100 | 97 |
| Review notes | 4000 | 1865 |
| TestFlight: What to Test | 4000 | 938 |
| TestFlight: Beta App Description | 4000 | 645 |

## Name

```text
Contraction Traction
```

On the Home Screen the app shows as "Contractions" (`CFBundleDisplayName`).

## Subtitle

```text
Simple, private labor timer
```

## Promotional text

```text
Time contractions with one big button, log the ones you missed from memory, and merge your partner's log. Free, no account, no ads. Your data stays on your phone.
```

## Description

```text
Contraction Traction is a simple contraction timer for iPhone. It's free, needs no account, and keeps everything on your phone.

TIME CONTRACTIONS
Tap the big Start button when a contraction begins and tap again when it ends. Each one shows how long it lasted and how far apart it was from the one before. You also get last-hour averages and a timeline of the last two hours. Between contractions, the button shows the time since the last one started.

LOG THE ONES YOU MISSED
If you missed a few or wrote them down on paper, "Log past" adds them from memory in a few taps: when the last one started, about how long it lasted, how many there were, and about how far apart. Entries from memory are marked approximate (~), so you can always tell timed entries from estimates. Tap any entry to fix its time, length, or note.

SHARE WITH YOUR PARTNER
Share your log as plain text in Messages, or send it as a file with AirDrop. On the other phone, paste the text into Import or open the file. You review everything before it's added:
- New contractions are listed, and you can uncheck any of them.
- Contractions already in your list are skipped, so duplicates are removed.
- When the same contraction was timed on both phones a little differently, you choose to keep yours or use theirs.
Nothing in your list is deleted, and Undo puts it back the way it was.

LOCK SCREEN AND DYNAMIC ISLAND
A Live Activity shows the running timer on the Lock Screen and in the Dynamic Island. It has a Start/Stop button, so you can time a contraction without unlocking your phone.

5-1-1 NOTE
The app can show a short note when your recorded contractions have been about 5 minutes apart and lasted about a minute for about an hour. You can switch it to 4-1-1 or 3-1-1, or turn it off. The note only describes the times you recorded. Your provider's instructions come first.

PRIVATE BY DESIGN
Free, with no account, no ads, and no tracking. The app has no servers and makes no network connections. Your data stays on your phone unless you choose to share it.

IMPORTANT
Contraction Traction is a timing tool, not medical advice. Follow your provider's instructions. In an emergency, call 911 or your local emergency number.
```

## Keywords

```text
labor,labour,timer,pregnancy,birth,baby,doula,midwife,511,5-1-1,partner,tracker,log,maternity,due
```

None of these words appear in the name ("Contraction", "Traction"). No word
is repeated, and there are no spaces after the commas.

## URLs

| Field | Value |
|---|---|
| Support URL | `TBD: GitHub Pages support page` (likely `https://jkjackson2000.github.io/contraction-traction/`, served from `docs/index.html`) |
| Privacy Policy URL | `TBD: GitHub Pages privacy page` (likely `https://jkjackson2000.github.io/contraction-traction/privacy.html`, served from `docs/privacy.html`) |
| Marketing URL | Optional. Leave blank. |

Turn on GitHub Pages and confirm both pages load before you submit. App
Review opens the privacy URL.

## Category and pricing

- Primary category: Health & Fitness
- Secondary category: none
- Price: Free (no in-app purchases)
- Copyright: 2026 Jared Jackson

## Age rating questionnaire

Answer **None** or **No** to every content question:

| Question | Answer |
|---|---|
| Cartoon or fantasy violence | None |
| Realistic violence | None |
| Prolonged graphic or sadistic realistic violence | None |
| Profanity or crude humor | None |
| Mature or suggestive themes | None |
| Horror or fear themes | None |
| Sexual content or nudity | None |
| Graphic sexual content and nudity | None |
| Alcohol, tobacco, or drug use or references | None |
| Simulated gambling | None |
| Gambling (real money) | No |
| Contests | No |
| Unrestricted web access | No |
| User-generated content | No. Shared logs go between the user's own devices through the system share sheet; the app has no feed or public sharing. |
| Messaging or chat | No |
| Advertising | No |
| Parental controls | No |
| Age assurance | No |
| **Medical or treatment information** | **None** (see the note below) |
| **Health or wellness topics** | **Yes** (see the note below) |

The two health-related questions:

- **Medical or treatment information.** Answer None. The app records times
  and computes averages. It gives no diagnosis, treatment, or instructions.
  The 5-1-1 note only describes the recorded pattern and says to follow your
  provider's instructions. If App Review disagrees, the conservative answer is
  "Infrequent", which raises the rating.
- **Health or wellness topics.** Answer Yes, because the app is about labor
  and pregnancy.

Expected result: the lowest age rating (4+). Check the rating App Store
Connect computes before you submit.

## App Privacy

- Data collection: **Data Not Collected**. The app has no network code,
  analytics, or third-party SDKs.
- Tracking: **No**.
- This matches `App/Resources/PrivacyInfo.xcprivacy`: `NSPrivacyTracking` is
  false, no data types are collected, and the only required-reason API is
  UserDefaults with reason `CA92.1`.

## Review notes (App Review Information → Notes)

Sign-in required: **No**. Leave the demo account blank.

```text
No account or sign-in. The app makes no network connections and has no servers, analytics, ads, or in-app purchases. All data stays on the device.

FIRST LAUNCH
One disclaimer screen ("Timing tool, not medical advice..."). Tap Got it.

TIMER
Tap the large Start button to begin a contraction and tap again to stop it. "Log past" adds contractions from memory.

TESTING IMPORT (one device is enough)
1. Tap Start, wait a few seconds, and tap Stop. Repeat once or twice.
2. Tap the Share icon (top right), then "Share as text...", then Copy.
3. Tap the Import icon (tray with arrow, top right), tap Paste, then Continue.
4. Review shows the entries as "already in your list". Edit a time in the text box before you tap Continue (or paste the sample below) to see new entries and ones to resolve. Tap Import, then Undo in the toast if you like.

Sample text to paste into Import:
2026-10-18 2:10:03 PM · 58s
2026-10-18 2:15:40 PM · ~1m 05s · back pain
2026-10-18 2:20:12 PM · 1m 02s

With two devices: on the first, tap Share, then "AirDrop file...", and send it to the second. On the second, open the file with "Contractions" to go straight to Review.

LIVE ACTIVITY
Tap Start in the app, then lock the device. The Lock Screen shows the running timer with a Stop button. Tap Stop to end the contraction without opening the app, then tap Start for the next one. On devices with the Dynamic Island, touch and hold the island to see the same controls. The activity ends after 2 hours without a contraction, or when you tap "End session" in the app. You can turn it off in the app's Settings.

HEALTH
The app is a timing tool and makes no medical claims. The disclaimer ("Timing tool, not medical advice. Follow your provider's instructions. In an emergency, call 911 or your local emergency number.") appears on first launch, in Settings > About, and in the description.
```

## TestFlight: What to Test

```text
Thanks for testing! Please try these:

1. Sharing between two phones. On phone A, time or log a few contractions, then tap Share. Try both "Share as text..." (Messages) and "AirDrop file...". On phone B, paste the text with Import > Paste, or open the AirDropped file with Contractions. Check the Review screen: new entries, ones already in your list, and ones to resolve (Keep mine / Use theirs). Import, then try Undo.
2. Lock Screen and Dynamic Island. Tap Start, lock the phone, and use the Stop and Start buttons on the Lock Screen. On a phone with the Dynamic Island, touch and hold the island and use the button there. Then open the app and check the list matches.
3. Log past. Add one contraction, then a run (for example, 4 about every 5 minutes, the last one 10 minutes ago). Check the times, the ~ marks, and the timeline.

Please report anything confusing, slow, or wrong, especially wrong times or duplicates after an import.
```

## TestFlight: Beta App Description

```text
Contraction Traction is a free, private contraction timer for iPhone. One big button times each contraction and shows how long it lasted and how far apart they are. "Log past" adds the ones you missed from memory. Partners can share their logs as plain text or by AirDrop and merge them, with duplicates removed and conflicts reviewed. A Live Activity puts the timer and a Start/Stop button on the Lock Screen and in the Dynamic Island. There is no account, no ads, and no tracking, and your data stays on your phone. Timing tool, not medical advice. Follow your provider's instructions. In an emergency, call 911 or your local emergency number.
```
