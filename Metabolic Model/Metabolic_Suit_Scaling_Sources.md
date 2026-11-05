# EVA suit metabolic allowance

Three independently editable activity-only factors replace the single allowance: `Suit.LightFactor`, `Suit.ManualFactor`, and `Suit.WalkingFactor`. All default to 1.20 as preliminary assumptions, not literature-calibrated coefficients.

| Current label | Task class | Gravity factor | Suit factor |
|---|---|---|---|
| Nominal | Light | 1 | LightFactor |
| Above Nominal | Manual | 1 | ManualFactor |
| Exercise - Resistance | Manual | 1 | ManualFactor |
| Exercise - Aerobic | Walking (assumed traverse proxy) | C_w_M / C_w_E | WalkingFactor |

`M_physical = M_rest + k_task * K_g_task * max(M_mapped - M_rest, 0)`.

RestingMetabolicRate_W = 316/3.6 = 87.78 W is the BVAD sleep-rate proxy, not a measured basal metabolic rate. NominalMetabolicRate_W = 500/3.6 = 138.89 W is the separate awake reference used by the LCG cooling allocation (BVAD Rev. 2, Tables 3-24/3-25, printed p. 49). The resting component is unchanged by task corrections. At LightFactor = 1.2, nominal activity becomes 149.11 W before FOS (164.02 W with FOS = 1.1). Only walking uses the existing speed/gravity relation. The suit multiplier now acts on gravity-adjusted activity, replacing the former additive Earth-activity penalty. The source mapping still defines Above Nominal as 80% of the resistance source rate. Unknown task labels raise an error. Metabolic_Task_Mapping exposes the classification, factors and rates for every input row.

## Evidence and interpretation

- Carr and Newman (2007), *Space suit bioenergetics: framework and analysis of unsuited and suited activity*, DOI: 10.3357/asem.1952.2007. https://pubmed.ncbi.nlm.nih.gov/18018432/ identifies pressure, gravity, speed, slope and suit configuration as drivers. This supports modelling a suit contribution, but does not establish 20% as a common constant.
- Diaz-Artiles et al. (2019), *SmartSuit: Hybrid, Intelligent, and Highly Mobile EVA Spacesuit for Next Generation Exploration Missions*, NASA NIAC Phase I report, Table 1, p. 15. https://www.nasa.gov/wp-content/uploads/2019/04/niac_2019_phi_diazartiles_smartsuit_tagged.pdf reports simulated walking expenditures of 556 kcal/h unsuited, 957 in the EMU and 842 in SmartSuit. Ratios imply approximately 72% and 51% higher total expenditure respectively. These are simulation-specific walking results, not measured Mars EVA multipliers; they show why 20% cannot be described as conservative for every suit/task.
- Kluis and Diaz-Artiles (2021), *Revisiting decompression sickness risk and mobility in the context of the SmartSuit, a hybrid planetary spacesuit*, npj Microgravity 7, 46. https://doi.org/10.1038/s41526-021-00175-3 examines pressure and assistance effects on mobility/metabolic expenditure. Its suit-specific simulations further support pressure/mobility dependence, rather than a universal allowance.

Retaining 20% is defensible only as an explicit placeholder for an unspecified future suit during preliminary trades. Validate it using matched suited/unsuited tasks at representative pressure, gravity, speed and carried mass. Exploratory factors 1.0, 1.2, 1.5 and 1.75 can expose sizing dependence; these are analyst-selected scenarios, not confidence bounds. Avoid adding the allowance to source profiles already measured during suited EVA.

## Scope in this script

JOS-3 now receives PhysicalMetabolicRate_W so task corrections affect moisture, air temperature and downstream RH hardware sizing. DesignMetabolicRate_W includes FOS for the displayed design metabolic summary. FOS is not fed into physiology; it continues to scale the simulated moisture requirements separately. The source metabolic profiles remain available for comparison. These corrections assume the mapped input rates do not already contain an EVA suit penalty.

