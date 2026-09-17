# MessMate UI/UX Guidelines

## Product goal
MessMate is a mobile-first Mess Meal & Accounts Management System. The interface must feel simple for everyday members while giving managers powerful controls without clutter.

## UX principles
- Mobile-first and fully responsive on phone, tablet, and desktop.
- Show the most important information first; minimize unnecessary taps.
- Use clear labels, familiar icons, strong visual hierarchy, and consistent spacing.
- Prefer smart defaults and pre-filled values for recurring actions.
- Keep financial figures, meal counts, pending actions, and locked states immediately understandable.
- Use confirmation for destructive or financially significant actions.
- Provide clear empty, loading, success, error, and offline/connection states.
- Never rely on color alone to communicate status.
- Keep member and manager experiences role-aware so users only see actions they can perform.
- Use accessible contrast, readable typography, large touch targets, and keyboard-friendly forms.

## Visual direction
- Clean, modern, friendly dashboard aesthetic.
- Card-based summaries for key metrics.
- Subtle borders and elevation; avoid excessive decoration.
- Consistent status treatment: active/success, pending/attention, rejected/error, locked/readonly.
- Support light and dark themes without changing information hierarchy.

## Member home priority
1. Today's meals
2. Tomorrow's meal plan
3. Current meal rate
4. My balance
5. Quick actions: Meal Off, Deposit, View Ledger
6. Relevant pending notifications

## Manager home priority
1. Today's meal count
2. Tomorrow's meal count
3. Pending join requests
4. Pending bazar approvals
5. Meal rate
6. Cash/balance summary
7. Quick actions: Add Bazar, Add Expense, Record Deposit, Manage Members

## Meal UX
- Breakfast, Lunch, and Dinner should be visually distinct but consistent.
- Clearly show ON, OFF, pending/unconfirmed, and locked states.
- Show each meal's cutoff time where relevant.
- Before cutoff, members can change their own meal status when permitted.
- After cutoff, meals are locked for members.
- Unconfirmed meals use the mess default rule, which is ON by default; manager can change the default to OFF.
- Manager override must be clearly identified and audited.

## Bazar UX
- Only members with `can_add_bazar` permission can see/use the add-bazar action.
- New entries are Pending when approval is required.
- Approval/rejection actions are available only to authorized managers/bazar managers.
- Show who created and who approved an entry, with timestamps.
- Approved entries become part of financial calculations; rejected entries do not.

## Forms
- Keep forms short and task-focused.
- Use sensible defaults such as today's date and active member.
- Validate amounts and required fields immediately.
- Make the primary action obvious and prevent accidental duplicate submissions.
- For financial records, show a review summary before final submission when appropriate.

## Navigation
Preferred mobile navigation: Home, Meals, Bazar, Ledger, Profile. Manager-only management/settings screens should be accessible without cluttering member navigation.

## Responsive behavior
- Phone: compact cards, bottom navigation, full-width primary actions.
- Tablet: two-column dashboard where useful.
- Desktop: sidebar/navigation plus multi-column dashboard and data tables.

## Security UX
- Hide unavailable actions and also enforce permissions server-side.
- Clearly explain why an action is unavailable when useful.
- Never expose secret keys or sensitive backend configuration in the UI.
