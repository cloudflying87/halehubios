# HaleHub iOS App — Status

**Last Updated:** May 15, 2026
**iOS Project:** `/Users/davidhale87/Coding/HaleHubIOS/`
**Django Project:** `/Users/davidhale87/Coding/halehub/`
**API Base:** `https://flyhomemn.com/api`
**API Source:** `apps/api/` in the halehub repo

---

## What's Been Built

### Django REST API (`apps/api/`) — 22 endpoints, all clean

| Group | Endpoints |
|---|---|
| Auth | `POST /api/auth/login/` · `/auth/refresh/` · `GET /api/auth/me/` |
| Vehicles | `GET /api/vehicles/` · `/<id>/` · `/<id>/events/` · `/<id>/maintenance/` · `POST /<id>/log/` · `GET /maintenance-categories/` |
| Recipes | `GET /api/recipes/` · `/<id>/` · `/categories/` · `POST /<id>/mark-cooked/` |
| Meal Plans | `GET /api/meal-plans/` · `/meal-plans/active/` |
| Shopping | `GET /api/shopping/` · `/<id>/` · `POST /<id>/items/` · `POST /<id>/items/<id>/toggle/` · `DELETE /<id>/items/<id>/` |
| Notifications | `GET /api/notifications/` · `/unread-count/` · `POST /<id>/read/` · `/read-all/` |

---

### iOS App — 30 Swift files, valid `.xcodeproj`

**Architecture**
- `APIClient` — async/await actor, snake_case JSON decoding
- `AuthManager` — JWT login/logout, user profile cached in UserDefaults
- `CacheManager` — file-based JSON cache in Documents/HaleHubCache
- `NetworkMonitor` — NWPathMonitor, publishes `isConnected` + `OfflineBanner` view

**Tab 1 — Vehicles 🚗**
- Vehicle list with type filter chips, thumbnail images
- Vehicle detail: hero image, stats bar (mileage/avg MPG/fuel spend/service spend), event type filter tabs, month-grouped history, maintenance schedules with DUE badges
- Log Event sheet: gas (with live cost preview), service (with category picker), outing (with location field) — all pre-seed the current vehicle

**Tab 2 — Meals 🍽️**
- Active meal plan — auto day-grouped when dates set, meal-type grouped otherwise; today highlighted; sides shown per meal
- Recipe list — filter chips (dietary + categories), sort menu, favorites toggle, thumbnail images
- Recipe detail — hero image, nutrition grid, numbered ingredient list, numbered instruction steps
- Cook Mode — full-screen step-by-step, progress bar, all-steps overview, screen stays awake
- **Offline**: recipes and meal plan cached to disk, loads instantly without network

**Tab 3 — Shopping 🛒**
- Shopping list overview with progress bars (checked / total items)
- List detail: check off items with optimistic UI, add items inline, swipe to delete, "Clear Checked" menu
- **Offline**: cached shopping lists shown with offline banner; check-off and add require network

**Tab 4 — More ···**
- User profile card (name, email, role)
- Notifications with unread badge count — tap to mark read, "Mark all read"
- Offline calculators (all work with no network):
  - 💰 **Loan Calculator** — monthly payment, total interest, visual principal/interest bar
  - 📈 **Compound Interest** — final balance, contribution breakdown, year-by-year bar chart
  - 🕐 **Time Calculator** — add, subtract, difference, convert with HH:MM:SS input

---

## What YOU Need to Do

### 1. Deploy Django changes to production
```bash
./build.sh
```
No migrations needed. The `apps/api/` app has no models.

### 2. Open the iOS project in Xcode
```bash
open /Users/davidhale87/Coding/HaleHubIOS/HaleHubIOS.xcodeproj
```

### 3. Set your Development Team (required to run)
1. Click the blue `HaleHubIOS` project icon in the sidebar
2. Select the `HaleHubIOS` target → **Signing & Capabilities**
3. Under **Team**, select your Apple ID / Apple Developer account
4. Xcode auto-generates the provisioning profile

> **Apple Developer account:** $99/year at developer.apple.com — required for TestFlight

### 4. Run in Simulator
Select an **iPhone 16** simulator and press **⌘R**. Log in with your HaleHub email and password.

### 5. Test on your real iPhone
1. Plug in via USB, select it from the device dropdown
2. Press ⌘R — Xcode installs the app
3. On your iPhone: **Settings → General → VPN & Device Management** → trust your developer certificate

