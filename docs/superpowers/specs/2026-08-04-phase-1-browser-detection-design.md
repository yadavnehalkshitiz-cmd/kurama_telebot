# KuramaBot Phase 1: Server-Assisted Browser Detection

Date: 2026-08-04
Status: Approved by delegated product direction

## Goal

Deliver an Android-first in-app browser that lets users browse any HTTP(S) website and offers a download action only after KuramaBot's backend confirms that the current public page contains supported downloadable media.

Phase 1 must turn the existing browser prototype into a predictable, testable flow without attempting private-session extraction, raw stream interception, DRM bypass, background execution, or iOS release work.

## Product Decisions

- Android is the first release target. The architecture must avoid Android-specific state in Dart so iOS can follow.
- Browsing is unrestricted to valid HTTP(S) pages; extraction support is determined by the backend.
- Detection is server-assisted through the existing `POST /api/fetch-info` endpoint and `ApiClient.fetchInfo`.
- Browser cookies, login tokens, WebView request headers, and page HTML are never sent to the backend.
- Only the canonical top-level page URL is submitted for detection.
- Private/login-only posts and DRM-protected streams are out of scope.
- A confirmed `VideoInfo` object is passed to the existing format-selection screen; metadata is not fetched twice.

## Architecture

### Browser state

Introduce a small controller/model independent of Flutter widgets:

- `idle`: no eligible page has completed loading.
- `checking`: the backend is resolving the current page URL.
- `detected`: the backend returned valid `VideoInfo` for the same current URL.
- `unsupported`: the backend rejected the page as unsupported or found no media.
- `error`: a timeout, connection, authentication, or server error prevented detection.

Each navigation increments a request generation. Late responses from older URLs are discarded. Duplicate checks for the same normalized URL are suppressed. Detection begins after a successful top-level `onLoadStop`, not from intercepted subresource requests.

### Components

1. `BrowserDetectionController`
   - Owns detection state and the current normalized URL.
   - Depends on a narrow media-probe function rather than `BuildContext`.
   - Debounces rapid navigation and rejects stale responses.
   - Exposes immutable state for widget rendering and unit tests.

2. `BrowserScreen`
   - Owns WebView navigation controls and presentation only.
   - Validates address-bar input and converts non-URL text into a search query.
   - Starts detection after page load completes.
   - Renders progress, supported/unsupported feedback, and the detected-media action.
   - Passes the already-resolved `VideoInfo` to `VideoInfoScreen`.

3. `ApiClient`
   - Reuses `fetchInfo` as the authoritative media probe.
   - Preserves typed timeout and backend error messages.
   - Does not receive cookies or WebView headers.

4. Existing download flow
   - `VideoInfoScreen` remains responsible for format and quality selection.
   - `POST /api/download` remains responsible for creating the server task.
   - Phase 1 does not change background transfer behavior.

## Data Flow

1. User enters an address, search phrase, or taps a platform shortcut.
2. The app resolves it to an HTTP(S) URL and loads it in the WebView.
3. When the top-level page finishes, the controller enters `checking` and calls `fetchInfo(pageUrl)`.
4. If metadata returns for the current generation, state becomes `detected`.
5. The animated action appears with the media title and an explicit `Download` label.
6. Tapping it opens `VideoInfoScreen` with the cached metadata.
7. Unsupported pages keep browsing available and show quiet, non-blocking feedback.

## Navigation and Security Rules

- Accept only `http` and `https` page URLs.
- Search non-URL input through an encoded HTTPS search URL.
- Reject `file:`, `javascript:`, `data:`, `content:`, and custom schemes inside the WebView.
- Never evaluate arbitrary page JavaScript for extraction.
- Never send cookies, authorization headers, form data, or page HTML to KuramaBot.
- Do not label a page downloadable until the backend confirms it.
- Error messages must distinguish unsupported media from server connectivity problems.

## Visual Direction

Preserve KuramaBot's dark fox identity while reducing the prototype's generic glowing-button treatment.

- `Ink Black` `#0D0D12`: primary canvas.
- `Den Surface` `#171720`: controls and browser chrome.
- `Fox Ember` `#FF5722`: primary action.
- `Amber Signal` `#FFB02E`: detection/checking indicator.
- `Mint Confirm` `#3DDC97`: confirmed media state.
- `Ash Text` `#B9B8C3`: supporting copy.

The signature interaction is a single restrained ember pulse when detection changes from `checking` to `detected`. It runs once, respects reduced-motion settings, and does not animate continuously. The download action contains useful content—media availability and title—rather than claiming an unverified quality such as “HD.”

## Error Handling

- Invalid input: keep the current page and show an address-bar validation message.
- Unsupported page: show a compact “No supported media found” status; do not use an error snackbar.
- Offline/backend unavailable: show a retry action while leaving the webpage usable.
- Authentication failure: direct the user to server configuration.
- Navigation during detection: cancel logically by generation and ignore stale completion.
- Widget disposal: controller completion must not update disposed UI.

## Testing Strategy

### Unit tests

- URL normalization accepts HTTP(S), upgrades hostname-like input to HTTPS, and searches plain text.
- Unsafe schemes are rejected.
- State transitions cover success, unsupported media, timeout/error, duplicate URL suppression, and stale-response rejection.
- A detected result retains the exact `VideoInfo` returned by the probe.

### Widget tests

- The download action is hidden in `idle`, `checking`, `unsupported`, and `error` states.
- Checking and error feedback render without blocking browser controls.
- A detected result displays one enabled download action.
- Tapping the action opens the metadata/quality screen without another probe.

### Integration verification

- Run `flutter pub get`, `flutter test`, and `flutter analyze` with no errors.
- Build an Android release APK in CI.
- Manually verify public URLs from YouTube, Instagram, TikTok, Pinterest, Vimeo, and one unsupported site.
- Confirm that navigation during a slow probe never shows media from the prior page.

## Delivery Scope

Phase 1 includes the controller, browser UI refactor, focused tests, required Android WebView/network configuration, and CI verification.

Phase 1 excludes raw network sniffing, authenticated/private content, cookie transfer, DRM content, background downloads, notifications, player changes, vault changes, conversion/tagging changes, billing changes, and iOS release validation.

## Acceptance Criteria

- Users can browse arbitrary valid HTTP(S) pages and use search input.
- Backend detection begins automatically after a top-level page finishes loading.
- Download UI appears only for backend-confirmed media and uses the returned metadata.
- Stale or duplicate requests cannot show the wrong media.
- Browser failures do not prevent continued browsing.
- No WebView session data is transferred to the backend.
- Automated tests cover the detection state machine and URL handling.
- Android CI produces a release APK from the committed source.
