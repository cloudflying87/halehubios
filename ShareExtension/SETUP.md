# HaleHub Share Extension — Xcode setup

Lets you **Share → HaleHub** from Safari to import a recipe straight into HaleHub,
no review step. The Swift/plist/entitlements here are ready; these steps wire them
into the Xcode project (the parts that can't be done by editing files alone).

## 1. Create the extension target
- Xcode → **File ▸ New ▸ Target… ▸ Share Extension**.
- Product Name: **ShareExtension**. Bundle id becomes `com.halefamily.halehubios.ShareExtension`.
- When prompted "Activate scheme?", click **Cancel** (keep the app scheme).
- Delete the `ShareViewController.swift`, `Info.plist`, and `MainInterface.storyboard`
  Xcode auto-generated in the new target folder.

## 2. Use these files instead
- Add `ShareExtension/ShareViewController.swift`, `Info.plist`, and
  `ShareExtension.entitlements` (this folder) to the **ShareExtension** target
  (File ▸ Add Files… → check only the ShareExtension target).
- Target ▸ Build Settings → set **Info.plist File** to this `Info.plist`, and
  **Code Signing Entitlements** to `ShareExtension.entitlements`.
- There is no storyboard — `Info.plist` uses `NSExtensionPrincipalClass`.

## 3. Turn on the App Group (both targets)
This is how the extension reads your login. Do it for **both** the main app
target **and** the ShareExtension target:
- Target ▸ **Signing & Capabilities ▸ + Capability ▸ App Groups**.
- Add group **`group.com.halefamily.halehubios`** (exact string) and tick it.
- This registers the group on your Apple Developer account automatically.

## 4. Build & run
- Select the **app** scheme, run on your iPhone.
- Open the app once and sign in (so the token is shared).
- In Safari, open a recipe → **Share ▸ HaleHub** → it imports and shows
  "Added … ✅".

## Notes
- The group id, token key (`halehub_access_token`), and API base in
  `ShareViewController.swift` must stay in sync with the app (`AuthManager`).
- If it says "sign in first", open the app and log in — the extension uses the
  app's shared token.
