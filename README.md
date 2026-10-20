# FS25_RedTape

The mod brings more complexity and realism to the game through 3 systems: policies, schemes and taxes. 

Policies are requirements that reflect many real life things farmers need to do, such as not contaminating water sources, and taking good care of animals. Compliance with policies is currently measured in a points based system, but depending on feedback this may also involve financial benefits/fines.

Schemes are somewhat similar to policies, but are entirely optional. An example might be that the government want to promote a specific crop.
If you join the scheme, you could be given equipment such as a a harvester and cash bonuses for crops grown. The quality of schemes and rewards is impacted by your policy compliance rating.

Tax is like real life. If you make profits, some will go to the government. Plan carefully to avoid tax. Losses can rollover between years which can help with your tax burden.

I am aiming to get the mod into a small testing group by November and release something by Christmas.

## Roadmap

Some rough plans are:

- More schemes (send me your ideas)
- More policies (as above)
- A system to apply for Grants, e.g. to help towards a new cow shed
- Long term: random events, e.g. your tractor was stolen.

## For mod authors: registering tax statistics

Red Tape only puts money on the tax statement if it knows which finance statistic it belongs to.
Anything else is logged as "Uncategorised" and left off. If your mod has its own finance
statistics (insurance, loans, contracts, ...), register them so they're taxed correctly:

```lua
-- Call from loadMap or later, on every machine (server and clients).
-- Don't call at file load: your mod may be loaded before Red Tape.
if RTTaxSystem ~= nil and RTTaxSystem.registerTaxStatistic ~= nil then
    RTTaxSystem.registerTaxStatistic("myModPremium", "expense")
    RTTaxSystem.registerTaxStatistic("myModPayout", "income")
end
```

`kind` is one of:

- `"expense"` - deducted from taxable profit.
- `"income"` - counted as taxable income.
- `"ignore"` - deliberately left off the tax statement, without the warning.

The function returns `true` if the statistic was registered. It logs a warning and returns `false`
for an invalid statistic or kind, or for a statistic Red Tape already categorises (its own
categories can't be overridden).

Money types using the `"other"` statistic aren't covered by this; use a statistic of your own.

## Discord

[![Discord](https://img.shields.io/discord/1415966930799693847?logo=discord)](https://discord.gg/eGyACAan)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/M4M41K5NPV)