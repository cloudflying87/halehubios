# HaleHub iOS App — Status

**Last Updated:** May 15, 2026
**iOS Project:** `/Users/davidhale87/Coding/HaleHubIOS/`
**Django Project:** `/Users/davidhale87/Coding/halehub/`
**API Base:** `https://flyhomemn.com/api`

---

## What's Been Built

### Django REST API (`apps/api/`)

A new `apps/api/` app was added to the existing HaleHub Django project. It exposes a JWT-authenticated REST API consumed by the iOS app. No database migrations are required — it only reads from existing models.

**Auth**
| Endpoint | Method | Description |
|---|---|---|
| `/api/auth/login/` | POST | Email + password → returns access + refresh JWT tokens |
| `/api/auth/refresh/` | POST | Swap refresh token for new access token |

**Vehicles**
| Endpoint | Method | Description |
|---|---|---|
| `/api/vehicles/` | GET | List all active family vehicles |
| `/api/vehicles/<id>/` | GET | Vehicle detail |
| `/api/vehicles/<id>/events/` | GET | Paginated event history (gas, maintenance, outings) |
| `/api/vehicles/<id>/log/` | POST | Log a new event — triggers auto MPG/GPH calculation |
| `/api/vehicles/<id>/maintenance/` | GET | Maintenance schedules with due/ok status |

**Recipes & Meal Planning**
| Endpoint | Method | Description |
|---|---|---|
| `/api/recipes/` | GET | Recipe list — supports `?search=`, `?sort=`, `?is_favorite=true`, `?category_id=`, dietary flags |
| `/api/recipes/<id>/` | GET | Full recipe with ingredients, instructions, nutrition |
| `/api/recipes/<id>/mark-cooked/` | POST | Increments `times_cooked`, updates `last_cooked` |
| `/api/recipes/categories/` | GET | All family recipe categories with emoji/color |
| `/api/meal-plans/` | GET | List all meal plans |
| `/api/meal-plans/active/` | GET | Active meal plan with entries, sides, and nested recipes |

---

### iOS App (SwiftUI, 16 Swift files)

**Architecture**
- `APIClient` — async/await networking actor, snake_case JSON decoding, ISO8601 date handling
- `AuthManager` — JWT login/logout, tokens persisted in UserDefaults
- `RecipesViewModel` — shared state for recipes, meal plan, categories, filters, sort
- `VehiclesViewModel` — vehicles list state

**Vehicles Tab**
- Vehicle list with mileage, type icon, make/model/year
- Vehicle detail showing maintenance schedule (DUE badges) and recent event history
- Log Event sheet — gas (gallons, price, odometer), maintenance, outing; date picker
- MPG/GPH auto-calculated server-side on save

**Meals Tab**
- Active meal plan view — auto-switches between **day-by-day layout** (when entries have dates) and **meal-type layout** (Breakfast / Lunch / Dinner / Snack)
- Today highlighted with a badge; sides shown indented under each meal
- Check off meals as cooked with strikethrough animation
- Navigate to full recipe detail from any meal entry

**Recipes List**
- Horizontal scrollable filter chips: All / GF / DF / Vegetarian / Vegan + all your custom categories
- Sort menu: Name / Most Cooked / Recently Cooked / Rating
- Favorites-only toggle
- Thumbnail images (AsyncImage) with fallback placeholder
- Star ratings, cook count, diet badges per row

**Recipe Detail**
- Full-width hero image
- Stat pills: Prep / Cook / Total time / Serves / Calories
- Dietary flags displayed as badges
- Nutrition grid (calories, protein, carbs, fat, fiber)
- Dot-bulleted ingredients list
- Numbered instruction steps

**Cook Mode** (full-screen)
- Step-by-step instructions with progress bar
- Animated forward/back navigation
- "All Steps" overview sheet — tap any step to jump to it
- Screen stays awake while cooking (`isIdleTimerDisabled = true`)

---

## What You Need to Do Right Now

### 1. Deploy the API to production

The Django changes need to be on the server before the app can talk to it.

```bash
# On your server (or from your machine if build.sh handles it)
./build.sh
```

No migrations needed. The new `apps/api` app has no models.

### 2. Open the iOS project in Xcode

```bash
open /Users/davidhale87/Coding/HaleHubIOS/HaleHubIOS.xcodeproj
```

