# MessMate — Replit Master Build Specification

## PURPOSE

You are the implementation agent for **MessMate**, a production-oriented shared-mess management application.

Your job is to take the existing repository and turn it into a complete, polished, working application — not merely a mockup, prototype, documentation exercise, or visual redesign.

**Repository:** `miz-app-builder/messmate-management`

**Existing master blueprint:** `docs/MESSMATE_FULL_PROJECT_BLUEPRINT.md`

Read the master blueprint first, then read this file. This file is the implementation contract for Replit.

---

# 1. NON-NEGOTIABLE IMPLEMENTATION RULES

1. **Inspect the existing code before changing it.** Do not blindly replace `App.jsx`, `AppShell.jsx`, routing, authentication, or Supabase logic.
2. Preserve working functionality unless the existing implementation conflicts with this specification or a security/integrity rule.
3. Do not build fake/demo data as a substitute for real functionality.
4. Use the existing Supabase backend and migrations wherever possible.
5. Do not introduce a third-party backend, database, authentication provider, or application host.
6. Frontend: React + Vite.
7. Backend: Supabase PostgreSQL + Supabase Auth + RLS + protected RPCs/functions/triggers as required.
8. Never put a Supabase service-role key in browser/client code.
9. Never trust role IDs, member IDs, amounts, totals, approval state, or accounting values supplied by the browser.
10. Critical mutations must be authorized and validated server-side.
11. Do not bypass RLS merely to make the UI work.
12. Do not silently weaken security policies to solve frontend errors.
13. Financial records must be traceable and corrected by reversal/adjustment, not destructive overwrites.
14. Approved bazar records are immutable.
15. Closed monthly settlements are immutable.
16. A `PENDING` member must have **ZERO accounting eligibility**.
17. Only an eligible `ACTIVE` member participates in normal accounting.
18. Meal cutoff enforcement must exist server-side.
19. Manager overrides after cutoff must be audited.
20. Finish with a production build check (`npm run build`) and fix all build/runtime errors you can reproduce.
21. Do not stop after creating components. Wire every important screen to real data and real actions.
22. Do not leave dead buttons, fake navigation, placeholder CRUD, or `TODO` stubs for core features.

---

# 2. FIRST TASK — AUDIT THE CURRENT REPOSITORY

Before implementing new code:

### Inspect
- `package.json`
- `src/main.jsx`
- `src/App.jsx`
- `src/AppShell.jsx`
- `src/lib/*`
- all current panels/components
- all CSS files
- `supabase/migrations/*`
- `.github/workflows/*`
- `README.md`
- existing environment-variable usage

### Determine
- Which features already work.
- Which screens already exist.
- Which Supabase RPCs exist.
- Which tables/views/functions/triggers/policies exist.
- Which code is duplicated.
- Which code is dead.
- Which UI is incomplete.
- Which current changes are risky.
- Whether the application currently builds successfully.

Create an internal implementation checklist from the audit and then execute it.

**Important:** The repository has previously had dashboard/UI work and Supabase security hardening. Preserve those improvements where valid, but verify them rather than assuming they are correct.

---

# 3. PRODUCT DEFINITION

MessMate is a complete digital platform for people living in a shared mess/flat/hostel arrangement.

It manages:

```text
Authentication
    ↓
Mess creation / joining
    ↓
Membership approval
    ↓
Meal management
    ↓
Bazar
    ↓
Expenses
    ↓
Deposits / payments
    ↓
Accounting
    ↓
Ledger
    ↓
Monthly settlement
    ↓
Reports
    ↓
Notifications + audit
```

The product must feel like a serious accounting/operations application, while remaining extremely easy for an ordinary mess member to use every day.

---

# 4. USER ROLES

## 4.1 Manager

Full administrative control over the mess:
- Mess settings.
- Join requests.
- Member activation/deactivation.
- Roles.
- Specific permissions.
- Meal rules.
- Meal cutoffs.
- Manager meal overrides.
- Bazar approval.
- Expenses.
- Deposits.
- Ledger.
- Settlement.
- Reports.
- Notifications.
- Audit history.

