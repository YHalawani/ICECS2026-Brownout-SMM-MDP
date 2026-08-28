# Model definition

This document records the numerical model specification implemented by the MATLAB code.

## Workload

MMASH annotations are mapped to three physiological states:

- **SLEEP** — activity code 1 or a `sleep.csv` in-bed interval.
- **LOW** — activity codes 2--4.
- **HIGH** — activity codes 5--6.
- Activity codes 7--13 represent concurrent diary events and are not treated as separate physiological states.

The analysis uses the full 22-user MMASH cohort. The timeline uses 60 s intervals, with sleep intervals overriding activity annotations. A correct full-cohort extraction gives:

| Quantity | SLEEP | LOW | HIGH |
|---|---:|---:|---:|
| Occupancy | 26.54% | 65.67% | 7.79% |
| Mean dwell (s) | 16912.0 | 8777.6 | 1551.2 |

Empirical dwell durations are sampled during Monte Carlo evaluation. Value iteration uses the corresponding mean dwell duration.

The observed physiological transition matrix is first obtained from the mapped MMASH timeline. Because state persistence is represented separately by the empirical dwell-time distributions, self-transitions are removed when constructing the exit-transition matrix:

`Pexit(i,j) = Pphys(i,j)/(1 - Pphys(i,i))`, for `i ~= j`

and

`Pexit(i,i) = 0`.

Thus, `Pexit` determines the next physiological state after the current dwell ends.

Requested transmissions are modeled as a Poisson overlay. For a dwell of duration `dwell` and an action-dependent TX period `action_TX_period`, the requested TX count has mean

`dwell / action_TX_period`.

The nominal TX periods for A1 are `[300 120 60]` s for SLEEP / LOW / HIGH.

## Firmware actions

Vectors are ordered SLEEP / LOW / HIGH.

| Action | State power (mW) | Relative sensing service S | TX service T | Utility u | State peak current (mA) |
|---|---:|---:|---:|---:|---:|
| A0 | `[0.024 0.024 0.024]` | `[0 0 0]` | `[0 0 0]` | 0 | `[0.01 0.01 0.01]` |
| A1 | `[0.024 1.880 14.10]` | `[1 1 1]` | `[1 1 1]` | 1 | `[0.01 1 20]` |
| A2 | `[0.224 2.880 15.10]` | `[1 1 1]` | `[1 1 1]` | 1.10 | `[0.01 1 20]` |
| A3 | `[0.024 1.930 14.15]` | `[1 1 1]` | `[0.33 0.33 0.33]` | 1 | `[0.01 1 20]` |
| A4 | `[0.224 2.580 14.80]` | `[1 1 1]` | `[0.17 0.17 0.17]` | 1.10 | `[0.01 1 20]` |
| A5 | `[0.024 2.380 15.10]` | `[1 1 1]` | `[0.20 0.50 2.00]` | 1 | `[0.01 1 20]` |
| A6 | `[0.024 1.410 7.755]` | `[1 0.75 0.55]` | `[0.25 0.35 0.50]` | 1 | `[0.01 0.70 9]` |

The absolute values in the table above are the authoritative action values used by the model.

A1 defines the nominal reference vectors

`P0 = [0.024 1.880 14.10] mW`

and

`I0 = [0.01 1 20] mA`.

The nominal baseline loads are system-level battery-side abstractions based on representative component operating conditions. They are not measured current waveforms from a fabricated prototype.

A2--A6 define a discrete set of predefined firmware choices relative to A1. Their processing-power increments, sensing-service factors, TX-rate factors, and peak-current changes are engineering modeling assumptions. They were fixed as part of the design space and were not fitted to the reported simulation results.

- **A0 — Monitoring fallback.** Uses the low-power SLEEP floor in all three states and provides no useful monitoring service, so `S = T = u = 0`.

- **A1 — Nominal sense-send.** Uses the nominal state power and peak-current vectors. By definition, its relative sensing service, TX service, and utility are all one.

