# Kurama Product Separation and App Roadmap Design

**Date:** 2026-08-12  
**Status:** Approved design, awaiting implementation-plan review  
**Products:** Kurama App and Kurama Telegram Bot

## 1. Objective

Separate the current mixed repository into two independently owned products without interrupting the live Telegram bot or losing the working mobile application:

1. Keep the existing `kurama_telebot` GitHub repository and reduce it to the Telegram product.
2. Create a new `kurama_app` GitHub repository containing the Flutter client, its FastAPI backend, Supabase definitions, app-specific tests, deployment files and release automation.

After migration, neither repository imports code, reads runtime files or depends on build artifacts from the other. Similar downloader logic may initially be copied into both products so each can evolve and deploy independently.

## 2. Repository boundaries

### Existing `kurama_telebot`

```text
kurama_telebot/
├── bot/                 Telegram handlers, keyboards and sending logic
├── downloader/          Bot-owned extraction and media-processing code
├── tests/               Telegram and bot-downloader tests
├── deployment/          Bot container and hosting configuration
├── scripts/             Local bot setup and maintenance tools
├── requirements.txt
└── README.md
```

This repository owns Telegram commands, Telegram delivery, bot-specific cookies, bot configuration and its own downloader implementation. It does not own Flutter, mobile accounts, the app backend, app billing or app release workflows.

### New `kurama_app`

```text
kurama_app/
├── mobile/              Flutter Android and Windows client
├── backend/             FastAPI download and account-facing service
├── supabase/            Versioned schema, migrations, policies and seed data
├── tests/               Backend, contract and end-to-end tests
├── deployment/          Backend container and environment templates
├── docs/                Architecture, operations and product documentation
├── scripts/             Repeatable local-development and release helpers
└── .github/workflows/   App/backend validation and signed releases
```

The new repository owns every feature used by app users, including authentication, profiles, credits, subscriptions, payments, downloads, browser functionality, vault behavior, Android/Windows builds and app-backend deployment.

## 3. Migration strategy

Use a clean snapshot split rather than filtered Git history. Existing Telegram history remains intact. The app repository begins with an explicit migration commit that records the source repository and source commit.

Migration order:

1. Record a complete inventory and source commit.
2. Create the private `kurama_app` repository initially.
3. Copy only app-owned files into a clean local repository.
4. Reorganize the copied files under `mobile/`, `backend/`, `supabase/`, `deployment/` and `tests/`.
5. Make the new repository build and test independently.
6. Deploy the new backend alongside the current service and run smoke tests.
7. Release an app build pointing to the new backend.
8. Confirm production behavior and rollback readiness.
9. Only then remove app-owned files from `kurama_telebot` and simplify its deployment.

At every migration checkpoint, the currently published bot and app remain usable. No cleanup of the original repository occurs until the replacement app pipeline is green.

## 4. App architecture

### Mobile client

Flutter remains the cross-platform client for Android and Windows. It is divided by feature rather than by screen type alone:

```text
mobile/lib/
├── app/                 Startup, routing, theme and environment
├── core/                Networking, errors, storage and reusable UI
└── features/
    ├── auth/
    ├── browser/
    ├── downloads/
    ├── home/
    ├── profile/
    ├── subscriptions/
    └── vault/
```

Each feature owns its models, services, state and presentation. Cross-feature access occurs through small public interfaces. Secrets are never compiled into the APK; only public configuration such as the backend URL and Supabase publishable key may be present.

### Backend

FastAPI owns privileged operations:

- Validate Supabase access tokens.
- Authorize every user-owned resource.
- Apply rate limits, quotas and credit rules.
- Fetch media metadata and execute download jobs.
- Stream completed files with ownership checks.
- Process payment/admin operations through privileged endpoints.
- Produce structured logs, health signals and auditable errors.

The backend uses server-only credentials. The Supabase service-role key and other privileged secrets are stored only in the deployment environment.

### Authentication and database

Supabase provides email/password authentication, verified email flows, password reset, Google sign-in and PostgreSQL. Flutter uses the Supabase publishable key and maintains the user's session in secure device storage. Requests to FastAPI carry the user's short-lived bearer token.

All exposed user tables use row-level security. Policies combine the authenticated role with ownership checks such as `auth.uid() = user_id`; authentication alone never grants access to every row. Authorization roles are stored in protected app metadata or server-controlled tables, not user-editable metadata.

Initial data domains:

- Profiles
- User roles and account state
- Credit ledger rather than an untraceable mutable balance
- Subscription and payment records
- Download jobs and user-visible history
- Devices/sessions where supported
- Administrative audit events

Database changes are versioned, reviewable migrations. Production is never changed manually without recording the change in the repository.

## 5. Browser product scope

The embedded browser becomes a privacy-focused downloader browser, not a promise of complete Brave or Chrome compatibility.

### Initial advanced browser release

- Multiple tabs with persistent titles, URLs and active-tab state
- Tab overview, create, switch, duplicate and close
- Back, forward, reload, stop and home controls
- Address/search input with safe URL handling
- Bookmarks, browsing history and recently closed tabs
- Incognito tabs that do not persist local history or cookies after closure where the WebView permits
- Per-site permission decisions for camera, microphone, location and notifications
- Popup, redirect and unsafe-scheme controls
- Media detection connected to the downloader flow
- Download queue integration rather than uncontrolled WebView file downloads
- Privacy dashboard showing blocked requests and current protections

### Built-in addons

“Addons” initially means curated modules controlled by the app: ad/tracker blocking, cookie controls, JavaScript toggle, user-agent selection, reader-oriented cleanup where feasible and per-site exceptions. Arbitrary Chrome/Firefox extensions are outside scope because Flutter WebView is not a compatible extension runtime.