## 4.2 Bazar Manager

Only permitted bazar functions:
- Create bazar.
- Add item lines.
- Calculate/submit bazar.
- View bazar history.
- Approve/reject only if explicitly granted the required permission.

## 4.3 Member

- View own meals.
- Change own meals before cutoff.
- Schedule future meals.
- View own balance.
- View own ledger.
- View relevant bazar/expense information.
- View settlement.
- Receive notifications.

Do not expose manager-only controls to ordinary members.

---

# 5. MEMBERSHIP STATE MACHINE

Use clear states:

```text
JOIN REQUEST
    |
    v
 PENDING
   /   \
REJECT  APPROVE
          |
          v
        ACTIVE
        /    \
   SUSPENDED  LEFT
```

Required dates:
- `joined_at`
- `activated_at`
- `left_at`

### Hard accounting rule

```text
PENDING  = no accounting
ACTIVE   = accounting eligible
SUSPENDED/LEFT = no normal future accounting
```

A pending user may exist in the system and may receive join-request status notifications, but must not affect meal totals, meal rate, expense/bazar allocation, balance, or settlement.

---

# 6. AUTHENTICATION

Implement a reliable Supabase Auth flow.

Required:
- Sign up.
- Sign in.
- Sign out.
- Session restoration after refresh.
- Auth state listener.
- Password reset flow.
- Email confirmation compatibility.
- Clear error messages.
- Loading/disabled states.

Expected errors should be mapped to understandable messages:
- Invalid credentials.
- Email already registered.
- Email not confirmed.
- Weak password.
- Provider disabled.
- Rate limit.
- Network/server error.

Do not replace useful Supabase errors with one generic message when a meaningful error code/message is available.

After authentication, determine whether the user:

```text
has no mess
    -> Create Mess / Join Mess

has pending membership
    -> Pending screen

has active membership
    -> Dashboard
```

---

# 7. MESS CREATION

Create New Mess screen must support:
- Mess name.
- Mess code generation/selection according to existing schema.
- Manager assignment.
- Start date.
- Default meal rate/settings if supported by current schema.
- Default meal rules.

After successful creation:
- User becomes manager.
- Membership becomes active.
- Dashboard loads.

Show the mess code prominently and provide a QR/join-code UX when supported by the existing stack.

---

# 8. JOIN EXISTING MESS

Screen:

```text
Mess Code
[____________]

[ Request to Join ]
```

Also support QR entry where practical.

On request:
- Validate mess code server-side.
- Prevent duplicate active/pending membership.
- Create `PENDING` request.
- Notify manager.
- Show pending status to applicant.

Manager screen:

```text
Pending Requests
--------------------------------
Name / Email | Date | Action
             |      | Approve / Reject
```

Approval must happen through protected server-side logic.

---

# 9. DASHBOARD — PREMIUM UI REQUIREMENT

The dashboard must be redesigned into a clean, professional, compact workspace.

### Current UX problems to eliminate
- Full-width stretched cards on large screens.
- Excessive empty vertical space.
- Weak visual hierarchy.
- Floating black pill navigation/buttons covering content.
- Important tools separated awkwardly from the main workspace.
- Cards that contain very little information but occupy huge areas.

### Desktop

Use a centered content area around **1180–1240px maximum width**.

Recommended structure:

```text
┌──────────────────────────────────────────────────────────┐
│ MessMate logo     Mess / Role       Notification Avatar │
├──────────────────────────────────────────────────────────┤
│                                                          │
│ Welcome back, Name                                       │
│ Mess name • Active/Pending status                        │
│                                                          │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐             │
│ │ Meals  │ │Balance │ │ Bazar  │ │ Status │             │
│ └────────┘ └────────┘ └────────┘ └────────┘             │
│                                                          │
│ Today's Meals                                            │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ Breakfast  │ Lunch │ Dinner │ Total │ Lock status   │ │
│ └──────────────────────────────────────────────────────┘ │
│                                                          │
│ Quick Actions                                            │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐             │
│ │ Meals  │ │ Bazar  │ │Finance │ │Members │             │
│ └────────┘ └────────┘ └────────┘ └────────┘             │
│                                                          │
│ Recent Activity / Pending Actions                        │
└──────────────────────────────────────────────────────────┘
```