- **A2 — Processing.** Adds `[0.20 1.00 1.00]` mW to the nominal state-power vector while retaining nominal sensing service, TX service, and peak current. The utility multiplier is `u = 1.10` to represent the additional value assigned to local processing.

- **A3 — Aggregation.** Adds `[0 0.05 0.05]` mW of aggregation/buffering overhead and requests approximately one-third of the nominal TX service, `T = [0.33 0.33 0.33]`.

- **A4 — Processing with stronger aggregation.** Adds `[0.20 0.70 0.70]` mW and requests approximately 17% of nominal TX service, `T = [0.17 0.17 0.17]`. The utility multiplier is `u = 1.10`.

- **A5 — Event-alert mode.** Adds `[0 0.50 1.00]` mW. Requested TX service is `[0.20 0.50 2.00]`, representing lower routine TX activity in SLEEP/LOW and twice the nominal TX rate in HIGH.

- **A6 — Reduced sensing load and peak current.** State power is obtained from the nominal vector using the dimensionless power multipliers `[1 0.75 0.55]`. Its dimensionless peak-current multipliers are `[1 0.70 0.45]`, which give the absolute peak-current vector `[0.01 0.70 9]` mA. The predefined relative sensing-service values are `[1 0.75 0.55]`, and TX service is `[0.25 0.35 0.50]`.

The A6 sensing-service factors are composite relative sensing-service assumptions. They do not represent a specific physical duty-cycle law and are not derived from the power multipliers, peak-current multipliers, SNR, or measured clinical sensing quality.

The relative service score is

`Q = u * (0.60*S + 0.40*T)`.

`S` is the predefined relative sensing-service factor.

`T` is the requested transmission service relative to A1 in the same physiological state. It is not capped at one, which allows the A5 HIGH-state value `T = 2`.

`u` is an action-level utility multiplier. It provides additional service credit to the processing modes A2 and A4 rather than defining a separate service dimension.

The coefficients 0.60 and 0.40 are service-value weights, not energy proportions.

Voltage-warning suppression modifies delivered sensing or TX service before the resulting service value is evaluated.

## Battery model

The battery specification combines datasheet-grounded quantities, derived quantities, and modeling assumptions.

- **`Vnom`** — nominal battery voltage, `Vnom`, in V. It defines the full-charge OCV endpoint `Voc(1) = Vnom` and is also used when converting average power to average current.

- **`Enom`** — nominal stored energy, `Enom`, in Wh. It defines the initial battery-energy budget. It is calculated as

  `Enom = Vnom * Cnom / 1000`

  where `Cnom` is the rated battery capacity in mAh.

- **`Rint`** — representative internal resistance, `Rint`, in ohm. It determines the modeled voltage drop under current load.

- **`n`** — dimensionless Peukert-like rate-derating exponent. Larger values produce a stronger increase in effective energy use at currents above the reference current.

- **`Iref`** — reference current, `Iref`, in mA. It is used in the Peukert-like correction and in anchoring the empty-cell OCV endpoint.

- **`Vwarn`** — warning loaded-voltage threshold, in V. It determines when warning-level sensing or TX suppression is applied.

- **`Vmin`** — adopted minimum loaded-voltage/cutoff threshold, in V. It determines sensing-state action feasibility and voltage-related termination.

The nominal voltage and rated-capacity values are based on representative battery datasheets. `Enom` is derived from those quantities.

For the rechargeable LIR cases, the selected internal-resistance values use reported impedance limits. For the CR2032 and CR1632 cases, the internal-resistance values are representative modeling assumptions and are examined separately through resistance sensitivity analysis.

The Peukert-like exponent `n`, warning threshold `Vwarn`, and the interior OCV shape are modeling parameters. `Vmin` is the adopted minimum/cutoff threshold for the corresponding battery case rather than a measured operating threshold of a fabricated patch.

