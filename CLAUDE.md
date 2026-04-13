# Safety App - Project Guidelines

## Project Overview

Women & Child Safety App with location sharing, SOS alerts, and emergency features.

- **Target**: 100K+ users, India-focused
- **Platforms**: Android & iOS
- **Architecture**: Offline-first with cloud sync

## Tech Stack

### Frontend (Flutter)
- **State Management**: Riverpod
- **Navigation**: go_router
- **Local Storage**: Hive (offline-first)
- **Location**: geolocator, google_maps_flutter

### Backend
- **Auth & Database**: Supabase (PostgreSQL)
- **Custom API**: Elysia + Bun (for SOS, SMS, notifications)
- **Region**: ap-south-1 (Mumbai)

## Code Standards

### Flutter/Dart
- Use `const` constructors where possible
- Always dispose controllers in `dispose()`
- Use Riverpod providers for state, not StatefulWidget state
- Handle errors with try-catch, show user-friendly messages
- Follow null safety strictly

### Naming Conventions
- Files: `snake_case.dart`
- Classes: `PascalCase`
- Variables/functions: `camelCase`
- Constants: `kPascalCase` or `SCREAMING_SNAKE_CASE`

### Project Structure
```
lib/
├── app/           # App config, router, theme
├── core/          # Models, providers, services
├── features/      # Feature modules (auth, sos, contacts)
└── shared/        # Shared widgets, constants, utils
```

## Security Requirements

**CRITICAL - This is a safety app. Security is paramount.**

1. **Never hardcode secrets** - Use `.env` files
2. **Validate all inputs** - Phone numbers, emails, coordinates
3. **Encrypt sensitive data** - Emergency contacts, location history
4. **Secure API calls** - Always HTTPS, validate certificates
5. **Permission checks** - Request only when needed, explain why
6. **No debug logs in production** - Strip sensitive data from logs

## Key Features Priority

1. **SOS Alert** - Must work offline, background, lock screen
2. **Location Sharing** - Battery efficient, accurate
3. **Emergency Contacts** - Encrypted, easily accessible
4. **Fake Call** - Quick access, convincing
5. **Audio/Video Recording** - Discreet, auto-upload when online

## Testing Commands

```bash
cd flutter_app
flutter analyze                    # Static analysis
flutter test                       # Run tests
flutter run -d emulator-5554       # Run on Android emulator
```

## Environment Setup

```bash
# Copy env template
cp flutter_app/.env.example flutter_app/.env

# Add your Supabase credentials to .env
# SUPABASE_URL=https://your-project.supabase.co
# SUPABASE_ANON_KEY=your-anon-key
```

## Deferred / Known TODO

- **Fake Call audio assets** — `lib/core/services/fake_call_service.dart` was originally wired to play `assets/sounds/ringtone.mp3` and `assets/sounds/fake_conversation.mp3` via `audioplayers`. Neither file has ever existed in the repo. As of the flutter-migration branch, the audio code and the `assets/sounds/` pubspec entry were removed pending proper implementation. When revisiting: (1) add real `ringtone.mp3` and `fake_conversation.mp3` under `flutter_app/assets/sounds/`, (2) re-add `- assets/sounds/` under `flutter:` `assets:` in `pubspec.yaml`, (3) restore `audioplayers` import + `_audioPlayer` field + `play/stop/setReleaseMode` calls in `triggerCall`/`answerCall`/`endCall`/`declineCall`/`dispose`. Feature priority #4.

## Agents Available

- `security-reviewer` - Security vulnerability scanning
- `code-reviewer` - Code quality and best practices
- `performance-reviewer` - Battery, memory, network optimization

Run agents after significant code changes.