### Mobile

- Compact header.
- No horizontal scrolling.
- Primary actions reachable with one/two taps.
- Cards become compact.
- Bottom navigation for major sections.
- Tables become cards/lists.
- Forms become stacked.

### Visual style

Use:
- Consistent spacing scale.
- Clear typography hierarchy.
- Subtle borders/shadows.
- Consistent iconography using existing `lucide-react` dependency.
- Professional neutral palette.
- Strong accessible contrast.
- Clear status badges.
- Consistent button hierarchy.
- Smooth but restrained interactions.

Do not overuse gradients, glassmorphism, giant shadows, or decorative animation.

---

# 10. PRIMARY NAVIGATION

Desktop:

```text
Dashboard
Meals
Members
Bazar
Finance
Ledger
Settlement
Reports
Notifications
Settings
```

Mobile:
- Dashboard.
- Meals.
- Bazar.
- Finance/Balance.
- More/Settings.

Role-specific modules must be hidden when the user has no permission, while database authorization remains mandatory.

Never use floating navigation pills that overlap the page content.

---

# 11. MEAL MANAGEMENT

Meal types:
- Breakfast.
- Lunch.
- Dinner.

Values:

```text
ON  = 1
OFF = 0
```

## Member view

Provide a calendar/date-oriented interface showing:

```text
Date       Breakfast  Lunch  Dinner  Total
18 Sep     ON         ON     OFF     2
19 Sep     ON         OFF    ON      2
20 Sep     ON         ON     ON      3
```

Use clear ON/OFF controls and lock indicators.

## Scheduling

Support:
- One date.
- Date range.
- Selected meal types.
- ON/OFF choice.
- Future meals.

## Cutoff

Show:
- Cutoff time.
- Remaining time when useful.
- Locked state after cutoff.

Before cutoff:

```text
Member can edit own meal.
```

After cutoff:

```text
Member cannot edit.
Manager may override through protected workflow.
```

Unconfirmed meals after cutoff must follow the configured default rule.

## Manager override

Manager can override locked meal state only through the authorized server path.

Record an audit event with:
- actor
- member
- date
- meal type
- old value
- new value
- timestamp
- reason if required

## Performance

Do not request unnecessary duplicate rows. Generate/ensure future entries within the safe configured horizon and avoid unbounded generation.

---

# 12. MEAL RULES

Support:
- Global default.
- Per-meal override.
- Breakfast rule.
- Lunch rule.
- Dinner rule.
- Effective date if supported.
- Cutoff configuration.

UI must explain the difference between:
- default meal behavior
- member confirmation
- cutoff
- manager override

Do not make a user guess why a meal is locked or ON.

---

# 13. BAZAR MANAGEMENT

Bazar entry creation must be practical for mobile use.

Fields:
- Date.
- Buyer/actor where applicable.
- Note.
- Items.

Each item:

```text
Item
Quantity
Unit
Unit Price
Line Total
```

Example:

```text
Rice    10 kg    70    700
Potato   5 kg    40    200
Oil      2 L    180    360
--------------------------
Total                 1260
```

Line totals and grand total must be calculated/validated server-side.

### States

```text
DRAFT -> PENDING -> APPROVED
                  \-> REJECTED
```

If approval is not required by the current mess setting, follow the configured workflow without bypassing authorization.

### Immutability

Once approved:
- Do not allow ordinary edit.
- Do not allow ordinary delete.
- Do not silently modify item totals.

