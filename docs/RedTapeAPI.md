# Red Tape API (v1): waste disposal

The API FS25_RedTape offers other mods. Version 1 has one feature: reporting the disposal of
regulated farm waste (waste oil and used coolant), which Red Tape's **Waste Oil and Coolant
Disposal** policy judges each month.

Global table: `RedTapeAPI`, in Red Tape's mod environment. Nothing in it throws: a bad call is
logged to the game log and returns `false, reason`.

## Split of work

- **Your mod** owns the waste: producing it, storing it, and how the player gets rid of it. It
  tells Red Tape what was disposed of, how and by which farm, and it can ask whether disposal is
  currently regulated.
- **Red Tape** owns the rule: when the policy is issued, the monthly evaluation, points, warnings
  and fines, and the report the player sees.

## 1. Find the API

```lua
local function getRedTapeAPI()
    if g_modIsLoaded == nil or not g_modIsLoaded["FS25_RedTape"] then
        return nil
    end
    local env = getfenv(0)["FS25_RedTape"]
    local api = env ~= nil and env.RedTapeAPI or nil
    if api == nil or type(api.getInfo) ~= "function" then
        return nil -- Red Tape older than this API
    end
    local info = api.getInfo()
    if info.version < 1 or not info.features.wasteDisposal then
        return nil
    end
    return api
end
```

Look it up from `loadMap` or later, not when your files are sourced: mods aren't guaranteed to be
loaded after Red Tape.

`getInfo()` returns a new table each call:

```lua
{
    version = 1,
    features = { wasteDisposal = true },
    wasteTypes = { "oil", "coolant" },
    disposalMethods = { "delivered", "collected", "discarded" },
}
```

`version` only goes up for a change a caller would notice. New features are added to `features`
without a version change, so check the feature flag as well as the version.

## 2. Register as a waste source

```lua
api.registerWasteSource("FS25_YourMod")   -- true, or false, "invalidSourceId"
api.unregisterWasteSource("FS25_YourMod") -- true, or false if it wasn't registered
```

The Waste Disposal policy is only issued while at least one source is registered, so a savegame
without a mod that reports disposals never gets it. Call `registerWasteSource` from `loadMap`, on
every machine. Registering twice is harmless, and registrations last for the game session.

If the player switches your waste handling off, call `unregisterWasteSource`. Red Tape then stops
issuing the policy. If it's already active, it stays active but judges nothing: its monthly report
says no mod is reporting waste, and any warnings are cleared.

## 3. Report disposals (server only)

```lua
local ok, reason = api.recordWasteDisposal(farmId, wasteType, liters, method)
```

| Argument | Values |
|---|---|
| `farmId` | The farm the waste belongs to: a whole number, 1 or above. |
| `wasteType` | `"oil"`: waste engine, transmission and hydraulic oil. `"coolant"`: used coolant. |
| `liters` | Litres disposed of: a number above 0. Fractions are fine. |
| `method` | How it left the farm, see below. |

| `method` | Meaning | Policy effect |
|---|---|---|
| `"delivered"` | The farm took it to an approved site (a dealer, a collection point). | A month with any delivery and nothing discarded earns points. |
| `"collected"` | An approved collector fetched it from the farm. | Legal. Earns nothing on its own. |
| `"discarded"` | Got rid of illegally: dumped, poured away, burnt. | A warning, then a fine per litre, and lost points (section 5). |

Call it once for each disposal, as it happens, whether or not the policy is active. Red Tape
decides what counts. Several calls in a month add up.

Returns `true`, or `false` and one of:

| Reason | Cause |
|---|---|
| `notServer` | Called on a client. Only the server's records count. |
| `notReady` | Red Tape hasn't finished loading the mission. |
| `invalidFarm` | `farmId` isn't a whole number of 1 or more. |
| `invalidWasteType` | Not one of `getInfo().wasteTypes`. |
| `invalidLiters` | Not a finite number above 0. |
| `invalidMethod` | Not one of `getInfo().disposalMethods`. |

Red Tape saves the month's records with the savegame and clears them at month end, after the
evaluation.

## 4. Ask whether disposal is regulated

```lua
local regulated = api.isWasteDisposalRegulated(farmId)
```

`true` while the Waste Disposal policy is active and enforced: the policies system is on, the
policy's own setting is on, and the policy has been issued. Works on the server and on clients,
so it can drive UI. `farmId` is accepted for the future. Today policies apply to every farm alike,
so the answer is the same for all farms. It can change at any month end and whenever the server
changes Red Tape's settings, so check it each time you need it rather than caching it.

Use it to decide whether to offer something that only makes sense under the rule. For example,
an illegal option can be offered only while it's regulated, so there's something to break.
Without the policy, a disposal reported as `"discarded"` is still accepted and simply has no
effect.

## 5. How the policy judges a month

Evaluated monthly, per farm, on that farm's records for the month just ended:

| The month | Result |
|---|---|
| Something discarded, first offence, 400 L or less | A warning. -5 points per 100 L discarded (rounded away from zero). |
| Something discarded, with a warning already on record | A fine of 2 per litre discarded. The same points loss. |
| More than 400 L discarded | Fined straight away, with no warning first. The same points loss. |
| Nothing discarded, something delivered | +10 points. Warnings cleared. |
| Nothing discarded, nothing delivered | No points, except for a farm in the lowest tier (D). Warnings cleared. |

The figures are Red Tape's to tune and aren't part of the contract. The report shows the litres
of oil and coolant for each method, then the points.

## Changes

- **v1**: first version. Waste disposal: `getInfo`, `registerWasteSource`, `unregisterWasteSource`,
  `isWasteDisposalRegulated`, `recordWasteDisposal`.