| Battery | Vnom (V) | Enom (Wh) | Rint (ohm) | n | Iref (mA) | Vwarn (V) | Vmin (V) |
|---|---:|---:|---:|---:|---:|---:|---:|
| LIR2450 | 3.7 | 0.370 | 0.40 | 1.03 | 20 | 3.3 | 3.0 |
| LIR2032H | 3.7 | 0.222 | 0.65 | 1.03 | 12 | 3.2 | 2.75 |
| CR2032 | 3.0 | 0.705 | 18 | 1.08 | 0.19 | 2.4 | 2.0 |
| CR1632 | 3.0 | 0.390 | 30 | 1.09 | 0.19 | 2.4 | 2.0 |

### Rate-dependent energy use

Effective energy use is multiplied by the Peukert-like factor

`fP(I) = max(1, (I/Iref)^(n-1))`.

The factor is clamped at one so that operation below the reference current cannot artificially increase the modeled battery capacity.

For state energy, `I` is the average state current calculated from state power and nominal battery voltage:

`Istate_avg = Pstate / Vnom`.

For TX energy, `I` is the event-average TX current calculated from TX event-average power and nominal battery voltage:

`Itx_avg = Ptx / Vnom`.

These average currents are used only for the Peukert-like energy correction. The separate peak currents are used for loaded-voltage checks.

### Open-circuit voltage

The empty-cell open-circuit endpoint is

`Voc(0) = Vmin + (Iref/1000)*Rint`.

The full-charge endpoint is

`Voc(1) = Vnom`.

The interior OCV--SoC curve is piecewise linear with a knee at SoC `0.35`. A fraction `0.65` of the total modeled voltage rise occurs below this knee.

For SoC `s`,

`g(s) = 0.65*s/0.35`, for `s < 0.35`

and

`g(s) = 0.65 + 0.35*(s - 0.35)/(1 - 0.35)`, for `s >= 0.35`.

The open-circuit voltage is then

`Voc(s) = Voc(0) + (Vnom - Voc(0))*g(s)`.

The knee value `0.35` and lower-region voltage-span fraction `0.65` are modeling assumptions rather than measured battery discharge-curve characteristics.

### Loaded voltage

State and TX current peaks are assumed not to overlap. Their loaded voltages are therefore evaluated separately:

`Vstate = Voc(s) - (Istate_peak/1000)*Rint`

and

`Vtx = Voc(s) - (Itx_peak/1000)*Rint`.

The TX peak current is 12 mA.

Each TX event uses:

- event-average TX power: `14.1 mW`;
- duration: `0.05 s`;
- startup energy: `2 mJ`;
- TX peak current: `12 mA`.

These are system-level model parameters. They are not measured prototype waveforms.

### Worked voltage check

For CR1632,

`Voc(0) = 2.0 + (0.19/1000)*30 = 2.0057 V`.

For A1 in HIGH, the sensing-state peak current is 20 mA. The internal-resistance voltage drop is therefore

`(20/1000)*30 = 0.600 V`.

Hence,

`Vstate = Voc(s) - 0.600 V`.

At full charge,

`Voc(1) = 3.0 V`,

so

`Vstate = 3.0 - 0.600 = 2.400 V`.

This is exactly equal to the CR1632 warning threshold `Vwarn = 2.4 V`.

Because the warning condition uses `Vstate <= Vwarn`, A1 in HIGH is already at the warning boundary at full charge and remains in the warning region as SoC decreases until the minimum-voltage limit is reached.

This check is useful for detecting mA-to-A conversion errors in an independent implementation.

### Warning and minimum-voltage behavior

State and TX voltage conditions are evaluated separately.

When

`Vstate <= Vwarn`,

sensing service is suppressed by 50%. The corresponding state power is moved halfway from the selected state power toward the SLEEP-state power floor:

`Pstate_eff = 0.5*Pstate + 0.5*Psleep`.

Separately, when

`Vtx <= Vwarn`,

50% of the requested TX events are suppressed.

When

`Vstate <= Vmin`,

the sensing-state load is not physically supportable and useful monitoring terminates.

When

`Vtx <= Vmin`,

the affected TX is fully suppressed, but monitoring continues.

No independent fixed-SoC warning or termination threshold is used.

### Termination classes

The Monte Carlo evaluator records three mutually exclusive termination classes:

