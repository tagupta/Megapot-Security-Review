**What's happening now (short)**

When a user claims winnings for a past drawing, the function `_payReferrersWinnings` computes the referrerShare (a fraction of the winning amount) and, if there is no referral scheme, it currently does:

`drawingState[currentDrawingId].lpEarnings += referrerShare;`

i.e. it credits the LP earnings of the current drawing (the drawing now, not the drawing where the winning ticket belonged).

So: money owed to the referrer-share-of-a-win (when there is no explicit scheme) is added to the LP earnings of whoever happens to be the current drawing participants — LPs who were not necessarily the counterparty to the ticket that won.

**Why this is a problem**

**Short answer:** it misattributes value across time.

The winning ticket belonged to drawing D and was underwritten by LPs who backed drawing D (call them `LP_D`).

The claim happens at time `t > D`, and `currentDrawingId = C (C ≥ D)`. Crediting `drawingState[C]`.lpEarnings benefits `LP_C`, not `LP_D`.

If LP participation changed between D and C (withdrawals, new deposits, different LP set), `LP_C` receives funds that economically belong to `LP_D`. This is unfair to `LP_D` and beneficial to `LP_C`.

Worse: if `LP_D` already withdrew (claimable/withdrawn), the original LPs who bore the risk get nothing while later LPs capture the referrer-share.

So this is either:

a bug (if intended semantics: the referral win share should return to the LP pool that underwrote that drawing), OR

a deliberate but risky policy (if design intentionally funnels past winner referral-shares to the current LP pool). If it's the latter, it must be documented clearly.

**Concrete consequences (example)**
Drawing 10 backed by LPs A,B. A losing user wins a prize in drawing 10; referralWinShare (say 10 USDC) should logically go to LPs A,B (compensate them for underwriting that winning ticket).

Claim occurs much later in drawing 12. Current implementation credits drawing 12 LPs (maybe C,D). A,B lose out; C,D get extra revenue they didn't risk.

This is unfair and can be exploited via timing (LPs can leave before claims settle), or create accounting surprises.

**What to do — recommended fixes (safe, clear, minimal)**

_Option 1 (recommended): Attribute referrerWinShare to the drawing that the winning ticket belonged to_

Simplest conceptual fix: when paying winnings for a ticket belonging to drawing d, credit drawingState[d].lpEarnings (or lpDrawingState[d]) instead of drawingState[currentDrawingId].

Patch idea (signature change):
Change `_payReferrersWinnings` caller to pass the ticketDrawingId (or `_winningDrawingId`) and use it:

```diff
- function _payReferrersWinnings(bytes32 _referralSchemeId, uint256 _winningAmount, uint256 _referralWinShare) internal returns (uint256) {

+   function _payReferrersWinnings(bytes32 _referralSchemeId, uint256 \_winningAmount, uint256 _referralWinShare, uint256 _winningDrawingId) internal returns (uint256) {
  uint256 referrerShare = \_winningAmount \* \_referralWinShare / PRECISE_UNIT;
  if (\_referralSchemeId == bytes32(0)) {

-         drawingState[currentDrawingId].lpEarnings += referrerShare;
-         emit LpEarningsUpdated(currentDrawingId, referrerShare);

*         drawingState[_winningDrawingId].lpEarnings += referrerShare;
*         emit LpEarningsUpdated(_winningDrawingId, referrerShare);
          return referrerShare;
      }
      ...
  }
```

**Notes**

You must ensure the call site has access to the ticket's drawingId (it should — tickets are stored with drawing id).

This crediting will affect the lpEarnings value used when computing postDrawLpValue at settlement for drawing `_winningDrawingId`. If that drawing was already settled, then you must choose behavior: add to historical LP accounting (affects LPs who were present at that draw), or stash it to be applied to the next settlement for that drawing's LP ledger. See "Edge cases" below.

Option 2: If drawing d is already settled, route to a per-drawing `pendingReferralWinnings[d]` and apply in appropriate flow

If settlement for drawing d has already completed, adding to drawingState[d].lpEarnings might not affect LPs who have already finalized withdrawals. So do:

Maintain mapping(uint256 => uint256) drawingReferralAccrual;

On claim, do:

```solidity
if (drawingIsFinalized[_winningDrawingId]) {
// keep a reserve accounting, to be applied to the next LP settlement or to pay out to original LPs if still possible
drawingReferralAccrual[_winningDrawingId] += referrerShare;
} else {
drawingState[_winningDrawingId].lpEarnings += referrerShare;
}
```

Then in the appropriate spot (e.g., when next settling that drawing or at a reconciliation step), add drawingReferralAccrual[d] into the LP pool owed to LP_D or distribute to LPs who were stakers at time d (that requires historical share tracking).

This more complex approach is necessary if draws are finalized and LP accounting is already materialized and can't be retroactively altered.
