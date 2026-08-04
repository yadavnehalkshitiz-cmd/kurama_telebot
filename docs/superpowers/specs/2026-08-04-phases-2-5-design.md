# KuramaBot Phases 2-5 Design

## Goal

Complete the remaining mobile roadmap as one coherent product: local playback, secure private storage, resilient background completion, native notifications, MP3 metadata, and a real account/billing view backed by KuramaBot's API.

## Product boundaries

- Playback and background audio apply only to files the user has downloaded into KuramaBot. The app does not stream protected website sessions or transfer browser cookies.
- Android receives reliable WorkManager-backed completion. iOS receives supported background processing hooks, but the operating system decides when background jobs run.
- Vault files are encrypted at rest. An authenticated session decrypts a file into an app-cache temporary file only for playback; temporary plaintext is removed after use and on startup cleanup.
- Profile identity is installation-scoped and persisted locally. It is not presented as password-based account authentication.
- Payment records remain pending until an administrator approves them. The app never claims that submitting a receipt activates PRO.
- Existing user changes and Phase 1 behavior remain intact.

## Architecture

### Media library and player

`DownloadTask` becomes the single persisted media record. It stores media type, local and vault paths, privacy state, transfer speed, and server metadata. `MediaFileType` classifies audio/video from the declared format and file extension.

`PlayerScreen` selects one of two engines:

- Chewie/video_player for local video, including double-tap seek and vertical volume gestures.
- just_audio with just_audio_background for local audio, lock-screen controls, headset controls, and the Android media notification.

The Downloads screen exposes Play, Share, Move to Vault, and Remove actions only when their preconditions are true.

### Private vault

`VaultCipher` uses chunked AES-256-GCM. Every encrypted chunk has a fresh nonce and authentication tag, avoiding whole-video memory loading. The file format has an explicit magic/version header and rejects truncation or tampering.

`VaultKeyStore` stores the random 256-bit vault key and optional PIN verifier in flutter_secure_storage. The PIN verifier uses Argon2id with a random salt. `VaultAccessService` first offers device authentication through local_auth and supports a six-digit app PIN fallback. Authentication failure never unlocks the vault.

`VaultService` owns encrypt, decrypt-to-cache, restore, delete, and cache cleanup. Moving a file succeeds atomically: the model changes only after encrypted output is complete; plaintext removal happens last. Vault UI lists only private items and relocks on app backgrounding or leaving the tab.

### Background jobs and notifications

The backend already performs media extraction outside the phone process. A yt-dlp progress hook will expose percentage, speed, ETA, filename, and media type.

On task creation the app persists the task and registers a one-off WorkManager job. `BackgroundDownloadRunner` is platform-independent orchestration with injected API, store, notifier, and delay boundaries. It polls the server, persists progress, downloads the completed file atomically, and posts one notification ID per task. Completion notifications carry a JSON payload used to open the local player.

The foreground progress screen continues to poll for immediate UI feedback. File writes use a common destination and temporary suffix so foreground and background attempts cannot expose partial files. AppState reloads background updates when the app resumes.

### MP3 conversion and metadata

Audio selection remains a one-tap format option. The backend's yt-dlp configuration adds FFmpeg metadata and thumbnail embedding after MP3 extraction. Title, uploader/channel, and thumbnail already come from the extractor and become ID3 title, artist, and cover art. If a site supplies no thumbnail, conversion still succeeds without artwork.

### Profile, rewards, and billing

`UserProfile` is a typed API model containing credits, subscription state/expiry, monthly price, daily reward availability, and configured payment methods. AppState owns loading/error/submitting states.

The backend adds an idempotent daily-reward operation worth two credits. Claims are allowed once per rolling 24-hour window and return the authoritative balance and next claim time. Mobile download requests include the installation user ID; non-PRO downloads consume one credit, with a refund if server processing fails.

Payment methods come from server configuration. The app renders a QR for the selected configured value, accepts a transaction reference and optional image/PDF receipt, then submits multipart data to a dedicated endpoint. The server validates size and type, stores receipts under a controlled directory, and records the payment as pending.

## Visual direction

The existing obsidian-and-fox-amber identity stays. The signature element is a narrow amber "media rail" used consistently for active playback, running downloads, and the selected payment method. It encodes state rather than adding decoration. Screens remain quiet around that rail: deep obsidian, warm amber, jade success, compact utility typography, and no continuous glow animations. Reduced-motion settings disable gesture feedback animation.

## Error handling

- Missing/corrupt local files produce actionable recovery states.
- Vault authentication, decryption, and secure-storage errors stay locked and never fall back to success.
- Background network/time-limit failures return a retry result; authorization, invalid payload, and missing tasks fail permanently with a visible notification.
- Payment validation errors preserve entered data and never display success.
- Credit exhaustion returns HTTP 402 and directs the user to Profile.
- File moves, downloads, encryption, and receipt writes use temporary files followed by atomic rename.

## Verification

- Dart unit tests cover media classification, download serialization, job state transitions, PIN verification, and vault encryption/tamper detection.
- Flutter widget tests cover player selection, vault locked/empty states, profile loading/error/reward states, and download actions.
- Python unit tests cover audio postprocessors, daily reward idempotency, credit refund behavior, and receipt validation helpers.
- `flutter test`, `flutter analyze`, Python tests, Python compile checks, and an Android release APK build must pass.
- Android manifest/package metadata and notification/background permissions are inspected from the final APK.
- iOS configuration is generated and statically inspected on Windows; an iOS binary cannot be produced without macOS/Xcode.

## Explicit non-goals

- DRM bypass, authenticated browser-session extraction, and cookie export.
- Streaming YouTube or other website audio directly in the background.
- Automatic payment approval.
- Cloud synchronization of vault encryption keys.
- Claiming guaranteed immediate iOS execution when the OS suspends or terminates the app.
