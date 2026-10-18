# Third Place

A dating app for people who have already crossed paths. It reads only the **where** and **when** of your photos, on your phone, finds your third places (the cafés, gyms and parks you keep going back to, never home or work), and shows you people who share them.

## Run it

Requires Xcode 16.3+ and an iOS 17+ simulator.

```sh
open ThirdPlace.xcodeproj        # then Run on an iPhone simulator
```

The simulator's photo library has almost no geotagged photos, so load the test persona first (a year of a London life plus a festival and a few trips):

```sh
./Tools/seed-simulator.sh        # adds ~475 geotagged photos to the booted simulator
```

Without a backend config the app runs fully on the phone with demo people. To restart onboarding: long-press **Crossed paths** at the top of the feed.

## Connect the backend (Supabase)

1. Create a free project at [supabase.com](https://supabase.com).
2. In the dashboard: **Authentication → Sign In / Providers → Allow anonymous sign-ins** → on.
3. Apply the database, in order: `supabase/migrations/20261018120000_core.sql`, `supabase/migrations/20261018120100_storage.sql`, then `supabase/seed.sql` for demo people (development only). Either paste each into the dashboard's **SQL Editor**, or use the CLI:
   ```sh
   brew install supabase/tap/supabase
   supabase login
   supabase link --project-ref YOUR-PROJECT-REF
   supabase db push
   supabase config push
   ```
   and then run `seed.sql` in the SQL Editor.
4. Copy `supabase/Supabase.example.json` to `ThirdPlace/Supabase.json` and fill in the project URL and the **anon / publishable** key (Project Settings → API). Never put the service-role key in the app.
5. Run the app and go through onboarding again. The reveal now shows real counts, sign-up creates an account, and the feed shows real people.

The chat migration (`20261018130000_chat.sql`) is applied the same way. The demo people's auto-replies at the end of `seed.sql` are for development only.

## Sign-in

- **Email** works today. Supabase's free plan sends a sign-in **link**; tapping it on the phone opens the app through `thirdplace://auth` and signs you in.
  - The built-in email service only delivers to your Supabase team's own addresses and a couple of emails an hour. Before real users, connect an email provider (Authentication › Emails › SMTP Settings; Resend or Postmark both work).
  - Once SMTP is connected, switch to 6-digit codes: uncomment the templates in `supabase/config.toml`, run `npx supabase@2 config push`, and add `"emailCodes": true` to `ThirdPlace/Supabase.json`.
- **Skip for now** creates an anonymous account. People can add an email later from the You screen; until then the app reminds them it only lives on this phone.
- **Sign in with Apple** is written but switched off. It needs a paid Apple Developer account:
  1. In Xcode, sign in with that Apple ID, pick the team for the ThirdPlace target, and add the *Sign in with Apple* capability.
  2. In Supabase: Authentication › Providers › Apple › enable, and add the app's bundle ID `app.thirdplace.ios` to the client IDs.
  3. Add `"appleSignIn": true` to `ThirdPlace/Supabase.json`. The Apple button then appears above email.

## Tests

```sh
cd Packages/ThirdPlaceCore && swift test       # clustering, rhythms, blurring, ranking
cd Packages/ThirdPlaceBackend && swift test    # what's allowed to leave the phone
supabase/tests/run-local.sh                    # schema, privacy rules, feed, likes, matches, chat (local Postgres)
```

The SQL tests run the real migrations on a throwaway database in your local Postgres, with a small stand-in for Supabase's auth schema.

## What's here

```
ThirdPlace/                    SwiftUI app (iOS 17+)
  Design/                      Theme (colours, type) and shared components
  Model/                       App state, saved data, feed people (real or demo)
  Services/                    Photo library reader, Apple Maps naming, local storage, backend config
  Screens/                     Onboarding steps and the feed
Packages/ThirdPlaceCore/       Pure Swift, tested
  Geohash, Blur                ~150 m area codes and hour rounding: all that ever leaves the phone
  PlaceAnalyzer                Photos → home, work (hidden), third places with rhythms, moments
  Affinity                     Ranking: shared #1 place, specificity weighting, same-time bonus
Packages/ThirdPlaceBackend/    Supabase client: sign-in, profile, photos, sync, feed, likes, matches
supabase/
  migrations/                  Schema, row-level security, feed and matching functions, photo storage
  seed.sql                     Seven demo people around the test persona's London places
  tests/                       Local Postgres test suite
Tools/                         Test photo generator for the simulator
```

## How the backend keeps the privacy promise

- The server never sees a photo or an exact location. It gets **presence**: a ~150 m area code and an hour.
- Presence is only uploaded for places and moments you kept, and the database rejects anything else, so home and work can't leak even by a bug.
- Nobody can read anyone else's places or presence. The feed comes from a function that returns a category and neighbourhood ("Café · Hackney") before a match, and the venue only after a mutual like.
- Before sign-up the app only asks "how many people share these places?", and counts under 2 are reported as 0.
- Only matched people can message each other. Unmatching deletes the conversation for both; blocking and reporting also make sure neither person sees the other again. Reports are write-only for users.
- Deleting the account removes the profile, places, presence, likes, matches and photos.

## Feed ranking

`score = 0.75 · similarity + 0.10 · co-presence + 0.15 if you share a #1 place`

- **Similarity**: cosine of place profiles (each person's share of visit days per place), each place weighted by how specific it is, so a small bookshop counts for more than a huge park.
- **Co-presence**: shared (area, hour) slots, saturating.
- Implemented in SQL (`get_feed`) and mirrored in `ThirdPlaceCore/Affinity.swift`.

## Status

Working:
- Photo-library scan, on-device clustering, home and work detection, rhythms, moments, Apple Maps venue names
- Full onboarding and a Hinge-style feed with likes on specific parts of a profile and 8 likes a day
- Backend: accounts, profiles, photo storage, blurred presence sync, real overlap counts, ranked feed, likes, passes, matches with venue reveal, account deletion
- Matches and real-time chat, with openers built around the place you share; unmatch, block and report
- Email sign-in by link, "Skip for now" accounts that can add an email later, a You screen with sign-out and delete
- Schibsted Grotesk, Geist and Geist Mono bundled (SIL Open Font License, in `ThirdPlace/Resources/Fonts`)

Not yet:
- Custom SMTP (needed before real users) and 6-digit email codes
- Sign in with Apple (written, needs an Apple Developer account)
- Real selfie liveness check (simulated)
- Push notifications for new matches and messages
