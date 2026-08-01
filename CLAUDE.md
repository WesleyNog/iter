# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`iter` — Flutter app for delivery drivers to log and track routes ("rotas") for Mercado Livre, Amazon and Shopee. Domain, UI copy and comments are in Brazilian Portuguese; keep new user-facing strings in pt-BR. Currency is BRL, addresses are Fortaleza neighborhoods (`lib/Utils/bairros.dart`).

Flutter 3.41.4 / Dart SDK `^3.11.1`.

## Commands

```bash
flutter pub get                       # after any pubspec.yaml change
flutter run                           # run on the attached device/emulator
flutter run -d <device-id>            # flutter devices to list
flutter analyze                       # lint (flutter_lints via analysis_options.yaml)
flutter test                          # all tests
flutter test test/widget_test.dart    # a single file
flutter test --plain-name "<name>"    # a single test by name
```

`test/widget_test.dart` is still the untouched Flutter counter template and fails — it is not a regression you introduced.

## Layout

```
lib/
  main.dart              MaterialApp + AuthGate; only '/addIter' is a named route
  firebase_options.dart  FlutterFire-generated (project iter-mn); Android + iOS only
  screens/               full pages (login, home, addIter, listIter)
  widget/                reusable UI helpers exposed as top-level functions
  services/              Firebase + external API access
  model/                 plain data classes with toMap/fromMap
  Utils/                 pure helpers (note the capital U — imports are 'package:iter/Utils/...')
```

File names are camelCase (`addIter.dart`, `newRouteModal.dart`), not Dart's usual snake_case. Follow the existing convention rather than mixing styles.

Widgets in `lib/widget/` are top-level functions that show something (`showNotification`, `showCupertinoDatePicker`, `showBairrosMultiSelect`), not `StatelessWidget` subclasses. `showBairrosMultiSelect` takes the caller's `setState` so the sheet can refresh the parent screen.

State is plain `setState` in `StatefulWidget`s — there is no state-management package.

## Firebase / auth

`AuthGate` in `main.dart` is the app's `home`: it listens to `authStateChanges()` and swaps between `LoginScreen` and `HomeScreen`, so the session persists across launches. Neither screen navigates after sign-in/sign-out — the gate does it. Keep it that way: it lives on the first route, so anything that removes the first route (`pushNamedAndRemoveUntil('/home', (r) => false)`) would drop the gate and break sign-out. `AddIter` returns with `popUntil((route) => route.isFirst)` for that reason.

`FirestoreService.instance` (`lib/services/firebase.dart`) is the single accessor for Firestore; go through it instead of `FirebaseFirestore.instance`.

`GoogleSignInService` (`lib/services/authService.dart`) is an all-static class using the google_sign_in 7.x flow (`initialize` → `authenticate` → Firebase credential from the idToken). On first sign-in it creates the `user/{uid}` document from the `Users` model. `signInWithGoogle()` returns `null` when the user cancels; anything else throws.

`initialize()` is called with no arguments on purpose: the OAuth client comes from `android/app/google-services.json` (via the `default_web_client_id` string resource the google-services Gradle plugin generates) and from `ios/Runner/GoogleService-Info.plist`. Do not hardcode a `serverClientId` — re-download those files from the Firebase console instead. They only contain an OAuth client once a SHA-1 fingerprint is registered for the Android app.

`firebase_options.dart` only configures Android and iOS — macOS, Windows, Linux and web throw `UnsupportedError`, even though those platform folders exist.

The app id is `com.mna.iter` on every platform. On iOS, `ios/Runner/Info.plist` declares a `CFBundleURLTypes` scheme that must stay identical to `REVERSED_CLIENT_ID` in `GoogleService-Info.plist`; re-registering the iOS app in Firebase changes that value and the plist has to be updated by hand.

## Model serialization

`NewRouteModal` stores its `Company` and `StatusRoute` enums as bare strings (`company.toString().split('.').last`) and rebuilds them by matching `'Company.${map['company']}'`. Renaming an enum value breaks stored documents; change both directions together.

## Weather

`lib/services/openWeather.dart` calls OpenWeather and maps `weather[0].main` onto the `WeatherType` enum, which `lib/Utils/weather.dart` turns into an asset path. Unknown values fall back to `WeatherType.clear`.

Note the current state: the API key is hardcoded in that file and coordinates are hardcoded to Fortaleza in `addIter.dart`. `flutter_dotenv` is a dependency and `.env` (gitignored, holds `OPEN-WEATHER`) is declared as an asset, but `dotenv.load()` is never called — wiring that up is pending work, not a pattern to copy.

## Known incomplete work

Several files are intentionally empty placeholders: `lib/route.dart`, `lib/screens/listIter.dart`, `lib/services/saveIter.dart`.

- `AddIter._saveRoute()` is unreferenced, and its guard is inverted (`if (!validate())` builds the route); the save button only shows a dialog.
- `test/widget_test.dart` pumps `MyApp`, which now needs an initialized Firebase, so it throws before it even reaches its (already wrong) counter assertions.
