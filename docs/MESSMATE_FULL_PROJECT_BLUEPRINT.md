# MessMate — Full Project Blueprint

> Master product, architecture, database, security, UX and delivery specification for the shared-mess management platform.

## 1. Product Vision

**MessMate** is a complete digital management system for shared messes. It combines membership, meals, bazar, expenses, deposits, accounting, ledger, monthly settlement, notifications, reports and audit controls in one mobile-first application.

Primary goals:
- Simple daily operation for members.
- Strong financial integrity for managers.
- Clear approval and permission workflows.
- Server-side security with Supabase Auth, RLS and RPCs.
- Full traceability for important changes.
- Responsive desktop and mobile UX.

## 2. Technology Stack

```text
Frontend: React + Vite
Database/Auth: Supabase PostgreSQL + Supabase Auth
Security: PostgreSQL RLS + SECURITY DEFINER RPCs where required
Automation: Supabase/Postgres triggers + scheduled worker/cron
Source control: GitHub
Deployment: GitHub Pages + GitHub Actions
```

No third-party application hosting is required for the core product.

## 3. High-Level Architecture

```text
                         MESSMATE
                            |
             +--------------+--------------+
             |                             |
          FRONTEND                     SUPABASE
             |                             |
       React + Vite              +---------+---------+
             |                   |         |         |
        UI Modules              Auth      DB       Automation
             |                             |         |
       Service Helpers                    RLS      Triggers/Cron
             |                             |
             +-----------------------------+
```

Request path for protected operations:

```text
User -> React UI -> Supabase Auth Session -> RLS/RPC -> PostgreSQL
```

The frontend must never be treated as the security boundary.

## 4. User Roles

### Manager

Full mess administration:
- Create/configure mess.
- Approve/reject join requests.
- Activate/deactivate members.
- Assign roles and specific permissions.
- Configure meal rules and cutoffs.
- Manage/approve bazar.
- Manage expenses and deposits.
- Review ledger and balances.
- Calculate/close monthly settlements.
- View reports, notifications and audit history.

### Bazar Manager

Only explicitly granted bazar capabilities:
- Create bazar entries.
- Add/edit draft item lines.
- Submit bazar for approval.
- Approve/reject only where the permission model allows it.
- View bazar history.

### Member

- View/edit own eligible meals.
- Schedule meals before cutoff.
- View own balance and ledger.
- Submit/view payments as permitted.
- View bazar information.
- View monthly settlement.
- Receive notifications.
- View mess information.

## 5. Mess and Membership Lifecycle

```text
CREATE MESS
    |
    +----------------------+
    |                      |
    v                      v
JOIN REQUEST            MANAGER
    |                      |
  PENDING <---------------+
    |
 APPROVE / REJECT
    |
    v
 ACTIVE
    |
    +----> SUSPENDED
    |
    +----> LEFT
```

Required membership timestamps:
- `joined_at`
- `activated_at`
- `left_at`

### Critical accounting rule

A `PENDING` member has **zero accounting eligibility**.

```text
PENDING:
  no meals
  no bazar/expense share
  no balance
  no settlement

ACTIVE:
  accounting starts
```

Inactive/left members cannot receive new normal accounting entries unless an explicit historical adjustment workflow permits it.

## 6. Authentication

Required flows:
- Sign up.
- Sign in.
- Sign out.
- Session persistence.
- Password reset.
- Email confirmation where enabled.
- Auth error mapping with user-readable messages.

Auth flow:

```text
SIGN UP -> SUPABASE AUTH USER -> SESSION/CONFIRMATION -> MESS SETUP
SIGN IN -> SUPABASE SESSION -> MEMBERSHIP CHECK -> APP
```

Never expose service-role credentials in frontend code.

## 7. Mess Setup

First authenticated user chooses:

```text
Create New Mess
       OR
Join Existing Mess
```

Create-mess fields:
- Mess name.
- Mess code.
- Manager.
- Start date.
- Default meal rate/settings.
- Operational preferences.

Join flow:
- Enter mess code or use QR.
- Create `PENDING` request.
- Manager reviews.
- Approval creates/activates membership.

## 8. Meal Management

Meal types:
- Breakfast.
- Lunch.
- Dinner.

Values:
- ON = 1.
- OFF = 0.

Daily view:

```text
Date
Breakfast   ON/OFF
Lunch       ON/OFF
Dinner      ON/OFF
Total meals
Lock state
```

### Scheduling

