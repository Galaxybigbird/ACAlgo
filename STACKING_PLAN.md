# Option 2 Plan – Stack Min-Lot Orders as Risk Fallback

## Objective
When the desired lot size (after stop clamping) is still below the broker's `SYMBOL_VOLUME_MIN`, split the position into multiple tickets of the minimum lot size so that the combined exposure reaches the target risk.

## Key Points
- Use when calculated lot size < `SYMBOL_VOLUME_MIN`.
- Number of tickets = `ceil(requiredLot / minLot)`.
- Each ticket uses the same entry, SL, TP.
- Maintain risk integrity: `riskAmount` divided equally across the stacked tickets.

## Implementation Steps
1. Detect under-sized lot after final stop distance clamp.
2. Compute `numTickets = MathCeil(requiredLot / minLot)`, capped by broker limits if needed.
3. Derive per-ticket volume (`minLot`, maybe adjust final ticket to cover any remainder).
4. Issue multiple `trade.PositionOpen` calls with unique identifiers in `OrderComment` or via encoded magic number.
5. Group tickets for AC risk management:
   - Store bundle ID (e.g., timestamp + symbol) when issuing tickets.
   - Aggregate P/L from all tickets in the bundle before calling `UpdateRiskBasedOnResult` so compounding treats them as one trade.
6. Handle trailing/close logic by referencing bundle metadata.

## Risks & Considerations
- Prop firms may limit number of open tickets; require configurable cap.
- Increased bookkeeping (bundle tracking, aggregated trailing/closing).
- More broker requests; ensure retry logic / error handling.

## Dependencies
- Needs shared data structure to track bundles (e.g., map ticket→bundle ID).
- ACFunctions risk-updater must accept aggregated profit.

