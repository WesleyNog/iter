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
  controller/            per-collection Firestore read/write (UserController)
  model/                 plain data classes with toMap/fromMap
  Utils/                 pure helpers (note the capital U — imports are 'package:iter/Utils/...')
```

File names are camelCase (`addIter.dart`, `newRouteModal.dart`), not Dart's usual snake_case. Follow the existing convention rather than mixing styles.

Widgets in `lib/widget/` are top-level functions that show something (`showNotification`, `showCupertinoDatePicker`, `showBairrosMultiSelect`), not `StatelessWidget` subclasses. `showBairrosMultiSelect` takes the caller's `setState` so the sheet can refresh the parent screen.

State is plain `setState` in `StatefulWidget`s — there is no state-management package.

## Firebase / auth

`AuthGate` in `main.dart` is the app's `home`: it listens to `authStateChanges()` and swaps between `LoginScreen` and `HomeScreen`, so the session persists across launches. Neither screen navigates after sign-in/sign-out — the gate does it. Keep it that way: it lives on the first route, so anything that removes the first route (`pushNamedAndRemoveUntil('/home', (r) => false)`) would drop the gate and break sign-out. `AddIter` returns with `popUntil((route) => route.isFirst)` for that reason.

The gate passes its `User` to `HomeScreen` as a required constructor argument, so that screen can never be built without one. Read profile fields from `widget.user` there instead of reaching for `FirebaseAuth.instance.currentUser`.

Auth data (`displayName`, `email`, `photoURL`) comes from that `User`; everything else about the profile (`nickName`, `cpf`, `birthDate`) lives in Firestore and is read through `UserController.watch(uid)`, which yields `null` while the document does not exist. Build such streams once in `initState`/a field initializer — creating one inside `build` resubscribes on every rebuild. There is no state-management package: screens consume the stream with `StreamBuilder` and fall back to the auth data while it loads.

`FirestoreService.instance` (`lib/services/firebase.dart`) is the single accessor for Firestore; go through it instead of `FirebaseFirestore.instance`.

`GoogleSignInService` (`lib/services/authService.dart`) is an all-static class using the google_sign_in 7.x flow (`initialize` → `authenticate` → Firebase credential from the idToken). On first sign-in it creates the `user/{uid}` document from the `Users` model. `signInWithGoogle()` returns `null` when the user cancels; anything else throws.

`initialize()` is called with no arguments on purpose: the OAuth client comes from `android/app/google-services.json` (via the `default_web_client_id` string resource the google-services Gradle plugin generates) and from `ios/Runner/GoogleService-Info.plist`. Do not hardcode a `serverClientId` — re-download those files from the Firebase console instead. They only contain an OAuth client once a SHA-1 fingerprint is registered for the Android app.

`firebase_options.dart` only configures Android and iOS — macOS, Windows, Linux and web throw `UnsupportedError`, even though those platform folders exist.

The app id is `com.mna.iter` on every platform. On iOS, `ios/Runner/Info.plist` declares a `CFBundleURLTypes` scheme that must stay identical to `REVERSED_CLIENT_ID` in `GoogleService-Info.plist`; re-registering the iOS app in Firebase changes that value and the plist has to be updated by hand.

## Nickname uniqueness

Nicknames are unique, and that is enforced by the *shape* of the data, not by application code: `nicknames/{nickname}` holds `{uid}` with the nickname as the **document ID**. Security rules allow `create` and `delete` there but never `update`, and Firestore only lets `create` succeed when the document does not exist — so two clients cannot claim the same handle, with no read-then-write race.

This is why a `where('nickName', '==', x)` query on `user` is not an option: security rules cannot run queries (only `get()`/`exists()` on a known path), so uniqueness would be unenforceable, and checking availability would require read access to other people's profile documents.

`NicknameController.change()` does the swap in one `WriteBatch` (create new claim + delete old + update `user/{uid}.nickName`) so a rejected claim leaves nothing behind. Nicknames are normalized (lowercase, accents stripped, `^[a-z0-9._-]{3,20}$`) and the same regex is duplicated in `firestore.rules` — change both together. `user/{uid}.nickName` is a deliberate denormalized copy for display.

Sign-in reserves a generated nickname in the same batch that creates the user document, retrying with a new random suffix when the claim is denied.

Nicknames are app-generated and there is deliberately no UI to change one — `NicknameController.change()` exists for when that arrives, and stamps `user/{uid}.nickNameChangedAt` so a future cooldown or paid gate has data to read (absent = never changed). If that change ever becomes paid or rate-limited, enforcement has to move out of the client: rules today let the owner delete and re-create their own claim, which is enough while nothing gates it, but a client can never be trusted to charge itself.

## Route list ordering

`NewRouteModal.dateRoute` is a `dd/MM/yyyy` **string**, so a Firestore `orderBy('dateRoute')` sorts it as text and puts `02/01/2026` before `31/12/2025`. `RouteController.watchAll()` therefore reads `iter/{uid}/routes` unordered and sorts in memory: `sortByDate` ranks by **distance from today** (nearest first, in either direction), preferring the future on a tie, `createdAt` as final tiebreak, unparseable dates last. It takes an optional `reference` date so tests do not depend on the clock. No Firestore index can express this ordering — it changes every day. That means the whole collection is downloaded; adding pagination later requires writing a sortable ISO field on save and backfilling existing documents. See `docs/specs/lista-iter.md`.

## Create and edit share one form

`AddIter` is both the create and the edit screen: pass an existing `route` and it prefills the controllers in `initState` and saves with the **same id**, so `RouteController.save()`'s `set` replaces the document instead of adding one. `createdAt` is carried over from the original. The list opens it with `Navigator.push(MaterialPageRoute(...))` rather than the `/addIter` named route, because that route's `settings.arguments` carries a single untyped `Object?` and editing needs both the user and the route.

## Route times

`NewRouteModal.startAt` is a required `DateTime` (ISO in Firestore) and `endAt` an optional one — a route is scheduled knowing when it starts, but the end is only known once it is over. `RouteTime.resolveEnd()` rolls the end to the next day when it is not after the start, so a 22:00→02:00 route has a real 4h duration instead of a negative one; never rebuild an end time without it. `fromMap` reconstructs both from the older `dateRoute` + `hoursInitial`/`hoursFinal` fields when `startAt` is absent, so pre-existing documents keep loading.

## Model serialization

`NewRouteModal` stores its `Company` and `StatusRoute` enums as bare strings (`company.toString().split('.').last`) and rebuilds them by matching `'Company.${map['company']}'`. Renaming an enum value breaks stored documents; change both directions together.

## Weather

`lib/services/openWeather.dart` calls OpenWeather's **free** `/data/2.5/weather` and maps `weather[0].main` — which sits at the **root** of that response — onto the `WeatherType` enum. `lib/Utils/weather.dart` turns it into an asset path (`getWeatherIcon`) or into the widget (`weatherImage`).

`getWeather` returns `WeatherType?` and `null` means *could not find out* (no key, no network, unexpected body). Never collapse that back into `WeatherType.clear`: doing so is what hid a broken call for months, because "it failed" and "the sky is clear" both drew the same sun. `weatherImage(null)` draws a neutral icon instead.

One Call 3.0 — the only endpoint that would give the weather of a **past** date, for routes logged days later — answers 401 with the current key: it needs the paid "One Call by Call" plan. `/2.5/weather` (now) and `/2.5/forecast` (5 days) are what the key can reach.

The key comes from `.env` (gitignored, holds `OPEN-WEATHER`, declared as an asset) via `dotenv.load()` in `main()`, wrapped in try/catch: a clone without the file still boots, the weather just reads "unknown". Coordinates are still hardcoded to Fortaleza in `addIter.dart`.

`NewRouteModal.weather` is written **only when creating** a route. Editing keeps whatever is stored (`_fillFromRoute` restores it) — the API only knows the sky of *now*, so refetching would stamp today's weather onto a route from last week.

## Known incomplete work

Several files are intentionally empty placeholders: `lib/route.dart`, `lib/screens/listIter.dart`, `lib/services/saveIter.dart`.

- `AddIter._saveRoute()` is unreferenced, and its guard is inverted (`if (!validate())` builds the route); the save button only shows a dialog.
- `test/widget_test.dart` pumps `MyApp`, which now needs an initialized Firebase, so it throws before it even reaches its (already wrong) counter assertions.