### 6. Distribute to family via TestFlight
1. In Xcode: **Product → Archive** (plug in a real device or select "Any iOS Device")
2. In the Organizer: **Distribute App → TestFlight**
3. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
4. Add family members as internal testers — they get an email invitation

### 7. Add the iOS repo to GitHub (optional)
```bash
cd /Users/davidhale87/Coding/HaleHubIOS
git branch -m master main
git remote add origin git@github.com:cloudflying87/halehub-ios.git
git push -u origin main
```

---

## What's Not Built Yet

### iOS — Next Up

| Feature | Notes |
|---|---|
| Push notifications (APNs) | Requires `UNUserNotificationCenter` + server-side APNs setup — bigger lift |
| Recipe creation from mobile | Add/edit recipes still done on website |
| Multiple meal plans | App shows active plan only; no browse/switch |
| Pantry tracker | Model exists in Django, no API or iOS view yet |
| Vacations tab | Full Django app exists, not started on iOS |
| Finance calculators | Car purchase, affordability, early payoff — require auth API |
| Offline write queue | Shopping item toggles fail silently when offline; no retry queue |

### Django API — Future Endpoints

| Endpoint | Needed For |
|---|---|
| `POST /api/recipes/<id>/favorite/` | Toggle favorite from iOS |
| `GET /api/vehicles/<id>/stats/` | Detailed stats (currently computed client-side) |
| `GET /api/pantry/` | Pantry inventory tab |
| `POST /api/auth/logout/` | Token blacklisting on logout |

---

## File Map

```
HaleHubIOS/
├── project.yml                              # XcodeGen spec — edit, then run `xcodegen generate`
├── STATUS.md                                # This file
└── Sources/HaleHubIOS/
    ├── HaleHubIOSApp.swift                  # App entry point — injects auth + network
    ├── App/
    │   └── MainTabView.swift                # 4-tab shell
    ├── Core/
    │   ├── Network/
    │   │   ├── APIClient.swift              # All HTTP — change baseURL here
    │   │   ├── AuthManager.swift            # JWT + user profile caching
    │   │   └── NetworkMonitor.swift         # NWPathMonitor + OfflineBanner
    │   ├── Storage/
    │   │   └── CacheManager.swift           # File-based JSON cache
    │   └── Models/
    │       ├── Vehicle.swift
    │       ├── Recipe.swift                 # Recipe, MealPlan, MealPlanEntry, MealPlanSide
    │       ├── ShoppingList.swift
    │       └── HaleNotification.swift
    └── Features/
        ├── Auth/LoginView.swift
        ├── Vehicles/
        │   ├── VehiclesViewModel.swift
        │   ├── VehiclesListView.swift
        │   ├── VehicleDetailView.swift
        │   └── LogEventSheet.swift
        ├── Recipes/
        │   ├── RecipesViewModel.swift       # Offline caching built in
        │   ├── MealPlanView.swift
        │   ├── RecipesListView.swift
        │   ├── RecipeDetailView.swift
        │   └── CookModeView.swift
        ├── Shopping/
        │   ├── ShoppingViewModel.swift      # Offline caching built in
        │   ├── ShoppingListsView.swift
        │   └── ShoppingListDetailView.swift
        ├── Notifications/
        │   ├── NotificationsViewModel.swift
        │   └── NotificationsView.swift
        └── Account/
            ├── AccountView.swift            # Profile + notifications badge + calculators
            └── Calculators/
                ├── LoanCalculatorView.swift
                ├── CompoundInterestView.swift
                └── TimeCalculatorView.swift
```

---

## Quick Reference

**Change the API server URL:**
`Core/Network/APIClient.swift` line 10

**Add new Swift files:**
1. Write the `.swift` file in the right `Features/` subdirectory
2. Run `cd /Users/davidhale87/Coding/HaleHubIOS && xcodegen generate`

**Add a new API endpoint:**
1. Add view to `apps/api/views/`
2. Register in `apps/api/urls.py`
3. Add Swift model in `Core/Models/`
4. Call via `APIClient.shared.get(...)` or `.post(...)`
5. Run `./build.sh` to deploy

**Clear the iOS cache** (useful during development):
Call `await CacheManager.shared.clearAll()` from the app — or delete and reinstall the app.
