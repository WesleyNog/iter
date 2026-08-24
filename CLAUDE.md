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
  screens/               full pages (login, home, addIter, listIterScreen,
                         graficsScreen, vehiclesScreen, addVehicle, …)
  widget/                reusable UI helpers exposed as top-level functions
  services/              Firebase + external API access
  controller/            per-collection Firestore read/write (UserController)
  model/                 plain data classes with toMap/fromMap
  Utils/                 pure helpers (note the capital U — imports are 'package:iter/Utils/...')
```

File names are camelCase (`addIter.dart`, `newRouteModal.dart`), not Dart's usual snake_case. Follow the existing convention rather than mixing styles.

Widgets in `lib/widget/` are top-level functions when they *show* something (`showNotification`, `showCupertinoDatePicker`, `showBairrosMultiSelect`, `showFipePicker`) and `StatelessWidget`/`StatefulWidget` subclasses when they are a *piece of a screen* (`RouteCard`, `VehicleCard`, `PartsEditor`). `showBairrosMultiSelect` takes the caller's `setState` so the sheet can refresh the parent screen.

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

`weather[0].main` does not distinguish day from night — `weather[0].icon` does,
with a `d`/`n` suffix OpenWeather computes from that point's sunrise and sunset.
Reading the suffix costs nothing and depends on no timezone, season or latitude;
a cut-off hour hardcoded here would be wrong twice a year and wrong always for
anyone outside Fortaleza. `clearNight` and `cloudsNight` are the **only** two
types derived from it, because they are the only two with a drawing: rain at
night stays `rain`, and a type without an asset throws inside `Image.asset` in
the route list. A missing or non-string `icon` never becomes night — the daytime
type is the one that invents nothing. The two exist because Amazon routes run
past 19:00 and the only honest option for a clear night sky used to be
"Nublado", which is the opposite of what the sky was.

That suffix describes the **moment of the request**, and the fetch runs when the
form opens — before the driver has picked the route's date and time. So
`getWeather` returns a `CurrentWeather` carrying `sys.sunrise`/`sys.sunset` as
minutes of the local day, and `CurrentWeather.at(startAt)` re-decides day or
night for the route's own hour; `addIter` calls it again whenever the date or
the start time changes. Without that, a route run 08:00–14:00 and registered at
21:00 got a moon next to the very times that disproved it — and the app already
had a second, disagreeing definition of night in `Shift.noite` (18h–23h). When
the response carries no sun times, `at` returns the daytime type: the suffix
describes an hour that is not this route's, and promoting by it is the bug
itself.

Adding a `WeatherType` value is safe for documents already written —
`fromString` falls back to `clear` for anything it does not know — but it does
**not** reinterpret them: a night route recorded as `clouds` before these values
existed stays `clouds`, the same frozen past the provision rule protects.

That is precisely why the charts group by **sky, not by hour**. `_weatherLabelOf`
runs the stored type through `daytimeOf` before labelling, so "Nublado" and
"Noite nublada" are one bar in `failuresPerWeather` and `failureRatePerWeather`.
Keeping them apart would split one population into two smaller steps purely by
registration date — and with `maxBars: 4` in the chart and only the leader shown
in the rate card, the worst weather could vanish from the screen because it had
been divided in half. The moon still shows on the route card, where the hour is
information; in the ranking it is noise.

`nightVariantOf` and `daytimeOf` share **one** map, the reverse derived rather
than written twice: a pair that existed on only one side would promote a sky on
the way in and never undo it on the way out.

`NewRouteModal.weather` is written **only when creating** a route. Editing keeps whatever is stored (`_fillFromRoute` restores it) — the API only knows the sky of *now*, so refetching would stamp today's weather onto a route from last week.

## Vehicles and cost per KM

`iter/{uid}/vehicles/{id}` holds the driver's vehicles and the parameters that
turn **kilometres driven into money**. The whole feature exists to reproduce the
`Gastos` block of the owner's spreadsheet, and every field either feeds that
calculation or identifies the vehicle in the list — there is deliberately no
plate, colour or FIPE price. See `docs/specs/cadastro-veiculo.md`.

One formula for every line, in `lib/Utils/vehicleCost.dart`: **price ÷ how many
km it lasts**. Fuel is not a special case — its "price" is the litre and its
"life" is the km/l. `MaintenancePart.quantity` exists because a car burns four
tyres per change: without it, "R$ 500 a tyre" would provision a quarter of what
it should. A rate that cannot be computed is `null`, never `0` and never
`infinity`, and `unpricedParts()` names the parts left out so a screen can say
which — a part dropped in silence is cost the driver thinks he provisioned.

### The provision is frozen, on purpose

`NewRouteModal.provision` is written when a route is saved as `concluido` or
`pago`, and stores **values in reais** — never the rate, never a pointer to the
vehicle. Rates get edited; frozen values do not. `RouteProvision.profitFrom()`
derives the profit rather than storing it.

Fixing this is one of the stated reasons the app exists: the spreadsheet's cost
columns are formulas pointing at the month's parameter block, so raising the
tyre price rewrites the profit of days that already happened. **Never make any
money aggregate recompute the past from a current rate.**

`resolveProvision()` owns the rule, and the case that matters is *same KM and
same vehicle → keep what is stored*, even when the vehicle's rates changed since.
Correcting a neighbourhood on a June route must not restamp it with today's
fuel price. KM is compared with a one-metre epsilon, not `==`.

Which vehicle is in use lives in `user/{uid}.activeVehicleId` — one atomic write
to switch, where an `isActive` flag per document would need a transaction and
could still end up with zero or two. `VehicleController.activeFrom()` is the
**single** resolution used by the AppBar, the list and the provisioning; two
implementations would let the screen draw one car while the maths used another.
It falls back to the first vehicle when the stored id is orphaned.

### FIPE and the car image

`lib/services/fipe.dart` (no key, 500 req/day) lists brands, models and years so
the driver picks the car instead of typing it. Two shapes to respect: `codigo` is
a **String** in `/marcas` but an **int** in `/modelos`, and `/modelos` comes
wrapped in `{"modelos": […]}` while the others are bare arrays. Bodies are read
with `utf8.decode(bodyBytes)` — `response.body` assumes latin-1 and turns
"Citroën" into "CitroÃ«n". Like `getWeather`, these return `null` for *could not
find out*; an empty list means only what it says.

The image is a **URL** built by `lib/Utils/carImage.dart` and never stored as
bytes — imagin.studio's licence forbids downloading, caching and modifying, and
the demo `customer=img` watermarks. Two filters, because neither is enough:
`imaginHasImage()` drops "I don't have that vehicle", and the user's
"É esse o seu carro?" drops "I have one, but it's the wrong car" — asking for
`honda/cg` answers `found=true` with a Honda Pilot. Motorcycles always return
`null`. Never store `imageUrl` before the user confirms.

`image_picker` is the only dependency this feature added. Photos go to
Firestore as base64 (`maxWidth: 800, imageQuality: 70`, refused above 700 KB),
not to Storage, which would need the Blaze plan. Decode with
`decodePhoto()` from `widget/vehicleThumb.dart`: bare `base64Decode` **throws**,
and it throws before any `errorBuilder` runs, so one corrupt document would take
down the whole list. iOS needs `NSCameraUsageDescription` and
`NSPhotoLibraryUsageDescription` in `Info.plist` or it kills the app on open.

## Expenses are a statement, never a deduction

`iter/{uid}/supply` (fuel-ups) and `iter/{uid}/maintenance` record **money that
actually left the pocket**. The Summary tab shows them in an expense card below
the company cards.

**Never subtract them from route profit.** That profit already charges fuel and
parts as a *provision* (`km × R$/km`); subtracting the real spend counts both
twice. The card carries a line saying so, because seeing "Lucro R$ 175,60" above
"Gastos R$ 430,50" invites the arithmetic — and the arithmetic is wrong.

Comparing the two some day — "I provisioned R$ 628 of fuel and spent R$ 590" —
is the real value this data unlocks. Adding them is not.

Both feed the vehicle back, and both only ever **ask**: a fuel-up knows the real
price per litre, a *replacement* knows the real price of a part. `Utils/
expenseRules.dart` owns those rules. A **repair** never offers — fixing a tyre
for R$ 80 is not the price of a new tyre, which is what the Reparo/Substituição
toggle exists to distinguish. Updating `Vehicle` changes the cost per km of
every future route, so it is always the owner's call.

## Measured km/l

`Utils/fuelEconomy.dart` turns the odometer recorded at each fuel-up into the
**third** number that used to be typed once and never revisited — litre price
and part price were the other two. Distance between the first and last odometer
reading, over the litres of every fill **except the first**: that one filled the
tank that drove the distance *before* the window, and counting it makes the car
look thirstier than it is.

The failure that matters is the one that flatters. Litres are optional, so a
fill without them puts fuel in the tank that never reaches the denominator — a
higher km/l, a smaller fuel provision, and **overstated profit on every route**.
So a fill without litres *inside the window* invalidates the window:
`EconomyResult` carries a `gap` naming what is missing instead of a pretty
wrong number, and the same guard rejects an odometer that does not advance
(`128.800` typed as `12.880` would otherwise divide by a negative).

One result **per fuel**: ethanol runs ~30% fewer km per litre, so a single
average would describe neither tank of a flex car.

The number is *shown* from 2 fills but only *offered to the cadastro* from 3
(`_minimumFills`), because the estimate assumes the tank sat at the same level
at both ends — an error bounded by one tankful, which shrinks as the
denominator grows (~15% at 3 fills, ~2% at 20). Changing the provision of every
future route on one reading is not worth it.

Vehicle card shows the **lifetime** number, the summary's expense card the
**period** one — "how much does my car do" and "how did this month go" are
different questions. `periodEconomy()` returns `null` unless every fill in the
period belongs to one vehicle, a missing `vehicleId` included.

## Sem Rota: money and kilometres, but not a route

Sometimes Mercado Livre or Amazon offer a route, the driver accepts, drives to
the CD — and the route is gone. They pay anyway, each by its own rule.
`StatusRoute.semRota` records that, and `norouterule/{company}` holds the
percentage (`{percent: 40}` for ML, `100` for Amazon; the id is `Company.name`).
See `docs/specs/sem-rota.md`.

**`NewRouteModal.value` stores the net**, percentage already applied, plus a
frozen `NoRoutePayment {grossValue, percent, appliedAt}`. Both halves earn their
place: the net is what makes `summarize`, `companySummary`, `valuePerCompany` and
the profit work without any of them knowing the rule exists — and the gross is
what lets the form reopen without applying the percentage **again**, turning
R$ 250 into R$ 100 and then R$ 40, once per edit, silently. `paid` is derived, and
`route.value == payment.paid` is exact-equality: both sides go through
`NoRoutePayment.paidValue`, which works in integer cents because
`gross * (percent/100)` and `(x*100).round()/100` each round wrong in cases the
screen hides behind `toStringAsFixed(2)`.

`resolveNoRoutePayment` is `resolveProvision`'s sibling and freezes for the same
reason — **same company keeps the stored percentage**, even after the console
changes it. Only switching company reloads: the ML percentage does not describe
an Amazon trip.

### Two rulers, and `realized` is not one of them

`realized()` is still `concluido + pago` and **was not touched**. That is how the
trip stays out of the route count, the bairro rankings, the packages, the friends'
ranking and the career numbers — without a line of new code in `monthStats`,
`profileStats` or the analysis carousels. What needs the money uses
`noRouteTrips()`; `receivedPayment()` includes it because it was already paid.

The trip **is** kilometres, though: `NewRouteModal.hasRun` (`concluido + pago +
semRota`) gates the provision, so the fuel burned driving to the CD is charged
like any other. That getter exists because the condition used to be written three
times — and `addIter._withProvision`'s copy runs *first*, so fixing only
`vehicleCost.dart` provisioned nothing, with the unit test green.

**No average may divide money from one population by the count of another.** With
the trip in `total` and out of `count`, `total / count` inflates — the side that
flatters. Hence `PeriodSummary.routeTotal` (route money) beside `total`
(everything), and `receivedTotal` (paid + trips) beside `received` (paid only).
`CompanySummary.isEmpty` checks both counts for the same reason: a month of only
CD trips has money and KM, and `routes == 0` alone made the whole Summary tab say
"Nenhuma rota entre 01/08 e 31/08".

`norouterule` is `get` + `list: false` + **`write: if false`**. It is the first
collection in the app that is *business configuration* rather than user data:
`gastop` is writable because whoever passes the station reports the price, and
the worst case is one wrong price the median dilutes. Here a writable `percent`
lets any authenticated account zero everybody's pay. The owner edits it in the
console — and **the deployed rule creates no data**: until
`norouterule/mercadolivre` and `/amazon` exist there, every company behaves like
Shopee, with `npm test` and `flutter test` both green. It is the one step no test
catches.

Missing rule is refused, never defaulted. 100% overstates the earning, which is
the side that misleads, and 0% zeroes the value — which drops the provision with
it, because `provisionFor` bails on `value <= 0`, and the fuel of a real trip
would vanish. Reading failure is a **different** sentence from missing rule: the
first read of this collection on a device never comes from cache, so offline is
the common case, and collapsing the two would tell a driver with no signal to go
register a rule that is already there.

## Friends: consent lives in the rules, not in the client

`profiles/{uid}` is the public projection — name, `@nickname`, photo — because
`user/{uid}` holds CPF, e-mail and phone and can never open. It is written from
the **`User` of FirebaseAuth**, never copied from `user/{uid}`, whose `name` and
`photoUrl` have been frozen since the first login. The hook is
`HomeScreen.initState`, not the sign-in: `signInWithGoogle()` never runs for a
restored session, which is precisely why that document froze.

Use `allow get`, never `allow read`, on anything world-readable. **`read` is
`get` + `list`**, and a condition that does not inspect `resource` lets any
authenticated client download the whole collection. `nicknames` shipped that way
and handed out the full `@nickname → uid` map until it was closed.

Friendship is two edges, `friends/{a}/list/{b}` and its mirror, and the rule
that creates one demands the other **in the same commit** via `existsAfter()` —
cross-document atomicity without Cloud Functions. `exists()`/`get()` see the
state *before* the batch, which is what lets the accept read an invite marker
the same batch deletes. Accepting clears all **four** marker paths, because a
mutual invite writes markers on both sides. The edge body is only `at`, pinned
to `request.time` so a guest cannot sort themselves to the top of your list.

`profiles/{uid}/stats/{all|yyyy-MM}` is recomputed from the routes, never
incremented — `increment` drifts the first time a route is edited. See
`docs/specs/amigos.md`.

The rules have tests: `cd firestore-tests && npm test` runs 90 cases against
the Firestore emulator. It is a Node project on purpose, and deliberately
**outside `test/`** — `flutter test` globs that directory for `*_test.dart` and
would walk `node_modules` on every run. The emulator needs **Java 21+** while
the Android build needs 17, so `run.sh` points `JAVA_HOME` at the JDK bundled
with Android Studio for that command only. Never change the system java.

The console's rules simulator no longer exists (Google removed it), and it
could not test batches anyway — which is where `existsAfter` lives. Change a
rule, run `npm test`, then deploy.

## The project is on Blaze

Since 2026-08-07, for Storage. Cloud Functions and Storage are therefore
available, and several "impossible without a server" notes in older specs are
now merely "costs money per use". Two things that did not change: rules are
still the cheapest defence and the only one that holds when a server exists,
and the Android `release` build still signs with the debug key. Before the
first Function, set a billing budget and alert — the runaway risk is a trigger
that writes the document that fires it, not the feed.

## The Feed: the global collection is the most validated one

`posts` is world-listable, so it is the collection with the strictest `create`
rule in the project — not the loosest. `hasAll` + `hasOnly` + a 500-char cap +
`createdAt == request.time`, because a post dated 9999 pins itself to the top
of everyone's mural forever and `update` is restricted to the tombstone.

**Deleting a post is marking it.** Firestore does not cascade into
subcollections: a real delete would leave the likes behind, free the id for a
new post to inherit that thread, and make the owner's moderation `get()` error
— which is the same as denying. Deleting would be the gesture that makes an
offence permanent. `allow delete: if false`.

The tombstone `update` is pinned to the **exact shape** `PostController.erase`
writes (`deleted == true && text == '' && imagePath == null`), not to a set of
keys. `diff().affectedKeys().hasOnly([...])` says *which* keys changed and never
*what they changed to*, so on its own the update was a back door around every
`create` guard: a 10-character post became 1 MiB of permanent, undeletable text
in a world-listable collection, and `imagePath` escaped the `^posts/{my uid}/`
prefix that only `create` enforced, repointing at someone else's Storage object.
And because `exists()` is true for a tombstone, `likes` and `comments` check
`get(...).data.get('deleted', false) == false` instead — otherwise the gesture of
the person who was offended, deleting their own post, left the thread alive,
still accepting text, still readable by anyone holding the id, and invisible to
the owner, who moderates blind. `.get('deleted', false)` and not `.deleted`: a
missing key **errors**, and error means deny, which would silently break the
posts published before the field was required.

The photo lives in Storage and the document stores the **path**, never the
`getDownloadURL()` result: that URL carries a token, is served without auth,
bypasses `storage.rules` entirely, and can only be revoked by hand in the
console.

The author is **not** denormalized into the post. Only `uid` — name, photo and
nickname come from `profiles/{uid}`, prefetched once per page into a Map. Any
author field inside the post would be unverifiable by the rules, which is
impersonation for free on a global wall.

`profiles/{uid}/stats/*` is friends-only (`exists()` on the owner's list),
because a public wall hands out uids to anyone who scrolls. `fetchCareer`
returning `null` means **"not allowed to see"**, never zero.

## Blocking, reporting, commenting: the order was the design

Comments shipped **after** blocking and reporting, and that ordering is the
whole argument: a like is a button and cannot offend anyone; a comment is free
text from one person appearing under another person's post. Whoever publishes
owns what they wrote — whoever gets commented on did not choose it.

`blocks/{uid}/list/{otherUid}` is owner-read-only. **That hides the list, not the
fact** — `permission-denied` is distinguishable from "no signal" (an offline
write stays pending in the SDK; a denied one comes back immediately), and a
prober eliminates the other conditions first, since profiles are readable and
their own block list is readable. Blocking stops contact; it does not conceal
that it happened. Do not write a comment claiming otherwise — the first version
of these rules did, and a false security claim is the sentence that stops the
next person from looking.

What *is* achievable without a server is making the probe **noisy**, and that is
why `!bloqueioEntre(...)` lives only on the `incoming` match. The invite is one
atomic `WriteBatch` over both documents, so denying `incoming` denies the whole
invite; repeating the check on `outgoing` — a document in the prober's *own*
subtree — protected nothing and handed out a silent, repeatable, traceless
oracle ("denied, therefore she blocked me"), which combined with the `uid`s that
`list` on `posts` hands out is a map of who blocked you across the whole base.
The probe that remains has to write into the victim's inbox, which lights up her
badge. A stray `outgoing` marker never becomes a friendship: the edge still
needs the victim's `incoming`, which only she can create.

Blocking removes the two friendship edges and all four invite markers in the
same commit (`FriendController.severTies`, shared with `remove()`): a live
marker keeps authorizing the edge, so the friendship would come back on the
next accept. Unblocking does **not** restore the friendship.

Filtering the wall is client-side and cannot be anything else — `posts` is a
global listable collection and rules do not filter queries. What the rule
guarantees is the other direction: a blocked person cannot comment on your
post, which is what stops the harassment everyone *else* would still see.

`reports/p_{postId}__{uid}` (or `c_{postId}_{commentId}__{uid}`) is the report,
and **the document is the channel**: there is no server, so the queue is read in
the Firebase console and hiding a post is an admin write. `get` and `list` are
`false` for everyone, reporter included — a readable report collection is the
list of who denounced whom. The id gives one report per person per target by
*shape*, the reason is a closed list (never free text — that field would be the
first place someone writes another person's phone number), and the absence of
`commentId` is what says the target is the post, so `toCreateMap()` omits the
key instead of writing `null`.

Three things that look like detail and are not. The `p_`/`c_` prefixes exist
because post ids and comment ids are both **chosen by the client**: without
them, publishing a comment whose id equals a post id made one report silently
overwrite the other, in a collection whose `delete: if false` promises nothing
is ever lost. `_` is only a safe separator because `create` on `posts` and on
`comments` now requires `^[A-Za-z0-9-]{1,64}$` — that rule also stops an author
from picking a 1490-byte id, which would push every report id past Firestore's
1500-byte document-id limit and make their own content **unreportable forever**.
And the target check is `get(...).data.uid != request.auth.uid`, not `exists`:
`exists` only forbade reporting what does not exist, it never forbade
*fabricating* what does — publish a comment, report yourself, delete the
comment, repeat, and every lap left an undeletable document in the one
moderation channel the feature has.

Reporting hides the post locally and does not persist that: blocking is what
solves it for good, and storing "posts this user hid" would be another
collection and another read per feed open.

Comment threads use `snapshots()` while the wall uses `get()` — a listener on
the wall re-delivers documents on every like by anyone, to everyone with the app
open; a listener on a thread re-delivers one post's comments to the person
staring at them. `parseComments` re-sorts in Dart even with `orderBy` in the
query, because `serverTimestamp()` arrives **null** in the local snapshot and
null sorts first: without it a just-written comment jumps to the top of the
thread and drops back a second later. `count()` gives the card's comment
badge and cannot discount blocked authors — the sheet reports the number it
actually drew when it closes.

## Filters: empty and complete are the same answer

The company rail on the route list is multi-select and has **no "all" segment**,
because an empty set and a full one both mean *show everything*. That rule lives
**once**, in `_passes` of `Utils/routeFilter.dart`, and serves both the company
rail and the status chips — written twice, one copy falls behind on the first
adjustment. Tapping a lit segment emits *that* segment: the widget never toggles
itself, because two places toggling on their own is how one tap ends up marking
on one half of the screen and unmarking on the other.

`RouteOrder.pertoDeHoje` is the default and **returns the list untouched**.
Ordering by distance from today belongs to `RouteController.watchAll` and to
nowhere else — see `docs/specs/lista-iter.md`. A second implementation would be
two lists disagreeing about what "today" is.

**A saved money range and freshly computed bounds are not the same era.** The
filter stores reais, the bounds come from the current list, and between one
opening and the next the list changed — the very screen that opens the sheet
deletes routes by swiping and edits values in the form. A 300–500 range over a
list whose ceiling dropped to 250 makes `RangeSlider` **throw**
(`assert(values.start >= min)`). The range is *discarded*, never squeezed: a
filter that rewrites itself misleads more than one that switches off, and it
leaves the badge with it. `valueBounds` compares the **raw** values, before
rounding — written after it, a single R$ 123 route produced a perfectly valid,
perfectly useless 120–130 band.

**`home.dart` is `body: screens[current]`, not an `IndexedStack`.** Switching
tabs unmounts the screen and disposes its `State`, so nothing a screen holds in
`setState` survives — the filter, the expanded card, the last snapshot. Holding
the *widget* in a `late final` field preserves the widget and never the state.
The first version of `docs/specs/filtros.md` claimed the opposite and was on its
way to becoming a code comment; the fix was reading `home.dart`, which is the
only thing that ever settles it.

Week arithmetic goes through the `DateTime` constructor, never `Duration`:
`DateTime(y, m, d - (weekday - 1))` for Monday, `d + 6` for Sunday. `add(const
Duration(days: 7))` adds 168 hours, which in a DST zone lands on the wrong hour
of the right day and moves a period's edge by a day. Brazil dropped DST in 2019
and Fortaleza never had it, so both spell the same result today — the
constructor is chosen because it stays right elsewhere and costs nothing.

## Widget tests cannot tell you whether text fits

Two traps, both hit for real in this project:

**Wrapping is not overflow.** `tester.takeException()` catches `RenderFlex
overflowed`, but a label that wraps to two lines raises nothing — the test stays
green and the broken layout ships. A `SegmentedButton` reading "Substituição"
passed three width tests and still wrapped on the user's iPhone.

**The default test font is square.** Measured: 14.25 px per character at
`fontSize: 14`, every glyph one em wide. "Substituição" is 171 px in a widget
test and roughly 85 px on a device. Asserting "does it fit?" therefore fails
layouts that work, and designing to satisfy it means designing for a font that
does not exist.

So test the *cause*, not the symptom: that a control gets the full width, that
two fields share a row, that a `DropdownButtonFormField` has `isExpanded: true`.
Those hold regardless of font. Whether the text looks right is the device's
call — see `test/widget/addMaintenance_test.dart` for the pattern.

## iOS device builds

Installing on a physical iPhone can fail with `No code signature found` on a
Pods framework (`grpcpp.framework` is usually the first one iOS checks). It is
almost never a Podfile or signing-config problem — `DEVELOPMENT_TEAM` is set and
`CODE_SIGN_STYLE` is Automatic in the project.

CocoaPods deliberately leaves pod frameworks unsigned (`CODE_SIGNING_ALLOWED =
NO`, 75 times in `Pods.xcodeproj`); the Runner's `[CP] Embed Pods Frameworks`
phase signs them on the way in. A corrupted DerivedData makes that phase copy
frameworks from mismatched builds, and the `.app` ends up **partly** signed —
that mix is the tell. A build genuinely made without signing leaves *all* of
them unsigned, `App.framework` included.

The fix is the cache, and it is safe — nothing but build artifacts:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
flutter clean && flutter pub get
flutter build ios --debug          # ~11 min; re-signs all 29 frameworks
```

Verify before blaming anything else:

```bash
for f in build/ios/iphoneos/Runner.app/Frameworks/*.framework; do
  codesign -dv "$f" 2>&1 | grep -q "not signed" && echo "unsigned: $f"
done
```

A related symptom of the same corruption is
`unable to rename temporary '…/round_robin.o.tmp'` while building gRPC-Core.

## Known incomplete work

Two files are intentionally empty placeholders: `lib/route.dart` and
`lib/services/saveIter.dart`.

- `test/widget_test.dart` pumps `MyApp`, which now needs an initialized Firebase, so it throws before it even reaches its (already wrong) counter assertions. Every other test passes.
- The Amigos tab has all three sub-screens working (friends/invites/search,
  ranking, feed with posts, likes, comments, blocking and reporting). What is
  left there is **App Check plus a billing budget and alert** — the one item
  `docs/specs/amigos.md` marks as "do it before the app leaves your phone",
  because a globally writable collection on Blaze without App Check is a
  ten-line script making you pay. Also missing: automatic moderation (today the
  report queue is read by hand in the console) and the Function that would
  delete the likes/comments subcollections of a tombstoned post — that one is
  quota economy, not correctness.

`AddIter._saveRoute()` **is** wired (`addIter.dart:838`) and its guard is correct
(`if (!validate()) { notify; return; }`); the save button really writes to
Firestore. An earlier version of this file claimed otherwise — do not budget for
fixing a save path that works.
