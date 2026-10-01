# CLAUDE.md

Notes for working on FS25_RedTape. This file currently documents the **Policy** system only.

## What a policy is

A policy is a farming regulation the game periodically checks a farm against. Compliance pays out
policy **points**; non-compliance produces **warnings**, then **fines**, and usually loses points.
Points determine the farm's compliance **tier**, which in turn drives scheme quality and tax
benefits.

## Where the code lives

| File | Role |
| --- | --- |
| `src/system/PolicyList.lua` | `RTPolicyIds` + `RTPolicies` — the static definition of every policy, including its `evaluate` logic |
| `src/instances/Policy.lua` | `RTPolicy` — one *active* policy instance (save/load, streaming, evaluation entry point) |
| `src/system/PolicySystem.lua` | `RTPolicySystem` — generation, points, tiers, warnings, fines |
| `src/events/Policy*.lua` | The multiplayer events every state change goes through |
| `src/gui/MenuRedTape.lua`, `src/gui/tableRenderers/ActivePoliciesRenderer.lua` | The Policies tab |
| `src/RedTapeSettings.lua` | Settings, including the per-policy enable/disable toggles |

## Static definition (`RTPolicies`)

Keyed by `RTPolicyIds.<NAME>`. Common fields:

- `id`, `name`, `description`, `report_description` — the last three are i18n keys.
  A policy whose description depends on a setting supplies `getDescription(policyInfo)` instead of
  a plain `description` (see `RESTRICTED_SLURRY`).
- `probability` — relative weight used when picking which policy to issue next.
- `evaluationInterval` — months between evaluations (`1` = monthly, `12` = yearly).
- `periodicReward` / `periodicPenalty` / `pointsPenaltyPerViolation` — points applied on evaluation.
- `finePerViolation`, `warningThreshold`, `maxWarnings` — fine and warning behaviour.
- `activate(policyInfo, policy, farmId)` — called once per farm when the policy is issued.
- `evaluate(policyInfo, policy, farmId, currentTier)` — the actual check. Returns a report: an
  array of `{cell1, cell2, cell3}` rows, coerced to strings by `RTPolicy:evaluate`.

Adding a policy means adding an `RTPolicyIds` entry and an `RTPolicies` entry. Nothing else needs
touching — its settings toggle is generated automatically (see below).

## Lifecycle

1. **Generation** — `RTPolicySystem:generatePolicies()` runs on period change and tops the active
   list up to `DESIRED_POLICY_COUNT` (10). `getNextPolicyIndex()` picks from policies not already
   active, weighted by `probability`.
2. **Evaluation** — `RTPolicySystem:periodChanged()` (server only) calls `RTPolicy:evaluate()` on
   every active policy. A policy only evaluates once
   `RedTape.getCumulativeMonth() >= policy.nextEvaluationMonth`.
   **`evaluate` must never throw.** `RedTape:periodChanged` runs the policy, scheme, tax and grant
   systems in sequence and then `InfoGatherer:resetMonthlyData()`, so an uncaught error skips the
   rest of month end, including the reset (next month would then fine the same violations again).
   `pcall` is not available, so missing or malformed data (unknown policy index, nil values from
   an old or edited savegame) must be guarded: log with `RedTape.logWarning` and skip.
3. **Consequences** — `evaluate` sends `RTPolicyPointsEvent`, `RTPolicyClearWarningsEvent`, and
   (via `RTPolicySystem:WarnAndFine`) `RTPolicyWarningEvent` / `RTPolicyFineEvent`. Reports go out
   as `RTPolicyReportEvent`. All state changes go through events so the server stays authoritative
   and clients stay in sync; the server itself also sends via `g_client:getServerConnection()`.

## Tiers and points

`RTPolicySystem.THRESHOLDS`: A = 1500, B = 750, C = 300, D = 0. Points are clamped to
`[0, threshold(A)]`. Crossing a tier boundary calls `updateSchemeTiers` so active schemes with
`autoTierTransition` follow the new tier.

## Warnings and fines

`WarnAndFine(policyInfo, policy, farmId, fineIfDue, skipWarning)`. A warning is recorded first; the
fine only lands once the warning count would exceed `maxWarnings` (default 1), or immediately if
`skipWarning` is true (a severe enough breach). Recording a fine resets that farm/policy warning
count to 0. Fines use `MoneyType.POLICY_FINE`.

## Persistence

Active policies, points and warnings are saved to `<savegame>/RedTape.xml` under
`RedTape.policySystem`. `RTPolicySystem:saveToXmlFile` skips writing entirely when the
policies/schemes system is switched off.

## Enable/disable settings

Two independent levels:

- `policiesAndSchemesEnabled` — the whole policies *and* schemes system.
- `policyEnabled_<POLICY_KEY>` — one toggle **per policy**, e.g. `policyEnabled_CROP_ROTATION`.

The per-policy toggles are **generated** in `src/RedTapeSettings.lua` from `RTPolicies`, sorted by
policy id so menu order and the multiplayer stream order stay stable. They are appended to
`RedTape.menuItems` (so save, load and sync pick them up for free) and also tracked in
`RedTape.policyMenuItems`. Each defaults to **on**, is server-only, and uses the
`redTapeSettings` permission. They have no `rt_setting_`/`rt_toolTip_` keys of their own: the label
is the policy name and the tooltip is `rt_toolTip_policyEnabled` formatted with it, supplied via
the setting's `title` / `toolTip` fields (see `RedTape.getSettingTitle` / `getSettingToolTip`).
In the game settings page they sit under their own `rt_header_policies` section header.

`RedTape.isPolicyEnforced(policyId)` is the single check. It returns **true** for an unknown policy
or an unset value, so a missing setting can never silently switch a rule off — which is also why
savegames from before this feature load with every policy enforced.

Where it is applied:

- `RTPolicySystem:getNextPolicyIndex()` — a disabled policy is never issued.
- `RTPolicy:evaluate()` — returns early, so no report, points, warnings or fines. It still rolls
  `nextEvaluationMonth` forward, so re-enabling a policy starts a fresh evaluation period instead
  of immediately judging the months it spent switched off.
- `RTPolicySystem:getEnforcedPolicies()` — what the Policies tab lists.

A policy disabled while already active **keeps its record** (reports, warnings, watch flags), so
re-enabling resumes where it left off. It also keeps its slot against `DESIRED_POLICY_COUNT`, so
disabling an active policy leaves the farm with fewer active policies rather than substituting a
different one.