### 3. Set your Development Team in Xcode

This is required before you can build or run on a real device.

1. Click `HaleHubIOS` in the left sidebar (the blue project icon)
2. Select the `HaleHubIOS` target
3. Go to **Signing & Capabilities**
4. Under **Team**, select your Apple ID / team
5. Xcode will auto-generate a provisioning profile

> If you don't have an Apple Developer account, sign in at developer.apple.com ($99/year). Required for TestFlight.

### 4. Run in Simulator

- Pick **iPhone 16** or **iPhone 15** from the device dropdown
- Hit the Play button (⌘R)
- Log in with your HaleHub email and password

### 5. Test on your real iPhone

1. Plug in your iPhone via USB
2. Select it from the device dropdown
3. On first run, go to **Settings → General → VPN & Device Management** on the iPhone and trust your developer certificate
4. Hit ⌘R to install

---

## What's Not Built Yet

### iOS — Next Features

| Feature | Notes |
|---|---|
| Push notifications | Would need a notification backend (APNs) — useful for meal plan reminders |
| App icon | Currently using default icon — need to add artwork to Assets.xcassets |
| Launch screen branding | Currently blank white |
| Offline caching | No local persistence yet — requires network connection |
| Multiple meal plans | App shows active plan only; no way to browse past/future plans |
| Recipe creation | View-only; add/edit recipes still done on the website |
| Pantry tracker | Not started — model exists in Django |
| Vacations tab | Not started — full Django app exists |
| Finance tab | Not started — probably not needed on mobile |
| Paychecks tab | Not started |

### Django API — Future Endpoints

| Endpoint | Needed For |
|---|---|
| `POST /api/recipes/<id>/favorite/` | Toggle favorite from app |
| `GET /api/vehicles/<id>/stats/` | Lifetime MPG, cost summaries |
| `GET /api/meal-plans/` detail view | Browse past/future plans in app |
| `POST /api/auth/logout/` | Token blacklisting on logout |

### Distribution

| Step | Status |
|---|---|
| Apple Developer account | Need to confirm you have one (developer.apple.com) |
| TestFlight build upload | Not done — do this via **Product → Archive** in Xcode |
| Family TestFlight invites | Not done — invite via App Store Connect after upload |

---

## File Map

```
HaleHubIOS/
├── project.yml                          # XcodeGen spec — edit this, then run `xcodegen generate`
├── HaleHubIOS.xcodeproj/               # Generated — do not edit manually
└── Sources/HaleHubIOS/
    ├── HaleHubIOSApp.swift              # App entry point, auth gate
    ├── App/
    │   └── MainTabView.swift            # Two-tab shell (Vehicles / Meals)
    ├── Core/
    │   ├── Network/
    │   │   ├── APIClient.swift          # All HTTP calls — change baseURL here
    │   │   └── AuthManager.swift        # JWT login/logout
    │   └── Models/
    │       ├── Vehicle.swift            # Vehicle, Event, MaintenanceSchedule structs
    │       └── Recipe.swift             # Recipe, Ingredient, MealPlan, MealPlanEntry, etc.
    └── Features/
        ├── Auth/
        │   └── LoginView.swift
        ├── Vehicles/
        │   ├── VehiclesViewModel.swift
        │   ├── VehiclesListView.swift
        │   ├── VehicleDetailView.swift
        │   └── LogEventSheet.swift
        └── Recipes/
            ├── RecipesViewModel.swift
            ├── MealPlanView.swift
            ├── RecipesListView.swift
            ├── RecipeDetailView.swift
            └── CookModeView.swift
```

```
halehub/apps/api/
├── apps.py
├── urls.py
├── serializers/
│   ├── vehicles.py
│   └── recipes.py
└── views/
    ├── vehicles.py
    └── recipes.py
```

---

## Quick Reference

**Change the API server URL:**
Edit `Sources/HaleHubIOS/Core/Network/APIClient.swift` line 10 — `private let baseURL = ...`

**Add a new API endpoint:**
1. Add view to `apps/api/views/`
2. Register in `apps/api/urls.py`
3. Add corresponding Swift model in `Core/Models/`
4. Call from view or ViewModel via `APIClient.shared.get(...)`

**Regenerate the Xcode project after adding Swift files:**
```bash
cd /Users/davidhale87/Coding/HaleHubIOS && xcodegen generate
```