Support:
- Single date.
- Date range.
- Meal-type selection.
- ON/OFF selection.
- Future-date entries.

### Cutoff

Manager controls cutoff rules globally and/or per meal.

```text
Before cutoff -> member may edit
After cutoff  -> locked
```

After cutoff, unconfirmed entries follow the configured default rule. Manager override is allowed only through the protected server-side workflow.

### Meal override audit

Every manager override should retain:
- Actor.
- Member.
- Date.
- Meal type.
- Before value.
- After value.
- Timestamp.
- Reason when required.

## 9. Bazar Management

Bazar entry structure:

```text
Bazar
  |
  +-- item
  +-- quantity
  +-- unit
  +-- unit price
  +-- line total
  |
  +-- grand total
```

Example:

```text
Rice       10 kg x 70  = 700
Potato      5 kg x 40  = 200
Oil         2 L  x 180 = 360
---------------------------
Grand Total            1260
```

### Approval workflow

```text
DRAFT -> PENDING -> APPROVED
                 \-> REJECTED
```

If approval is required:
- New entry starts `PENDING`.
- Authorized approver approves/rejects.
- Approved entry becomes immutable.

Atomic creation must prevent partial bazar records or inconsistent totals.

## 10. Bazar Permissions

Manager grants specific capabilities to specific members.

Example:

```text
Rahim -> Bazar Manager
Karim -> No bazar permission
```

Permission checks must exist in database/RPC/RLS logic. Hiding a button in React is not security.

## 11. Expense Management

Categories:
- Rent.
- Gas.
- Electricity.
- Internet.
- Water.
- Maid.
- Cleaning.
- Other.

Every expense should retain:
- Mess.
- Category.
- Amount.
- Date.
- Description/note.
- Actor.
- Status/void information where applicable.

Financial corrections should use reversal/adjustment semantics rather than silently overwriting historical accounting.

## 12. Deposits / Payments

Payment record should contain:
- Member.
- Amount.
- Date.
- Payment method.
- Note/reference.
- Actor.
- Status.

Deposit accounting rule:

```text
Deposit approved/posted
        |
        v
Ledger credit
```

Void/correction:

```text
Void deposit
    |
    v
Reversal ledger entry
```

Existing historical data must be considered when adding automatic sync triggers; do not assume a trigger backfills old records unless an explicit backfill migration exists.

## 13. Accounting Engine

Core calculation:

```text
Member Cost
= Meal Cost
+ Bazar/Expense Share
+ Other Charges

Balance
= Total Credits/Deposits
- Total Cost
```

Positive balance means credit; negative balance means amount due.

### Meal rate

```text
Meal Rate
= Total Food Cost / Total Meals
```

Example:

```text
Food Cost = 30,000
Meals     = 600
Meal Rate = 50
```

Member meal cost:

```text
40 meals x 50 = 2,000
```

All production calculations should use database-side authoritative values, not client-supplied totals.

## 14. Ledger

Ledger is the financial source of traceability.

Example:

```text
18 Sep  Deposit      +5000
18 Sep  Meal Cost    -1000
18 Sep  Bazar Share  -1200
18 Sep  Expense Share -500
---------------------------
Balance              2300
```

Rules:
- Do not silently overwrite financial history.
- Use adjustments/reversals for corrections.
- Keep source/reference information.
- Preserve actor and timestamps where appropriate.
- Prevent unauthorized direct writes.

## 15. Monthly Settlement

Lifecycle:

```text
OPEN -> CALCULATED -> REVIEW -> CLOSED
```

Member settlement contains at least:
- Member.
- Total meals.
- Meal cost.
- Bazar/expense allocation.
- Deposits/credits.
- Final balance.
- Settlement status.

Once closed:

```text
No normal edit
No normal delete
No silent recalculation
```

Correction after closure requires an explicit adjustment/reversal workflow.

## 16. Reports

### Daily report
- Total meals.
- Breakfast/Lunch/Dinner totals.
- Bazar total.
- Expense total.
- Deposits where relevant.

### Monthly report
- Total food cost.
- Total meals.
- Meal rate.
- Total expenses.
- Total deposits.
- Member balances.
- Settlement status.

### Member report
- Meals.
- Meal cost.
- Allocated expenses/bazar.
- Deposits.
- Balance.

Future export targets:
- CSV.
- Excel.
- PDF.
- Print view.

## 17. Notifications

Notification types:
- Join request.
- Join approved/rejected.
- Meal reminder.
- Meal cutoff warning.
- Bazar pending.
- Bazar approved/rejected.
- Payment/deposit posted.
- Settlement ready.
- Settlement closed.

