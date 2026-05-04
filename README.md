# Rokid Outlook HUD


> **🔵 Connectivity Update — May 2025**
> The glasses connection has been migrated from **raw TCP sockets** to
> **Bluetooth via the Rokid AI glasses SDK** (`pod 'RokidSDK' ~> 1.10.2`).
> No Wi-Fi port forwarding is needed. See **SDK Setup** below.

iOS app that bridges **Microsoft Outlook** (email + calendar + contacts) with **Rokid AR glasses** — see your inbox, events, and contacts on your heads-up display in real time.

```
👓 Glasses query / 📱 iPhone monitor
         ↓
  iPhone (RokidOutlook)
         ↓  Microsoft Graph API v1.0
  graph.microsoft.com
         ↓  email · calendar · contacts
  iPhone ──Bluetooth/RokidSDK──▶ Rokid Glasses (live HUD)
```

## What appears on the glasses

```
📧 5 unread
🟡 Team Standup in 8m  9:00 AM – 9:30 AM
✉️ Boss: Q3 Report due Friday — please review…
```

Instant alerts fire on your glasses for:
- **New emails** arriving in your inbox
- **High-importance** emails
- **Flagged** emails
- **Calendar events** starting soon (configurable minutes)

## Glasses → Phone commands (TCP :8099)

| Command | Result |
|---------|--------|
| `QUERY: email` | Show recent inbox emails |
| `QUERY: unread` | Show unread emails only |
| `QUERY: flagged` | Show flagged emails |
| `QUERY: important` | Show high-importance emails |
| `QUERY: calendar` | Show today's events |
| `QUERY: next` | Show the next upcoming event |
| `QUERY: contact Sarah` | Look up Sarah in contacts |
| `QUERY: find Jones` | Search contacts by name |
| `QUERY: summary` | Push current HUD summary |
| `QUERY: refresh` | Reload from Microsoft Graph |

Plain text also triggers the default summary.

## Phone → Glasses packet types

```json
{"type":"outlook",     "text":"📧 5 unread\n✉️ Boss: Q3 Report due Friday"}
{"type":"email_alert", "text":"❗[IMPORTANT] ✉️ Boss: Q3 Report due Friday"}
{"type":"event_alert", "text":"📅 Starting in 5 min: Team Standup\n9:00 AM – 9:30 AM"}
{"type":"emails",      "text":"✉️ Boss: Q3 Report…\n● ✉️ Sarah: Quick question about…"}
{"type":"calendar",    "text":"🟢 Standup NOW 9:00–9:30\n📅 Review @ 2:00–3:00 PM"}
{"type":"contact",     "text":"Sarah Jones\n✉️ sarah@company.com\n💼 Product Manager"}
{"type":"status",      "text":"🔍 Searching 'Sarah'…"}
{"type":"error",       "text":"❌ Session expired"}
```

## SDK Setup

The glasses now connect over **Bluetooth via the Rokid AI glasses SDK** — no Wi-Fi port or TCP server needed.

The only thing left for each app is filling in the three credential constants (`kAppKey`, `kAppSecret`, `kAccessKey`) from [account.rokid.com/#/setting/prove](https://account.rokid.com/#/setting/prove), then running `pod install`.

1. **Get credentials** at <https://account.rokid.com/#/setting/prove> and paste them into the glasses Swift file:
   ```swift
   private let kAppKey    = "YOUR_APP_KEY"
   private let kAppSecret = "YOUR_APP_SECRET"
   private let kAccessKey = "YOUR_ACCESS_KEY"
   ```

2. **Install CocoaPods dependencies** from the repo root:
   ```bash
   pod install
   open *.xcworkspace   # always open the .xcworkspace, not .xcodeproj
   ```

3. *(Glasses now connect automatically over Bluetooth — no TCP port needed.)*

## Setup

### Step 1 — Register an Azure App (free, one-time)

1. Go to [portal.azure.com](https://portal.azure.com) → **Azure Active Directory** → **App registrations** → **New registration**
2. Name: anything (e.g. "Rokid Outlook HUD")
3. Supported account types: *Accounts in any organizational directory and personal Microsoft accounts*
4. Redirect URI → Platform: **Mobile and desktop applications** → URI: `rokidoutlook://auth`
5. Click **Register** and copy the **Application (client) ID**

### Step 2 — Grant API permissions

**API permissions** → **Add a permission** → **Microsoft Graph** → **Delegated**:
- `User.Read`
- `Mail.Read`
- `Mail.ReadWrite` *(for mark-as-read)*
- `Calendars.Read`
- `Contacts.Read`
- `offline_access`

Grant admin consent if you're an admin (or ask IT).

### Step 3 — Build and run

1. Open `RokidOutlook.xcodeproj` in Xcode 15+
2. Set your team in Signing & Capabilities
3. Build and run on iPhone (iOS 17+)
4. In **Settings**: paste Client ID, set Tenant ID (`common` for personal accounts)
5. Tap **Sign in with Microsoft** on the Inbox tab
6. *(Glasses now connect automatically over Bluetooth — no TCP port needed.)*

## Microsoft Graph API

| Feature | Graph endpoint |
|---------|---------------|
| My profile | `GET /me` |
| Inbox | `GET /me/mailFolders/inbox/messages` |
| Unread count | `GET /me/mailFolders/inbox?$select=unreadItemCount` |
| Mail folders | `GET /me/mailFolders` |
| Today's events | `GET /me/calendarView?startDateTime=...&endDateTime=...` |
| Search contacts | `GET /me/contacts?$filter=contains(displayName,'...')` |
| Mark as read | `PATCH /me/messages/{id}` `{"isRead":true}` |

## Display formats

| Format | Glasses output |
|--------|----------------|
| **Compact** | Unread count + next event + latest email |
| **Detailed** | Full email preview + sender + event details |
| **Minimal** | Unread count and next event only |

## Requirements

- iOS 17.0+
- Xcode 15+
- Microsoft account (personal or work/school with Exchange/Outlook)
- Azure App Registration (free — see Setup above)
- Rokid AR glasses on the same Wi-Fi (optional — works standalone as an Outlook dashboard)
