# Budget AI — Google Play Console answers

Copy each value into the matching Play Console field.
Package name: `com.budgetai.android` · Support email: `budgetaitracker@gmail.com`
Website: https://budgetai-app.pages.dev

---

## 1. Store listing  (Grow → Store presence → Main store listing)

**App name** (30 max)
```
Budget AI: Expense Tracker
```

**Short description** (80 max)
```
Log expenses by voice, receipt or chat. AI sorts and explains your spending.
```

**Full description** (4000 max)
```
Budget AI is the expense tracker that logs itself. Tell it what you spent, snap a receipt, or type a quick note, and Budget AI records every entry, puts it in the right category, and shows you where your money goes.

JUST SAY IT
Hold the mic and speak naturally: "Lunch 14.50 and a cab home for 22." Budget AI transcribes it, splits it into separate entries, and logs each one.

SNAP ANY RECEIPT
Take a photo or pick one from your gallery. Budget AI reads the receipt, logs the total once, and can list every item when you ask.

SORTED FOR YOU
Every expense lands in the right category automatically: groceries, dining, bills, transport and more. No manual tagging.

ASK ANYTHING
"How much did I spend on dining this month?" "What were my five biggest expenses?" Get clear answers and tables in seconds.

EVERY DOLLAR, TRACKED
See income in green and spending in red, grouped by day. Search everything, switch months in one tap, and add or edit entries by hand whenever you like.

SEE WHERE IT GOES
Daily charts, top categories, highlights like your biggest day, and a one-tap AI summary of every month in plain words.

HOME SCREEN WIDGETS
Eight widgets keep your budget one glance away: monthly expenses and income, today's spending, recent expenses, top categories, and this month versus last. Switch months right on the widget.

MAKE IT YOURS
Light and dark themes, any currency (including your own custom symbol), and message bubble styles.

YOUR DATA, YOUR CALL
Your entries are saved on your phone. Turn on Cloud Sync to keep them in your account and on every device, or save a backup file and restore it whenever you like.

BUDGET AI PREMIUM
Start free. Upgrade to Lite, Plus or Pro for more AI messages, faster replies and deeper analysis. Cancel anytime in Google Play.

PRIVATE BY DESIGN
• Entries stay on your phone unless you turn on Cloud Sync
• No ads and no third-party analytics or tracking
• Your data is never sold
• Chat history stays on your phone
• AI features run only after you agree, and you can report any AI reply
• Delete your entries, chats, or your whole account at any time

Budget AI uses OpenAI to understand your messages, receipts, and voice notes. It does not connect to your bank, and nothing is logged without you.

Budget AI is for personal budgeting and is not financial advice.

Privacy Policy: https://budgetai-app.pages.dev/privacy
Terms: https://budgetai-app.pages.dev/terms
```

**Graphics** (files in this folder)
- App icon: `app-icon-512.png` (512×512)
- Feature graphic: `feature-graphic-1024x500.png`
- Phone screenshots: `screenshots/phone/01.png` … `08.png` (1080×1920, upload in order)
- Subscription icons: `subscription-icons/` (Lite, Plus, Pro, 1024×1024)

**Category:** Finance · **Tags:** Budgeting, Expense tracker, Personal finance
**Contact email:** budgetaitracker@gmail.com · **Website:** https://budgetai-app.pages.dev

---

## 2. App content  (Policy → App content)

### Privacy policy
```
https://budgetai-app.pages.dev/privacy
```

### Ads
**Does your app contain ads?** → **No**

### App access
**All or some functionality is restricted** → add instructions:
```
Sign in on the welcome screen with the demo account below. It already contains sample expenses and income in USD.
Email: <DEMO ACCOUNT EMAIL>
Password: <DEMO ACCOUNT PASSWORD>
No other codes or steps are required.
```
(Use the demo account you made for the screenshots. Make sure it can sign in without a new email code.)

### Content rating  (IARC questionnaire)
- Category: **Utility, Productivity, Communication or Other**
- Violence, sexual content, profanity, drugs, gambling, crude humor: **No** to all
- Users can interact or exchange content with other users: **No**
- Shares user's location with other users: **No**
- Allows users to purchase digital goods: **Yes** (Budget AI Premium subscriptions through Google Play)
- Contains AI-generated content: **Yes** — text replies from an AI assistant, with an in-app Report option
Expected result: **Everyone / PEGI 3**