Notification fields should support:
- Recipient.
- Type.
- Title.
- Body.
- Read/unread state.
- Created time.
- Optional source/reference metadata.

Unread count appears in the UI.

## 18. Dashboard UX

Dashboard priority:

1. Today's meals.
2. My balance.
3. Pending actions.
4. Bazar.
5. Monthly status.
6. Quick actions.
7. Recent activity.

Manager dashboard should prominently surface:
- Pending join requests.
- Pending bazar approvals.
- Upcoming meal cutoffs.
- Current month status.

Desktop layout target:
- Centered content.
- Maximum width around 1180–1240px.
- No oversized empty regions.
- Clear KPI cards.
- Integrated quick actions.
- No floating buttons covering content.

Mobile layout target:
- Compact header.
- Touch-friendly controls.
- Two-column KPI/quick-action grids where appropriate.
- Bottom navigation for primary modules.
- Cards instead of wide tables.
- No horizontal overflow.

## 19. Navigation

Primary modules:

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

Desktop may use a sidebar; mobile should use compact header + bottom navigation.

## 20. UI State Standards

Every asynchronous module must have:

```text
Loading
Empty
Error
Success
Locked
Pending
Approved
Rejected
```

Errors should be specific and actionable. Avoid generic messages such as `Something went wrong` when a known backend reason is available.

## 21. Database Domain Model

Core entities:

```text
auth.users
messes
mess_members
join_requests
member_permissions

meal_entries
meal_rules
meal_cutoffs
meal_overrides/audit records

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

Relationships:

```text
MESS
 |
 +-- MEMBERS
 |     +-- ROLE/PERMISSIONS
 |
 +-- MEALS
 +-- MEAL RULES
 +-- BAZAR
 |     +-- BAZAR ITEMS
 +-- EXPENSES
 +-- DEPOSITS
 +-- LEDGER
 +-- SETTLEMENTS
 +-- NOTIFICATIONS
 +-- AUDIT LOGS
```

## 22. Security Architecture

Security layers:

```text
Supabase Auth
     |
     v
RLS policies
     |
     v
Protected RPCs
     |
     v
PostgreSQL constraints/triggers
     |
     v