Blocking rules must be updateable as signed/versioned data without shipping privileged application secrets. Failures in a privacy module must degrade safely and must not silently bypass authentication or file-safety checks.

## 6. Core app capabilities

The product roadmap is organized as dependent milestones:

### Phase 0 — Separation and reproducible foundation

- Create the new repository and independent developer setup.
- Move app-owned code and copy the required downloader code.
- Correct launcher/adaptive icons and consistent branding.
- Establish development, staging and production configuration.
- Create independent backend and mobile CI.
- Preserve signed Android release continuity with the existing permanent key.

### Phase 1 — Accounts and secure API

- Email/password sign-up and sign-in.
- Email verification, password reset and logout.
- Google sign-in with approved redirect/deep-link configuration.
- Supabase token validation in FastAPI.
- User-owned profiles and authorization policies.
- Rate limits, abuse controls and clear offline/authentication states.
- Remove shared master-key entry from the public app experience.

### Phase 2 — Reliable downloader

- URL recognition and metadata preview.
- Video/audio format and quality selection.
- Background job lifecycle: queued, running, paused where supported, retrying, failed, completed and cancelled.
- Notifications, progress, file integrity checks, share/open/export behavior and cleanup.
- Platform-specific error explanations without exposing server internals.

### Phase 3 — Advanced browser

- Multi-tab browser foundation.
- History, bookmarks, recently closed and incognito behavior.
- Privacy shields and built-in addons.
- Per-site controls and media detection.

### Phase 4 — User value and monetization

- Profile and security settings.
- Device/session management.
- Vault with PIN/biometric protection and recovery rules.
- Credit ledger, subscription state and payment history.
- Server-driven feature/plan entitlements.

### Phase 5 — Administration and public launch

- Admin user, subscription, payment and job controls.
- Account suspension, abuse handling and audit trail.
- Analytics, crash reporting and operational dashboards with privacy limits.
- Accessibility, localization, privacy policy, terms and account deletion.
- Staged internal, closed beta, open beta and production rollout.

## 7. API and data flow

1. The user authenticates through Supabase in Flutter.
2. Flutter receives a short-lived session token and stores the session securely.
3. Flutter calls FastAPI with that token.
4. FastAPI verifies token issuer, signature, audience and expiry, then derives the user identity from verified claims.
5. FastAPI validates request ownership, entitlement, rate limit and credits.
6. FastAPI creates and processes a download job.
7. Flutter polls or subscribes to job progress through a user-authorized channel.
8. File download endpoints re-check ownership before streaming.
9. Ledger and audit records are committed atomically with credit-changing operations.

No request trusts a user ID sent by the client when identity can be derived from the verified token.

## 8. Error handling and resilience

The client distinguishes:

- Device offline
- Backend sleeping/waking
- Backend unavailable
- Session expired
- Account unverified, suspended or unauthorized
- Unsupported media
- Platform extractor failure
- Rate or credit limit
- Download interrupted or storage unavailable

Authentication failures trigger a controlled session refresh or sign-in screen, never an “Invalid API key” message. Retry behavior is bounded and idempotent. Backend errors use stable codes plus safe user messages; detailed traces remain server-side. Download jobs include cleanup and recovery behavior for process restarts.

## 9. Testing and quality gates

### Per change

- Formatting and static analysis
- Unit tests for domain behavior
- Backend API and authorization tests
- Flutter widget/state tests
- Migration and RLS tests
- Secret-scanning and dependency checks

### Release gates

- Android signed release build and signature verification
- Windows release build and archive inspection
- Staging backend smoke tests
- Real-device authentication and download test
- Upgrade test from the previous signed Android version
- No production release if account isolation or RLS tests fail

Contracts between Flutter and FastAPI are versioned and tested on both sides. CI for one repository never depends on checking out the other repository.

## 10. Deployment and environments

The app backend and Telegram bot deploy separately with separate secrets, logs, storage and rollback controls. The app uses three environments:

- Development: local services and test data
- Staging: production-like authentication and backend for automated/manual verification
- Production: public users and signed releases

Environment-specific values are injected through build/deployment configuration. Production database migrations run before traffic is switched to code requiring them. Releases use immutable tags and retain the previous deployable version for rollback.

## 11. Repository cleanup rules

Existing uncommitted and staged user files are preserved. Migration commits include only explicitly inventoried product files. Runtime data, `.env`, cookies, IDE metadata, logs, downloads, keystores and local databases are not copied or committed.

The Telegram cleanup must prove:

- Bot tests pass independently.
- Bot starts without app/API modules.
- Its deployment contains only Telegram dependencies.
- No mobile secrets or release workflows remain.

The app migration must prove:

- Flutter tests and analysis pass from `mobile/`.
- Backend tests pass from `backend/`.
- Local setup starts without files from the Telegram repository.
- Android and Windows artifacts build in the new CI.
- Staging authentication and a complete download flow pass.

## 12. Success criteria

Separation is complete when:

1. `kurama_app` builds, tests, deploys and releases independently.
2. `kurama_telebot` runs and deploys independently.
3. Neither repository imports, mounts or checks out the other.
4. The public APK contains no shared privileged API key.
5. Users authenticate with verified email/password or Google.
6. Existing signed Android users can upgrade to the new release.
7. The launcher icon and in-app branding use the approved Kurama artwork.
8. The old mixed deployment can be rolled back during migration and retired only after production verification.

## 13. Explicit non-goals for the first implementation cycle

- Full Chrome/Brave extension compatibility
- Synchronizing Telegram users with app accounts
- Sharing a live downloader package between repositories
- Rewriting the Flutter application from scratch
- Moving production traffic before independent staging verification