If a correction is required, use an explicit correction/reversal process and preserve history.

---

# 14. EXPENSES

Categories:
- Rent.
- Gas.
- Electricity.
- Internet.
- Water.
- Maid.
- Cleaning.
- Other.

Expense form:

```text
Category
Amount
Date
Description
[Save]
```

Use currency formatting consistently.

Protect all writes server-side.

---

# 15. DEPOSITS / PAYMENTS

Deposit form:

```text
Member
Amount
Date
Payment method
Reference/note
[Post Deposit]
```

On successful posting:

```text
Deposit -> Ledger Credit
```

On void:

```text
Void Deposit -> Ledger Reversal
```

Never silently delete a posted financial record.

The UI must clearly distinguish:
- Pending.
- Posted.
- Voided.
- Reversed.

---

# 16. ACCOUNTING ENGINE

Authoritative calculation:

```text
Member Cost
= Meal Cost
+ Bazar/Expense Share
+ Other Charges

Balance
= Total Credits/Deposits - Total Cost
```

Meal rate:

```text
Meal Rate = Total Food Cost / Total Meals
```

All financial calculations that affect balances or settlement must use authoritative database values.

Do not trust a browser-calculated amount.

If the frontend displays a preview, label it as a preview until the server calculation is committed.

---

# 17. LEDGER

The ledger must provide a chronological, understandable financial history.

Columns on desktop:
- Date.
- Type.
- Description.
- Debit/Credit.
- Amount.
- Running balance.

Mobile card:

```text
18 Sep · Deposit
+ ৳5,000
Balance ৳5,000
```

Examples:
- Deposit.
- Meal cost.
- Bazar allocation.
- Expense allocation.
- Adjustment.
- Reversal.

Financial corrections must create traceable adjustment/reversal entries.

---

# 18. MEMBER BALANCE

Dashboard should show:

```text
My Balance
৳ 2,350
```

Use clear semantics:
- Credit/advance.
- Due.

Include a drill-down to ledger/settlement.

Do not show a balance that includes pending/non-active members incorrectly.

---

# 19. MONTHLY SETTLEMENT

Lifecycle:

```text
OPEN
  ↓
CALCULATED
  ↓
REVIEW
  ↓
CLOSED
```

Manager workflow:
1. Select month.
2. Calculate/recalculate while open.
3. Review member totals.
4. Resolve issues.
5. Close settlement.

Member workflow:
- View current month.
- View historical months.
- See final balance.
- See calculation breakdown.

Closed settlement:
- Read-only.
- No normal edit/delete.
- Corrections require explicit adjustment/reversal.

---

# 20. REPORTS

Implement useful reports, not placeholder pages.

## Daily
- Meal totals.
- Breakfast/lunch/dinner totals.
- Bazar total.
- Expense total.

## Monthly
- Total food cost.
- Total meals.
- Meal rate.
- Expenses.
- Deposits.
- Member balances.
- Settlement state.

## Member
- Meal count.
- Meal cost.
- Expense/bazar allocation.
- Deposits.
- Balance.

Use filters:
- Date/month.
- Member.
- Category where appropriate.

If export is already supported, keep it working. If not, structure the report components so CSV/Excel/PDF export can be added without rewriting the accounting engine.

---

# 21. NOTIFICATIONS

Notification center must support:
- Unread count.
- Mark read.
- Mark all read where authorized.
- Timestamp.
- Clear title/body.
- Source/context where useful.

Notification types:
- Join request.
- Join approved/rejected.
- Meal reminder.
- Meal cutoff.
- Bazar pending.
- Bazar approved/rejected.
- Deposit/payment.
- Settlement ready.
- Settlement closed.

Do not create duplicate notifications unnecessarily.

---

# 22. MEMBER MANAGEMENT

Manager screen:

```text
Members
-------------------------------------------------
Name | Role | Status | Joined | Actions
```

Actions:
- View member.
- Activate/deactivate according to allowed state.
- Assign role where authorized.
- Grant specific permissions.
- View accounting information.

