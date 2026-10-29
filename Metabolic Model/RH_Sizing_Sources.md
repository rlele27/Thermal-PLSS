# RH sizing basis, full EVA cases and limitations

Run `Nominal_Metabolic_Profile.m` for both the metabolic model and RH sizing. The script has explicit constants, input, settings, calculation, table and graph sections. Mean outlet conditions and the full `EVA_Profile` pass directly in memory; the former `RH_Inputs.xlsx` transfer and standalone `RH_Sizing.m` are removed. Existing equations, fixed-profile search coupling and numerical outputs are unchanged. `sizeEVARH.m` remains the full-EVA sizing helper.

The separate `RH_Component_Sizing.m` still reads `RH_Component_Inputs.xlsx`, which the merged script produces. That final component handoff has not been removed. The fixed-flow RH figures retain numbers 2–3, and the five metabolic graphs occupy 5–9. The airflow map and search graph have been removed.

## Literature and property basis

| Quantity | Reference and implementation |
| --- | --- |
| Channel geometry | [Althausen et al., AIAA 2006-1337](https://doi.org/10.2514/6.2006-1337), printed p. 4. Listed 0.08 inch gap, 0.07 inch fins, 0.7 inch height and 1.72 inch length give aspect ratio 0.114286 and hydraulic diameter 3.64718 mm. The inconsistent stated ratio 0.05 is not used. |
| Gas heat transfer | [Maya HTT constant-temperature rectangular-duct validation](https://help.mayahtt.com/tmg/topics/validation/VVC6_forced_convection_in_rectangular_duct.html). Fully developed laminar Nu polynomial and h = Nu*k/Dh. Sh = Nu is the corresponding dilute-species, constant-wall-value analogy. No entry-enhancement area credit is used. |
| Fin theory | [F-Chart/Nellis and Klein fin-efficiency documentation](https://www.fchart.com/ees/heat_transfer_library/fin_efficiency/hs1.htm). The dry analytical benchmark is eta = tanh(mL)/(mL). The implemented wet fin additionally solves sensible and latent loading along the fin rather than applying dry efficiency to all condensation. |
| Conductivity reference | [POCO HTC porous graphite datasheet](https://poco.entegris.com/content/dam/poco/resources/reference-materials/data-sheets/datasheet-htc-graphite-10231.pdf) gives 70 W/m/K in plane and 245 W/m/K out of plane. **The selected 70 W/m/K is an editable proxy, not verified PG-45 conductivity.** Grade, orientation, wetting and thermal contact must be confirmed. PG-45 permeability/bubble data do not establish its conductivity. |
| Free gas volume | [NASA EMU Hardware Data Book](https://www.nasa.gov/wp-content/uploads/2017/02/esoc-13_rev._v_emu_hardware_data_book_jsc-e-daa-tn55224.pdf), section 1.5.5, gives 1.5–2.0 ft3 including the ventilating circuit. Default is the lower 1.5 ft3 = 42.48 L, an editable analogue for this project. Equal allocation among three nodes is an assumption. |
| Water rho, cp and viscosity | [IAPWS SR6-08(2011)](https://iapws.org/technical-guidance/release/LiquidWater.download), Eq. 2, Eq. 7, Tables 1–2, at cooled-root/drain temperature. Density and cp use 0.1 MPa correlations as a low-pressure approximation. |
| Surface tension | [IAPWS R1-76(2014)](https://iapws.org/technical-guidance/release/Surf-H2O.download). Reported bubble pressures scale with operating/reference surface-tension ratio, assuming unchanged wettability. |
| Ceramic separator | [Hasan et al., NASA/TM-2006-214130](https://ntrs.nasa.gov/api/citations/20060021945/downloads/20060021945.pdf), printed pp. 4–5. Average pore size 6.7e-5 inch, hydraulic conductivity 7.56e-7 cm/s, approximate entry pressure 14.7 psi. The paper uses psi/psia wording; interpreting the bubble point as a differential limit needs confirmation with the selected part. |
| PG-45 reference | Same NASA paper: average pore size 0.0023 inch and measured entry pressure about 0.6 psi. Average pores are descriptive, not maximum diameters used to infer bubble pressure. |
| Separator permeability | k = K*mu/(rho*g), using an assumed 20 C reference test-water temperature because the paper does not specify it. k is approximately 7.735e-16 m2. |
| Oxygen transport | [NIST Shomate cp](https://webbook.nist.gov/cgi/cbook.cgi?ID=C7782447&Mask=1), [Lemmon/Jacobsen dilute transport](https://trc.nist.gov/refprop/FAQ/NAO.PDF), and [Fuller diffusivity formulation](https://catalogimages.wiley.com/images/db/pdf/0471464805.ch3.pdf), Eq. 3-36/Table 3.1, O2/H2O diffusion volumes 16.3/13.1. Humid-gas viscosity and conductivity remain dilute-O2 approximations. |

## Wet fin and coil model

The selected 1 C temperature is now the **two fin-root temperatures**, not the temperature of the whole fin. Both top and bottom fin roots are assumed perfectly connected to cooling. Solve half the 17.78 mm height with an insulated symmetry plane. Constant conductivity, 12 conduction intervals and negligible through-thickness temperature gradient are assumed.

The steady equation per unit channel length is `k*t*T'' + 2*h*(Tgas-T) + 2*hfg*rho_dry*km*max(wgas-wsat(T),0) = 0`. A tridiagonal Newton iteration solves the temperature-dependent saturation term. Vapor condensation stops locally where its driving difference is negative; no artificial condensation is imposed on a dry region. The root remains 1 C. Sensible and mass efficiencies are calculated separately from the solved temperature profile, then weighted with the isothermal top/bottom channel base areas. Report both dry analytical efficiency and wet total-heat fin efficiency.

Inlet gas conditions set these effective efficiencies. Along-channel changes in fin temperature, film properties and wetting are not resolved, and the fin-root cooling connection itself is still assumed. Fin efficiency therefore improves the previous isothermal-wall model without validating the physical cooling assembly.

Mass-transfer area uses `A = -Q/(km*eta_mass)*log(1-removal/maximum_removal)`. Outlet temperature uses the sensible NTU with h*eta_heat. Cooling is moist-gas enthalpy loss minus liquid enthalpy at the root temperature. Heat duty is thermal load, not refrigeration electrical input. Gas volume and properties remain fixed at inlet values for each interval.

If this simplified coil model predicts bulk outlet RH above 100%, its wall-transfer area and formal thermal duty are retained as **provisional requirements**, with the design flagged invalid for a demonstrated vapor-only outlet. Fog transport/capture is not assumed or silently credited. Such a flag does not prove the proposed hardware can never work; it identifies physics that must be validated before accepting its size.

Straight-channel Darcy friction is calculated from the rectangular Poiseuille relation. It excludes entrances, offsets, headers and wetting/flooding losses. Re >= 2300 is rejected. The entry-length warning remains a correlation-domain diagnostic, without an area reduction.

## Full EVA sizing

The in-memory `EVA_Profile` contains all 960 half-minute intervals of the current eight-hour EVA, with physical and FOS-adjusted net vapor, pressure, dry oxygen flow, supply humidity ratio and regional mean/outlet air states. Interval states are coincident; independent peaks are not combined. The source is the existing net vapor reaching PLSS after the original suit condensation/re-evaporation calculation. Mars metabolic adjustment is not applied to moisture. FOS is included once.

**Peak case:** calculate area and thermal duty for every interval at its original physical inlet state and FOS-adjusted water requirement. Maximum required area sets the channel count; maximum thermal duty sets refrigeration capacity; maximum water rate sets the separator and extraction pump. These maxima can occur in different intervals. Average thermal power uses the time integral, and water storage uses integrated generated water, not peak rate times eight hours. The original air profile is not a 65%-RH-controlled profile.

**65% case:** integrate three serial finite gas inventories, representing neck, torso and legs. Dry oxygen circulates from the condenser to neck, torso, legs and back. Regional net moisture sources are reconstructed from the original JOS-3 outlet humidity increments and scaled by FOS. The original node temperatures are prescribed. Equal node gas volumes and fixed reference dry-gas inventories are assumed; initial bulk RH is 50%. The condenser runs continuously, without active humidification. Check RH at every modelled regional air node, supply and final return.

For each node, `M_dry*dw/dt = mdot_dry*(w_in-w) + source`. Step size is at most 1 s and 0.2 of the smallest node residence time. The condenser mass effectiveness is based on its fin-corrected area. Fin/transport coefficients for this transient case are evaluated once per interval at the 65% return reference state, rather than recomputed every substep.

First test **ideal infinite area and a saturated 1 C return from the condenser**. This is a favorable sink bound independent of fin efficiency. If it already exceeds 65%, do not invent a finite area. If it meets 65%, bracket and bisect area and rerun the complete humidity history to identify a finite size. Any retained vapor changes actual collected liquid through the transient mass balance.

This is a one-way RH design study. It does not rerun JOS-3 evaporation, sweat retention, air heating or wall condensation as humidity changes. It checks modelled bulk-air nodes, not humidity inside the garment or every physical pocket in the suit. Predictions after a 65% breach are not accepted operating states; the plotted ideal trace stops at the first breached interval, and an unconstrained supersaturation indicator is not reported as an actual humidity maximum.

## Remaining drain assumptions

Equivalent separator thickness 1 mm, permeability retention 50%, suction 8 kPa, bubble-pressure FOS 2, minimum liquid pressure 10 kPa and routing allowance 500 Pa remain labelled engineering assumptions. Selected parts must confirm wetting, priming, drainage paths, conductivity, permeability, gas breakthrough and oxygen compatibility. A pressure allowance does not replace a porous-reservoir flow-distribution model.

## Current results and verification

At the average inlet state: required area 0.02711 m2, wet fin efficiency 0.93595, mean fin temperature 3.153 C, warmest fin 4.224 C, and cooling duty 85.80 W.

Across the full EVA: peak wall-transfer requirement is 0.06617 m2, 39 channels, 43.688 x 150.368 x 17.78 mm gas-channel core, 0.11923 m2 liquid separator area, and 247.04 W formal peak cooling. Warmest fin is 7.423 C. Some outlet states predict fog, so these are provisional wall-transfer/hardware estimates, not an experimentally validated complete design. The 65% case has no finite size at the selected flow and 1 C roots under the stated source/temperature/inventory assumptions; the ideal sink first breaches the ceiling at approximately 94 minutes.

MATLAB checks cover fin-grid refinement (12/24 intervals), the infinite-conductivity/isothermal limit, source reconstruction, full-EVA mass balance, peak versus time-weighted average accounting, and correct integrated storage. Implementation checks do not replace experimental validation. Gas-volume and timestep robustness are checked separately.

Robustness checks: a 0.5 s maximum step and a 56.63 L gas volume both retain the current 65% infeasibility result, with the first breached interval at 93.5 minutes. An in-memory synthetic case with regional net sources reduced to 20% verifies the finite-area search branch: 0.013157 m2 gives maximum modelled suit RH 64.999996%. The actual workbook/profile was not replaced by this synthetic test.

## Fixed 6 ACFM configuration

The multi-CFM search and its helper program have been removed. The combined RH/airflow map, search-solution graph and +/-10% airflow curves are removed. Figures 2–3 now use only the configured supply flow, currently 6 ACFM, with the corresponding actual condenser-inlet flow calculated from the metabolic air state. The sensitivity calculation retains moisture, temperature, RH and surface-temperature cases, without airflow perturbations.

The original three-node, full-EVA fixed-flow humidity check remains. Current 6 ACFM data have approximately 1.563 g/min average and 5.123 g/min peak moisture, including FOS. The ideal 1 C sink still cannot maintain 65% at all modelled nodes for this full profile. No flow increase is selected automatically. The component workbook retains its other sheets; only the obsolete airflow-search results are cleared, with a short status note left in that worksheet.

For scale, using the earlier 6 ACFM peak return state near 31.67 C and 31.7159 kPa, a 65% RH return carries enough moisture for about 3.21 g/min net removal to an ideal saturated 1 C sink, or 4.01 g/min to a perfectly dry sink. These are single-state, steady carrying-capacity illustrations, not full-EVA sizing results. They show why deeper drying or extra area alone cannot be assumed to handle the current 5.12 g/min peak while holding 65% everywhere.

## Merge verification

Before removing the spreadsheet transfer, MATLAB captured numerical tables, all full-EVA states, component-input values, and line/contour data for both original scripts. The merged script reproduced those results within a 1e-9 relative/absolute numerical comparison tolerance, with all nine graph datasets retained. No physiological or condenser feedback was added by this reorganization.


## Fixed-flow selected condenser comparison
The minimum-area case uses the three-node full-EVA humidity inventory and the selected RH limit. No finite area is reported when the ideal sink already fails. The second case uses an editable 99% approach to the root-temperature humidity-ratio equilibrium limit, because exactly reaching that asymptote requires infinite transfer area. Its area is the largest interval requirement and is rounded up to whole channels. This percentage is a numerical design choice, not a literature requirement or a claim that peak astronaut generation can be removed.

Figure 8 compares the selected cases. Node temperatures and sources remain prescribed by JOS-3; condenser area changes humidity inventory, not the body thermal calculation. The condenser outlet temperature is an NTU estimate followed by assumed external reheat to the prescribed supply temperature. The inventory uses coefficients evaluated at the permitted return RH. Histories stop when any checked state exceeds saturation; full-EVA performance totals are withheld for such cases, because this inventory has no additional liquid/fog transport model. Saturation times in the summary identify the start of the affected profile interval. Cooling estimates do not validate mist capture. The displayed sensitivity table perturbs the average inlet state at fixed flow; it is not a repeated coupled EVA simulation.

The 65% RH requirement is currently disabled at the user's request. The minimum-area selection now checks only the 100% saturation ceiling at all modelled air states. This is a vapor-model validity boundary, not a comfort criterion; it does not add liquid-water transport to the RH inventory.

## Current selected-case reporting (supersedes saturation rejection above)
The first selected case now inverts the transfer equation for the EVA time-weighted average moisture generation at the representative average inlet state, then rounds up to whole channels. It is not sized to an RH ceiling. Both selected inventories continue over the full EVA even above 100% diagnostic RH. No saturation clipping is applied. Such values indicate missing condensation/liquid transport; associated removal totals and thermal duties are extrapolations, not validated physical performance.

Figure 8 shows one line per case: maximum RH across the three regional nodes, suit supply and return over each interval, including internal substeps. The plotted peaks match the summary maximum RH. PeakRemoval_g_min is the largest interval-average removal predicted by the unconstrained inventory. MaximumSaturatedCapacity_g_min is the largest installed-area transfer rate with return air limited to 100% RH at the prescribed interval return temperatures and conserved dry gas flow; it uses the existing fixed transfer coefficients and is a conditional estimate, not a rerun of the body model. AverageRemoval_g_min and collected mass cover the full EVA including recovery.

## Condenser-exit air reporting
The selected-condenser comparison includes time-weighted average and peak gas temperature and RH directly after the cold condenser, before external reheating. Temperature uses the existing sensible NTU calculation. The humidity inventory accumulates the mean and maximum condenser-outlet vapor pressure during each interval; these pressures are divided by saturation pressure at that interval's calculated cold-outlet temperature. Mean RH is weighted by interval duration; peaks include internal steps and interval-end states. Gas pressure is the existing suit-pressure approximation. RH above 100% is left visible as a fog/condensation diagnostic; no new mist transport, saturation adjustment or latent heat correction is introduced.