Activity-only factors previously derived by subtracting 143 W must be recalculated before use with the new resting reference. The current factors remain assumed 1.20 values. JOS-3 retains its own physiological basal-rate calculation; the sleep proxy changes profile scaling only.


## 95th-percentile male input case

The active human case now uses BVAD Rev2 (February 2022), printed pp.48 and 50 (PDF pp.62,64): height 1.84 m, mass 100 kg, high fitness VO2max 55 mL/kg/min. Table 3-26 supplies sleep 367 and nominal awake 580 kJ/h (101.9444 and 161.1111 W). Sleep remains a resting-rate proxy, not an independently measured waking basal rate. Suit factors, FOS, EVA schedule, suit environment and LCG settings are independent engineering assumptions, not anthropometric percentiles, and are unchanged.

Both Metabolic.xlsx copies now use the complete 95th-percentile METMAN output from BVAD Rev1 (January 2018; Literature/20180001338.pdf), printed p.53, Tables 3-27/3-28. Exercise rates are 5197 kJ/h aerobic and 1452 kJ/h resistance. All seven output columns (metabolism, sensible, latent, water vapor, sweat, oxygen and carbon dioxide) were transcribed, including three successive 15-minute aerobic intervals, three resistance intervals, and three recovery intervals. The existing time grid is retained, but its activity labels now reflect that published 45/45-minute exercise protocol. The remaining nominal rows use Rev1 steady-state awake outputs consistently with that table. Rev2 revised steady-state heat/moisture and respiratory values, so the workbook explicitly identifies Rev1 instead of mixing editions within a row. Rev2 has no complete percentile exercise/recovery table. Neither source gives a 95th-percentile age, body-fat percentage or cardiac index: those remain explicitly marked JOS-3/scenario assumptions (30 years, 15%, 2.59 L/min/m2). Generic JOS-3 defaults and coefficients remain library reference values, not the active astronaut inputs.

The separate Raw_Nominal.csv EVA activity schedule is unchanged. Its numeric historical metabolic series remains a labelled raw comparison; the calculated profile maps its activity labels to the new lookup. The main model consumes only metabolic power from this sheet and recomputes heat/moisture through JOS-3 at the new size, rather than importing cabin sweat/vapor into the suit. No additional mass or fitness multiplier is applied to these already-percentile metabolic rates. NMP_RBDM also uses the updated workbook and its resting proxy is updated to 367/3.6 W. The root workbook's existing hardcoded daily totals were replaced by integrated totals over its actual 16-hour schedule, labelled accordingly. Lunar EVA historical comparison rates are retained as historical data, not relabelled as percentile predictions.


## Explicit off-nominal design case replaces scalar safety factors
The active nominal metabolic profile and RH source handoff no longer multiply metabolic power or moisture by scalar safety factors. The separate off-nominal case preserves the EVA timeline up to EVA end minus OffNominalAerobicDuration_min (default 120 min), then applies the mapped 95th-percentile aerobic rate continuously until EVA end. The aerobic task retains its physical suit-resistance and Mars walking-proxy gravity corrections; these are physical modelling assumptions, not safety factors. The source lookup workbook and raw EVA schedule are unchanged.

Both scenarios run JOS-3 independently with continuous body/sweat/condensate history through the activity change. The off-nominal scenario supplies the entire actual profile to the component sizing search, including its own temperatures, humidity ratios and moisture. The summary's former margin column is replaced by OffNominal_W next to Nominal_W. Figure 2 retains nominal output; figure 10 compares both scenarios' metabolism, net vapor to PLSS and suit outlet temperature. Other sizing/performance figures and the moisture/air summary now describe the off-nominal design case. Separate profiles remain in Nominal_Moisture_Profile and OffNominal_Moisture_Profile. RH moisture sensitivity perturbations are retained as sensitivity experiments, not design margins. The legacy NMP_RBDM script also no longer applies its scalar safety factor.

The two-hour aerobic extension is an engineering off-nominal scenario requested for this design, not a demonstrated sustainable suited workload or a BVAD protocol. No physiological safety or endurance conclusion follows from numerical completion.