### Target audience and content
- Target age groups: **18 and over** (you may also tick 16–17)
- Appeals to children: **No**

### News app → **No** · Government app → **No** · Health app → **No**

### Financial features
Choose the option for **budgeting / personal finance management (no money movement)** if listed; otherwise **"My app doesn't provide any financial features"** from the list. Budget AI offers no loans, banking, payments, trading, crypto, or credit.

### Account deletion
- Can users create an account? **Yes**
- Delete account URL:
```
https://budgetai-app.pages.dev/delete-account
```
- In-app: **Budget Hub → Danger Zone → Delete Account**
- Data deleted with the account: all of it (account, finance entries synced with Cloud Sync, synced settings, AI usage, reports). Nothing kept except where the law requires. Entries kept only on the phone are removed from the device.

---

## 3. Data safety  (Policy → App content → Data safety)

**Overview questions**
| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all user data encrypted in transit? | **Yes** |
| Do you provide a way for users to request that their data is deleted? | **Yes** (in app and at the deletion URL) |

> "Shared" means given to a third party for its own use. OpenAI and Supabase process data **on our behalf** (service providers), so that counts as **collected**, not shared. Answer **Shared: No** everywhere.

**Data types to tick**

| Category → Type | Collected | Shared | Processed ephemerally | Required? | Purposes |
|---|---|---|---|---|---|
| Personal info → **Email address** | Yes | No | No | Required | Account management, App functionality |
| Personal info → **Name** | Yes | No | No | Optional | App functionality (shown in the app) |
| Financial info → **Other financial info** (expense and income entries; stored on our servers only when the user turns on Cloud Sync) | Yes | No | No | Optional | App functionality |
| Financial info → **Purchase history** (Premium plan and renewal status) | Yes | No | No | Optional | App functionality |
| Messages → **Other in-app messages** (chat messages sent to the AI) | Yes | No | **Yes** | Optional | App functionality |
| Photos and videos → **Photos** (receipts attached to chat) | Yes | No | **Yes** | Optional | App functionality |
| Audio → **Voice or sound recordings** (hold-to-talk) | Yes | No | **Yes** | Optional | App functionality |
| App activity → **Other user-generated content** (AI reply reports) | Yes | No | No | Optional | App functionality, Fraud prevention, security, and compliance |
| App activity → **App interactions** (monthly AI request counts for limits) | Yes | No | No | Required | App functionality |

**Do not tick:** Location, Contacts, Calendar, Web browsing, Device or other IDs, Health, App info and performance (no crash reporting), Advertising.

---

## 4. Foreground service declaration  (App content → Foreground service permissions)

**Permission type:** `FOREGROUND_SERVICE_DATA_SYNC`

**Task description**
```
When the user sends a message to the Budget AI assistant, the app streams the AI reply from our server and saves any expense entries it logs. If the user leaves the app while that reply is still arriving, a dataSync foreground service with a visible notification keeps the network transfer alive until the reply and its entries are fully downloaded and stored, then stops immediately. It only runs if the user turns on "Background Service" in Budget Hub.
```

**User impact if deferred or interrupted**
```
The AI reply would be cut off mid-stream and expenses the user just asked to log could be lost or saved incompletely, so the user would have to send the message again.
```

**Is the task user-initiated?** Yes — it starts only while a reply the user requested is in progress, and only when the user enabled Background Service.

**Video** (upload to YouTube as Unlisted, paste the link). Record ~30 s on the Android phone:
1. Open Budget AI → Budget Hub → turn **Background Service** on.
2. Go back to chat, send: "Lunch 14.50 and coffee 4.75".
3. While the reply is still streaming, press **Home**.
4. Pull down the notification shade → show the **"Budget AI chat running"** notification.
5. Wait for the reply to finish → notification disappears → reopen the app → the reply and the two entries are complete.

---

## 5. Before you submit
- [ ] `make aab` → upload `~/Documents/Budget AI/Budget AI 1.0.0+5.aab` (or the latest build number)
- [ ] Release notes (e.g. "First release of Budget AI.")
- [ ] Demo account can sign in (step 2, App access)
- [ ] All App content sections show a green check