1. **State-load minimum-voltage violation.**  
   An active action A1--A6 is selected, but at the simulator's continuous SoC its sensing-state loaded voltage satisfies `Vstate <= Vmin`. Useful monitoring therefore terminates immediately.

2. **No active monitoring action attainable.**  
   For the brownout-aware policy, every active action A1--A6 is excluded from the admissible set at the corresponding solver energy state because its sensing-state loaded voltage satisfies `Vstate <= Vmin`. A0 is therefore the only policy choice, and selecting A0 during evaluation terminates useful monitoring.

3. **Energy depletion.**  
   The sampled dwell requires more state-plus-TX energy than remains in the battery. The simulator then has `active_fraction < 1`. Monitoring time, delivered TX, and QoS are credited only for that completed fraction of the dwell, after which the remaining battery energy is exhausted and the run terminates.

## MDP

The MDP state consists of remaining battery energy and physiological state.

The main analysis uses

`N_E = 800`

battery-energy grid states and

`gamma = 1`.

Value iteration stops when the maximum absolute change in the value function is below

`1e-6`

with a maximum of

`25000`

iterations.

The brownout-aware solver excludes an active action when its sensing-state loaded voltage satisfies

`Vstate <= Vmin`.

The brownout-blind solver does not apply this voltage-feasibility mask during optimization.

A0 is the terminal physical fallback used when no active monitoring action remains attainable.

**Important evaluation rule:** "blind" refers only to the optimization step. Both blind and aware policies are physically evaluated using the same loaded-voltage and brownout model. Thus, a blind policy may select a mode that was allowed by its optimizer but violates the physical loaded-voltage limit during evaluation.

For completed monitoring time `t` in hours, the immediate reward is

`t * (1 + lambda*Q)`.

No additional voltage-headroom reward penalty is used. Warning conditions affect the modeled energy consumption and delivered service, while sensing-state minimum-voltage violations determine action feasibility.

Continuous post-action battery energy is not rounded to a complete grid interval. Future value is obtained by linear interpolation between the adjacent battery-energy grid states.

If the available battery energy supports only part of an expected dwell, the completed fraction scales the monitoring-time and QoS reward, and no future value is credited after depletion.

### Energy-grid sensitivity

Grid sizes

`N_E = [200 400 800 1600]`

were evaluated.

Between `N_E = 800` and `N_E = 1600`, the maximum change across the CR1632 lambda sweep was:

- lifetime: `1.46%`;
- TX rate: `0.93%`;
- overall QoS: `0.47%`.

These values are within the predefined 2% convergence criterion for the reported performance metrics.

At `N_E = 400`, the matched-service analysis selected the same headline policy pairs as at `N_E = 800`, although the estimated lifetime gains were slightly larger.

Termination classification is more sensitive to grid resolution near the loaded-voltage feasibility boundary. Termination percentages should therefore be compared at the stated grid size.

## Monte Carlo and matched-service analysis

The main sweep uses 200 Monte Carlo runs per policy point.

The tested service-weight values are

`[0 0.1 0.2 0.3 0.5 0.75 1 1.5 2 3 5 10 30]`.

Each Monte Carlo run starts in the LOW physiological state.

Battery seed bases are:

| Battery | Seed base |
|---|---:|
| LIR2450 | 42000 |
| LIR2032H | 43000 |
| CR2032 | 44000 |
| CR1632 | 45000 |

Run `r` uses

`seed_base + r`.

Blind and aware simulations therefore use the same run-index seeds and are compared run by run.

This is matched run-index seeding rather than strict common random numbers. Once the two policies make different decisions, their random-number consumption can diverge.

Both policies are physically evaluated with the same loaded-voltage model enabled.

Matched-service comparisons use the actual simulated policy points.

Nondominated lifetime--service points are retained separately for the blind and aware policies.

TX rate is the primary matching metric.

A service mismatch within 2% is preferred. If no qualifying pair is available, a 5% fallback threshold is used.

Within the applicable tier, the pair with the minimum service mismatch is selected. Higher mean service is used only as an exact tie-break.