Permission screen:

```text
Member: Rahim

Bazar Manager       [ON]
Bazar Approver      [OFF]
Other permission    [OFF]

[Save Permissions]
```

Permission changes must go through protected server-side logic and be auditable.

---

# 23. SETTINGS

Mess settings should be organized into sections:

### General
- Mess name.
- Mess code.
- Basic configuration.

### Meals
- Breakfast default.
- Lunch default.
- Dinner default.
- Cutoff times.
- Unconfirmed behavior.

### Bazar
- Approval required.
- Bazar permissions.

### Finance
- Currency display.
- Accounting/settlement configuration supported by current schema.

Use clear save states and confirmation feedback.

---

# 24. DATABASE / SUPABASE REQUIREMENTS

Use existing migrations and schema first.

Expected domain entities include:

```text
messes
mess_members
join_requests
member_permissions

meal_entries
meal_rules
meal_cutoffs

bazar_entries
bazar_items

expenses
deposits
ledger_entries

monthly_settlements
settlement_items

notifications
audit_logs
```

Before creating a new table/function:
1. Search existing migrations.
2. Confirm whether equivalent functionality already exists.
3. Reuse compatible existing RPCs.
4. Add a new migration only when genuinely necessary.

Never edit an old migration that may already have been applied. Add a new forward migration.

---

# 25. RLS / SECURITY REQUIREMENTS

Every mess-scoped resource must be isolated by mess membership and appropriate authorization.

Security checks must consider:
- authenticated user.
- mess membership.
- membership status.
- role.
- explicit permission.
- object ownership.
- record state.

Examples:

```text
Mess A member cannot read Mess B data.
Mess A member cannot mutate Mess B data.
Member cannot approve their own restricted financial action unless explicitly authorized by policy.
Non-manager cannot change manager-only settings.
Non-bazar user cannot create bazar through a direct API call.
Member cannot modify another member's meals.
Member cannot bypass meal cutoff by manipulating request payload.
```

UI hiding is not authorization.

---

# 26. PROTECTED RPC DESIGN

For critical mutations, prefer protected database functions/RPCs already present in the repository.

Examples of operations that require strong server-side validation:
- Create mess.
- Approve join request.
- Set member permissions.
- Save locked/manager-overridden meal.
- Create/approve bazar.
- Post/void deposit.
- Create financial adjustment.
- Calculate/close settlement.

RPCs must derive sensitive identity/authorization from the authenticated session whenever possible.

Never accept a browser-supplied `role='manager'` as proof of authority.

---

# 27. ACCOUNTING INTEGRITY

Enforce all of the following:

```text
PENDING member -> zero accounting
ACTIVE member  -> eligible accounting
Approved bazar -> immutable
Closed settlement -> immutable
Deposit posted -> ledger credit
Deposit voided -> reversal
Financial correction -> adjustment/reversal
Meal cutoff -> server enforced
Manager override -> audit record
```

Check for duplicate ledger entries and duplicate triggers before adding new database logic.

If historical data predates a new trigger, do not claim it was backfilled unless a migration actually performs the backfill.

---

# 28. AUDIT LOGGING

Critical actions should be traceable.

Audit at minimum:
- Actor.
- Mess.
- Action.
- Entity.
- Record ID.
- Previous state where relevant.
- New state where relevant.
- Timestamp.
- Reason where relevant.

Audit examples:
- Member approved.
- Permission changed.
- Meal changed after cutoff.
- Bazar approved.
- Deposit voided.
- Settlement closed.

---

# 29. ERROR HANDLING

Every API/database action must have:

```text
Loading state
Success state
Empty state
Error state
```

Errors should tell the user what happened and what to do.

Bad:

```text
Something went wrong.
```

Better:

```text
This meal is already locked because the cutoff has passed.
```

Better:

```text
You do not have permission to approve bazar entries.
```

Do not expose sensitive database internals to ordinary users.