Audit trail
```

Security requirements:
- Mess-to-mess data isolation.
- Server-side role checks.
- Server-side permission checks.
- Server-side membership status checks.
- Server-side meal cutoff enforcement.
- Server-side accounting validation.
- No direct client write path for protected financial operations.
- No service-role key in browser.
- Immutable states enforced by database logic.

## 23. Critical Business Invariants

These are non-negotiable:

```text
1. PENDING member = ZERO accounting.
2. Only eligible ACTIVE membership participates in normal accounting.
3. Approved bazar = immutable.
4. Closed settlement = immutable.
5. Financial correction = reversal/adjustment.
6. Deposit posting synchronizes with ledger.
7. Voided deposit creates/requires a reversal.
8. Meal cutoff is enforced server-side.
9. Manager meal override is audited.
10. Roles/permissions are checked server-side.
11. RLS isolates every mess.
12. Frontend state is never trusted for security.
13. Critical financial mutations use protected RPCs.
14. Client-supplied financial totals are not authoritative.
15. Every critical mutation must be traceable.
```

## 24. Audit System

Audit records should capture, where relevant:
- Actor/user.
- Mess.
- Action.
- Entity/table.
- Record ID.
- Old value/state.
- New value/state.
- Reason.
- Timestamp.

Audit examples:

```text
Manager approved member
Manager changed meal after cutoff
Manager granted bazar permission
Bazar entry approved
Deposit voided
Settlement closed
```

## 25. Project Structure

Target structure:

```text
messmate-management/
|
+-- src/
|   +-- App.jsx
|   +-- AppShell.jsx
|   +-- components/
|   |   +-- UI/
|   |   +-- Cards/
|   |   +-- Forms/
|   |   +-- Tables/
|   |   +-- Modal/
|   |
|   +-- modules/
|   |   +-- dashboard/
|   |   +-- meals/
|   |   +-- members/
|   |   +-- bazar/
|   |   +-- finance/
|   |   +-- ledger/
|   |   +-- settlement/
|   |   +-- reports/
|   |   +-- notifications/
|   |   +-- settings/
|   |
|   +-- lib/
|       +-- supabase.js
|       +-- auth.js
|       +-- permissions.js
|       +-- helpers.js
|
+-- supabase/
|   +-- migrations/
|
+-- public/
|
+-- .github/
|   +-- workflows/
|
+-- docs/
|   +-- MESSMATE_FULL_PROJECT_BLUEPRINT.md
|
+-- README.md
```

The current codebase can evolve toward this structure incrementally; avoid a risky rewrite while core accounting/security is still being stabilized.

## 26. Development Roadmap

### Phase 1 — Foundation
- Auth.
- Mess creation/join.
- Membership lifecycle.
- Roles.
- RLS.

### Phase 2 — Meals
- Daily meal entry.
- Future scheduling.
- Cutoff.
- Defaults.
- Overrides.
- Audit.

### Phase 3 — Bazar
- Permission.
- Entry.
- Item lines.
- Approval.
- Immutable approved records.

### Phase 4 — Finance
- Expenses.
- Deposits.
- Meal rate.
- Accounting engine.

### Phase 5 — Ledger
- Automatic ledger.
- Balance.
- Adjustments/reversals.
- Integrity checks.

### Phase 6 — Settlement
- Monthly calculation.
- Review.
- Close.
- Immutable closed state.

### Phase 7 — Notifications
- Reminders.
- Approval notifications.
- Settlement notifications.
- Notification center.

### Phase 8 — Reports
- Daily.
- Monthly.
- Member.
- Financial.
- Export.

### Phase 9 — UX
- Desktop navigation.
- Mobile navigation.
- Dashboard redesign.
- Loading/empty/error states.
- Accessibility polish.

### Phase 10 — Security & QA
- Full RLS review.
- RPC authorization review.
- Accounting integrity tests.
- Multi-mess isolation tests.
- Membership edge cases.
- Cutoff/lock edge cases.
- Settlement immutability tests.
- Audit verification.

### Phase 11 — Production
- GitHub Actions deployment.
- Supabase production configuration.
- Environment variables.
- Backup/recovery plan.
- Monitoring.
- Release checklist.

## 27. QA Test Matrix

### Authentication
- New user signup.
- Existing user signup.
- Correct login.
- Wrong password.
- Unconfirmed email.
- Signout.
- Session restoration.

### Membership
- Valid join code.
- Invalid join code.
- Duplicate request.
- Manager approval.
- Manager rejection.
- Pending user cannot create accounting.
- Activation starts accounting eligibility.
- Leaving mess stops normal future accounting.

### Meals
- Active member can edit before cutoff.
- Locked meal cannot be changed by member.
- Manager override works.
- Override audited.
- Default rule applied after cutoff.
- Future schedule works.

### Bazar
- Authorized user can create.
- Unauthorized user cannot create through API/RPC.
- Item totals are validated server-side.
- Pending approval works.
- Approved record cannot be edited.

### Finance/Ledger
- Expense posts correctly.
- Deposit posts correctly.
- Void creates reversal.
- Balance is consistent.
- Unauthorized direct writes fail.

### Settlement
- Monthly totals correct.
- Closed settlement cannot be mutated normally.
- Adjustment workflow preserves history.

### Isolation
- User in Mess A cannot read Mess B.
- User in Mess A cannot mutate Mess B.
- Role from Mess A cannot grant permissions in Mess B.

## 28. Release Gates

A release is production-ready only when:

```text
[ ] Auth works
[ ] Mess creation works
[ ] Join/approval works
[ ] Pending has zero accounting
[ ] Meal cutoff works
[ ] Bazar approval works
[ ] Approved bazar immutable
[ ] Expenses work
[ ] Deposits sync to ledger
[ ] Ledger balances reconcile
[ ] Settlement calculates correctly
[ ] Closed settlement immutable
[ ] Notifications work
[ ] RLS isolation verified
[ ] Critical RPC authorization verified
[ ] Audit trail verified
[ ] Desktop UI verified
[ ] Mobile UI verified
[ ] GitHub Actions deployment passes
```

## 29. Future Enhancements

After the core product is stable:
- QR join.
- PWA installation.
- Push notifications.
- CSV/Excel/PDF export.
- Expense trend analysis.
- Bazar price analytics.
- Meal usage analytics.
- Smart reminders.
- Optional meal suggestions based on historical patterns, always requiring user confirmation before accounting impact.

## 30. Product North Star

MessMate should always optimize for:

**Simple daily use + correct accounting + strong security + complete auditability.**

When a new feature is proposed, evaluate it against these four principles before adding it to the production flow.
