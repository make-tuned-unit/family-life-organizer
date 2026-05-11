# FamilyLife Flow Maps

Last updated: 2026-04-07

This document maps the logical user steps in each major feature and records which view states already exist in the app.

## Trips

Flow
- Start trip
- Confirm destination and traveler
- Begin live tracking
- Show in-transit state with map, ETA, and progress
- Send milestone alerts when close
- Mark arrived or cancel
- Review trip history
- Manage saved family destinations

Built views
- `TripsView`
- `NewTripView`
- `FamilyAddressesView`
- Active trip card with live route map, moving car marker, phase pills, and alert status
- Trip history rows

Built runtime states
- Empty state
- Start state
- In-transit state
- 15-minute-out state
- Near-arrival state
- Arrived action
- Cancel action
- Saved addresses state

Still missing
- Remote family-facing push path instead of local notification only
- Background location delivery and foreground/service continuity
- Explicit arrival summary screen

## Calendar

Flow
- Browse month or week
- Select day
- Review appointments
- Add appointment
- Edit appointment
- Delete appointment
- Optional reminder

Built views
- `CalendarView`
- `WeekView`
- `AddAppointmentView`
- `EditAppointmentView`

Built runtime states
- Empty-day state
- Loading state
- Add flow
- Edit flow
- Delete swipe actions
- Reminder opt-in on create

Still missing
- Reminder controls on edit
- Event import/export
- Conflict states and agenda summary view

## Pantry

Flow
- Browse by location
- Search items
- Add item
- Edit item
- Delete item
- Track expiry
- Trigger expiry alerts

Built views
- `PantryView`
- `AddPantryItemView`
- `EditPantryItemView`

Built runtime states
- Empty pantry state
- Filtered empty state
- Add flow
- Edit flow
- Delete actions
- Expiry badges
- Optional expiry alerts

Still missing
- Low-stock state
- Expired-items focused view
- Receipt-to-pantry review state before commit

## Groceries

Flow
- Review needed list
- Quick add item
- Search list
- Mark purchased
- Optionally migrate to pantry

Built views
- `GroceryListView`

Built runtime states
- Empty state
- Search-empty state
- Quick add state
- Purchase-to-pantry decision alert

Still missing
- Rich edit flow
- Quantity/category refinement view
- Completion summary state

## Expenses

Flow
- Review month summary
- Browse budget categories
- Review receipts
- Add receipt manually
- Scan receipt
- Review scan results
- Save receipt and optionally stock pantry
- Delete receipt

Built views
- `ExpensesView`
- `AddReceiptView`
- `ReceiptScannerView`

Built runtime states
- Empty receipts state
- Manual add state
- Scan-loading state
- Scan-results review state
- Save failure state
- Delete action

Still missing
- Receipt detail screen
- Scan correction/edit-before-save flow
- Month-over-month trend state

## Decisions

Flow
- Browse active decisions
- Filter by type
- Create decision
- Open detail
- React or vote
- Comment
- Resolve
- Review resolved history

Built views
- `DecisionsView`
- `NewDecisionView`
- `DecisionDetailView`

Built runtime states
- Empty state
- Filtered list state
- Create flow
- Poll vote state
- Reaction state
- Comment thread state
- Resolve state

Still missing
- Photo decision attachment flow
- Expired decision state handling
- Decision result summary view

## Rivalries

Flow
- Browse active rivalries
- Start rivalry
- Open detail
- Log progress
- Review leaderboard
- Finalize winner
- Review completed rivalries

Built views
- `RivalriesView`
- `StartRivalryView`
- `RivalryDetailView`
- `LogProgressView`

Built runtime states
- Empty state
- Start flow
- Active rivalry detail
- Log progress flow
- Leaderboard summary
- Finalize results state

Still missing
- Invite/accept decline flow
- Verified HealthKit sync view restored on shared backend path
- Win summary overlay on server-backed detail

## Gifts

Flow
- Browse people and events
- Add person
- Add event
- Open person gift list
- Add gift idea
- Progress idea through statuses
- Delete idea or event
- Review upcoming occasions

Built views
- `GiftsView`
- `PersonGiftListView`
- `AddGiftPersonView`
- `AddGiftIdeaView`
- `AddSpecialEventView`

Built runtime states
- Empty state
- Upcoming occasions state
- Add person flow
- Add event flow
- Add gift idea flow
- Status progression
- Delete actions

Still missing
- Person detail edit flow
- Event edit flow
- Purchased/wrapped gift checklist summary

## Home / Tasks

Flow
- Review today summary
- Open major feature hubs
- Add task
- Refresh dashboard

Built views
- `HomeView`
- `AddTaskView`
- `MoreView`

Built runtime states
- Dashboard summary
- Feature hub shortcuts
- Add task flow
- Error alert state

Still missing
- Task detail/edit state
- Overdue drill-in state
- Cross-feature “today agenda” detail screen