Log technical details to the console during development where appropriate.

---

# 30. FORMS

All forms need:
- Required-field validation.
- Numeric validation.
- Date validation.
- Appropriate min/max checks.
- Disabled submit while saving.
- Success feedback.
- Error feedback.
- No accidental double submission.
- Accessible labels.

Financial forms should use appropriate currency/number formatting.

---

# 31. RESPONSIVE DESIGN

Test at least conceptually against:

```text
Desktop: 1440px+
Laptop: 1024–1439px
Tablet: 768–1023px
Mobile: 320–767px
```

Requirements:
- No horizontal overflow.
- No overlapping buttons.
- No unreadable tiny text.
- Tables adapt to mobile cards where necessary.
- Modal dialogs fit mobile screens.
- Touch targets are sufficiently large.

---

# 32. ACCESSIBILITY

Use:
- Semantic HTML.
- Labels.
- Keyboard-accessible controls.
- Visible focus states.
- Adequate contrast.
- `aria-label` for icon-only buttons.
- Meaningful status text, not color alone.

Do not make an icon-only button without a tooltip/title or accessible label.

---

# 33. PERFORMANCE

Avoid:
- Unnecessary repeated Supabase queries.
- Infinite polling from multiple components.
- Duplicate realtime subscriptions.
- Unbounded meal generation.
- Rendering huge lists without need.
- Re-fetching the entire dashboard after every tiny interaction.

Use targeted refreshes and shared state where appropriate.

---

# 34. CODE QUALITY

Prefer:
- Small reusable components.
- Reusable API/data helpers.
- Centralized Supabase client.
- Centralized permission checks for UI visibility.
- Consistent naming.
- Minimal duplication.
- Clear separation between UI and data operations.

Do not perform a massive rewrite merely to make the folder structure look cleaner.

Refactor incrementally after functionality is stable.

---

# 35. ENVIRONMENT VARIABLES

Use Vite environment variables for Supabase configuration.

Expected client-side configuration pattern:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_PUBLISHABLE_KEY
```

Support the repository's existing compatible anon-key variable if it is already used.

Never commit secrets.

---

# 36. DEPLOYMENT

The application is deployed through GitHub Actions to GitHub Pages.

Keep the existing deployment workflow working.

Before finishing:

```bash
npm install
npm run build
```

Fix:
- compile errors.
- import errors.
- missing dependencies.
- syntax errors.
- broken asset paths.
- SPA routing issues appropriate to GitHub Pages.

Do not replace the deployment architecture with another host.

---

# 37. GITHUB WORKFLOW

Every meaningful implementation step should result in clean, understandable Git history.

Recommended commit groups:

```text
feat: complete authentication flow
feat: complete mess membership workflow
feat: complete meal management
feat: complete bazar workflow
feat: complete finance and deposits
feat: complete ledger and settlement
feat: complete notifications and reports
refactor: improve application shell and navigation
style: redesign dashboard and responsive UI
fix: security/accounting integrity issue
```

Do not commit generated secrets, local environment files, or unnecessary build output.

---

# 38. TESTING STRATEGY

Before declaring the project complete, test the following user journeys.

## Journey A — New Manager

```text
Sign up
  ↓
Create mess
  ↓
Become manager
  ↓
Open dashboard
  ↓
Configure meal rules
  ↓
See member management
```

## Journey B — New Member

```text
Sign up
  ↓
Enter mess code
  ↓
Request join
  ↓
PENDING screen
  ↓
No accounting
```

## Journey C — Approval

```text
Manager receives request
  ↓
Approve
  ↓
Member becomes ACTIVE
  ↓
Accounting eligibility starts
```

## Journey D — Meals

```text
Active member
  ↓
Open Meals
  ↓
Set Breakfast/Lunch/Dinner
  ↓
Save
  ↓
Cutoff passes
  ↓
Member becomes locked
```

## Journey E — Bazar

```text
Authorized user
  ↓
