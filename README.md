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

## Tests

```sh
cd Packages/ThirdPlaceCore && swift test       # clustering, rhythms, blurring, ranking
cd Packages/ThirdPlaceBackend && swift test    # what's allowed to leave the phone
supabase/tests/run-local.sh                    # schema, privacy rules, feed, likes, matches (local Postgres)
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

Not yet:
- Sign in with Apple, Google and phone (accounts are anonymous for now and can be linked later)
- Real selfie liveness check (simulated)
- Chat after a match
- Bundled fonts (Schibsted Grotesk, Geist, Geist Mono; swap in `Design/Theme.swift`)