Create bazar
  ↓
Add items
  ↓
Submit
  ↓
Manager/authorized approver
  ↓
Approve
  ↓
Record immutable
```

## Journey F — Finance

```text
Manager posts expense
  ↓
Manager/member posts deposit as permitted
  ↓
Ledger updates
  ↓
Balance updates
```

## Journey G — Settlement

```text
Open month
  ↓
Calculate
  ↓
Review
  ↓
Close
  ↓
Members see final settlement
  ↓
Closed record cannot be normally edited
```

---

# 39. SECURITY TESTS

Attempt these intentionally:

```text
Member reads another mess's data            -> DENY
Member writes another mess's data            -> DENY
Member changes another member's meal         -> DENY
Member edits after cutoff                    -> DENY
Unauthorized user creates bazar              -> DENY
Unauthorized user approves bazar             -> DENY
Member changes manager settings               -> DENY
Member grants permissions                     -> DENY
User changes another user's balance           -> DENY
Client submits fake financial total           -> server recalculates/rejects
Client submits fake role                      -> ignored/rejected
Closed settlement direct update               -> DENY
Approved bazar direct update                  -> DENY
```

These tests must be enforced by the database/security layer, not only by React.

---

# 40. UI ACCEPTANCE CHECKLIST

The finished application should have:

```text
[ ] Professional login/signup screen
[ ] Clear onboarding
[ ] Create mess screen
[ ] Join mess screen
[ ] Pending approval screen
[ ] Manager dashboard
[ ] Member dashboard
[ ] Responsive navigation
[ ] Meals screen
[ ] Meal calendar/schedule
[ ] Cutoff/lock indicators
[ ] Manager override UI
[ ] Members screen
[ ] Permission management
[ ] Bazar list
[ ] Bazar create/edit draft
[ ] Bazar approval
[ ] Expense screen
[ ] Deposit/payment screen
[ ] Balance screen
[ ] Ledger screen
[ ] Monthly settlement screen
[ ] Reports screen
[ ] Notification center
[ ] Mess settings
[ ] Loading states
[ ] Empty states
[ ] Error states
[ ] Mobile responsive layout
[ ] Desktop responsive layout
```

---

# 41. PRODUCT QUALITY BAR

Do not consider the project finished merely because:
- the page loads,
- the dashboard looks attractive,
- buttons exist,
- sample rows appear, or
- the build command succeeds.

It is finished only when the main workflows operate against real Supabase data and respect the security/accounting rules.

A successful build is necessary but not sufficient.

---

# 42. IMPLEMENTATION ORDER

Follow this order unless repository dependencies require a different sequence:

```text
1. Repository audit
2. Build/runtime baseline
3. Auth/session
4. Mess creation/join
5. Membership + roles + permissions
6. Dashboard/application shell
7. Meals + cutoff + scheduling
8. Bazar + item lines + approval
9. Expenses
10. Deposits
11. Accounting calculations
12. Ledger
13. Monthly settlement
14. Notifications
15. Reports
16. Settings
17. Responsive UI polish
18. Accessibility
19. Security review
20. Accounting integrity review
21. End-to-end testing
22. Production build/deployment verification
```

Do not jump directly to cosmetic work while a core workflow is broken.

---

# 43. WHEN THE EXISTING CODE CONFLICTS WITH THIS SPEC

Use this priority:

```text
Database/security integrity
        >
Business rules
        >
Real data correctness
        >
Existing working functionality
        >
UI/UX preferences
        >
Cosmetic refactoring
```

If existing UI code conflicts with the business rules, fix the UI.

If existing database logic conflicts with a security/integrity rule, add a forward migration and fix it safely.

Do not destroy working data or rewrite migrations that may already be deployed.

---

# 44. DO NOT MAKE THESE MISTAKES

### Mistake 1
Create a beautiful dashboard with fake numbers.

**Correct:** load real values from Supabase.

### Mistake 2
Hide manager controls with CSS and assume that is security.

**Correct:** enforce authorization in RLS/RPC/database.

### Mistake 3
Let the client send `total=1260` and store it blindly.

**Correct:** calculate/validate from item rows server-side.

### Mistake 4
Allow a pending member to appear in meal/accounting totals.

**Correct:** enforce ACTIVE eligibility.

### Mistake 5
Allow ordinary edit after bazar approval.

**Correct:** immutable approved state + correction workflow.

### Mistake 6
Allow closed settlement to be silently recalculated.

**Correct:** closed is immutable; use adjustment/reversal.

### Mistake 7
Replace the entire application shell without understanding current auth/navigation logic.

**Correct:** inspect and reconcile incrementally.

### Mistake 8
Add another backend service because a Supabase operation is difficult.

**Correct:** solve it with existing Supabase schema/RLS/RPC/triggers or a new Supabase migration.

### Mistake 9
Finish without testing mobile.

**Correct:** test responsive behavior and touch interactions.

---

# 45. DEFINITION OF DONE

MessMate is ready for production review when all of these are true:

```text
AUTH
[ ] Signup works
[ ] Signin works
[ ] Session persists
[ ] Signout works
[ ] Password reset works or is correctly wired

MESS
[ ] Create mess works
[ ] Join by code works
[ ] Pending state works
[ ] Manager approval works
[ ] Membership lifecycle works

MEALS
[ ] Breakfast works
[ ] Lunch works
[ ] Dinner works
[ ] Future scheduling works
[ ] Cutoff works
[ ] Lock state is clear
[ ] Manager override works
[ ] Override is audited

BAZAR
[ ] Permission works
[ ] Item lines work
[ ] Totals are correct
[ ] Approval works
[ ] Approved data is immutable

FINANCE
[ ] Expenses work
[ ] Deposits work
[ ] Deposit ledger sync works
[ ] Void/reversal works
[ ] Balance is correct

LEDGER
[ ] Entries are traceable
[ ] Running balance is correct
[ ] Adjustments/reversals preserve history

SETTLEMENT
[ ] Monthly calculation works
[ ] Review works
[ ] Close works
[ ] Closed state is immutable

NOTIFICATIONS
[ ] Join notifications work
[ ] Meal reminders/cutoff notifications work where configured
[ ] Bazar notifications work
[ ] Settlement notifications work
[ ] Read/unread works

REPORTS
[ ] Daily report works
[ ] Monthly report works
[ ] Member report works

SECURITY
[ ] RLS isolation tested
[ ] Role checks tested
[ ] Permission checks tested
[ ] Cutoff bypass tested
[ ] Financial tampering tested
[ ] Cross-mess access tested

UX
[ ] Desktop polished
[ ] Mobile polished
[ ] No overlapping controls
[ ] No excessive empty space
[ ] No floating buttons covering content
[ ] Loading/empty/error states present
[ ] Accessible labels/focus states present

ENGINEERING
[ ] No secrets committed
[ ] No core TODO placeholders
[ ] No fake production data
[ ] `npm run build` passes
[ ] GitHub Pages workflow remains valid
```

---

# 46. FINAL INSTRUCTION TO THE REPLIT AGENT

**Build the actual MessMate application described here.**

Do not answer with a plan instead of implementing it.

Do not stop after a UI mockup.

Do not replace real Supabase operations with local state just to make screens appear functional.

Do not weaken RLS or authorization to make a feature work.

Do not delete existing working functionality without understanding its purpose.

Use the existing repository as the starting point, inspect it carefully, implement the missing pieces, connect every major module to Supabase, enforce the business rules at the database/security layer, polish the UI for desktop and mobile, and finish by running the production build and fixing errors.

The final result should be a coherent, production-quality **MessMate shared-mess management system**, not a collection of disconnected screens.

**Master reference:** `docs/MESSMATE_FULL_PROJECT_BLUEPRINT.md`

**Implementation contract:** this file.
