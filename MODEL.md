# Model Definition

This document records the numerical model specification, assumptions, and analysis settings implemented by the MATLAB code for the ICECS 2026 paper **"Brownout-Aware Energy Management for Wearable Health Patches Using SMM-MDP Optimization."**

## 1. MMASH-Derived Workload and SMM

The workload is derived from the full 22-user MMASH cohort and mapped to three physiological states:

- **SLEEP** — activity code 1 or an interval covered by `sleep.csv`.
- **LOW** — activity codes 2--4.
- **HIGH** — activity codes 5--6.

Activity codes outside the explicit SLEEP/LOW/HIGH mapping are not treated as separate physiological states. The continuous timeline is initialized to LOW, so intervals without an explicit mapped activity remain LOW unless overridden by a sleep interval. Sleep annotations override activity annotations.

The workload timeline uses 60 s intervals. When a required activity start or end time is missing, neighboring timestamps are used when available; if no neighboring timestamp is available, the preprocessing code uses a 900 s fallback interval.

The full-cohort extraction gives:

| Quantity | SLEEP | LOW | HIGH |
|---|---:|---:|---:|
| Occupancy | 26.54% | 65.67% | 7.79% |
| Mean dwell (s) | 16912.0 | 8777.6 | 1551.2 |

Monte Carlo evaluation samples empirical dwell durations from the MMASH-derived dwell pools. Value iteration uses the corresponding mean dwell duration.

The observed state-to-state transition matrix is first obtained from adjacent states on the mapped 60 s timeline. Because state persistence is represented separately by the empirical dwell-time distributions, the next-state transition matrix is conditioned on leaving the current state:

```text
Pexit(i,j) = Pphys(i,j)/(1 - Pphys(i,i)),   i ~= j
Pexit(i,i) = 0
```

Thus, `Pexit` determines the next physiological state after the current dwell ends.

## 2. Transmission Overlay

Wireless transmission is modeled as an action-dependent overlay rather than a physiological state.

For a dwell of duration `d` in physiological state `i`, the requested TX count has mean

```text
lambda_TX = d/tau_i * T(i,a)
```

and is modeled as

```text
N_TX(i,a) ~ Poisson(lambda_TX)
```

where:

- `tau_i = [300 120 60]` s is the nominal A1 TX period for SLEEP/LOW/HIGH;
- `T(i,a)` is the requested TX-rate factor of action `a` relative to A1.

Value iteration uses the expected TX count `lambda_TX`. Monte Carlo evaluation samples a random requested TX count. The custom sampler uses direct Poisson sampling for `lambda_TX < 30` and a rounded, nonnegative normal approximation with mean and variance `lambda_TX` for larger means.

Voltage-warning suppression is applied after the requested TX count is obtained.

## 3. Firmware Actions and Service Model

Vectors are ordered SLEEP / LOW / HIGH.

| Action | State power (mW) | Relative sensing factor S | Requested TX-rate factor T | Utility u | State peak current (mA) |
|---|---:|---:|---:|---:|---:|
| A0 | `[0.024 0.024 0.024]` | `[0 0 0]` | `[0 0 0]` | 0 | `[0.01 0.01 0.01]` |
| A1 | `[0.024 1.880 14.10]` | `[1 1 1]` | `[1 1 1]` | 1 | `[0.01 1 20]` |
| A2 | `[0.224 2.880 15.10]` | `[1 1 1]` | `[1 1 1]` | 1.10 | `[0.01 1 20]` |
| A3 | `[0.024 1.930 14.15]` | `[1 1 1]` | `[0.33 0.33 0.33]` | 1 | `[0.01 1 20]` |
| A4 | `[0.224 2.580 14.80]` | `[1 1 1]` | `[0.17 0.17 0.17]` | 1.10 | `[0.01 1 20]` |
| A5 | `[0.024 2.380 15.10]` | `[1 1 1]` | `[0.20 0.50 2.00]` | 1 | `[0.01 1 20]` |
| A6 | `[0.024 1.410 7.755]` | `[1 0.75 0.55]` | `[0.25 0.35 0.50]` | 1 | `[0.01 0.70 9]` |

The absolute values above are the values used by the model.

A1 defines the nominal sense-send operating point:

```text
P0 = [0.024 1.880 14.10] mW
I0 = [0.01 1 20] mA
```

The baseline loads are system-level abstractions based on representative component operating conditions rather than measured current waveforms from a fabricated prototype.

A2--A6 define a discrete set of predefined firmware choices relative to A1. Their processing-power increments, sensing factors, TX-rate factors, utility multipliers, and peak-current changes are engineering modeling assumptions fixed before the reported simulation analysis.

- **A0 — Monitoring fallback.** Low-power fallback with no useful monitoring service.
- **A1 — Nominal sense-send.** Nominal sensing, transmission, and peak-current values.
- **A2 — Processing.** Adds local-processing power while retaining nominal sensing and TX rates; `u = 1.10`.
- **A3 — Aggregation.** Adds small buffering overhead and reduces requested TX rate to about one-third of nominal.
- **A4 — Processing + aggregation.** Adds processing power and stronger TX aggregation; `u = 1.10`.
- **A5 — Event alert.** Uses lower routine TX rates in SLEEP/LOW and doubles the requested nominal TX rate in HIGH.
- **A6 — Reduced load.** Reduces LOW/HIGH sensing power, sensing service, TX rate, and peak current.

For A6, the state-power multipliers relative to A1 are `[1 0.75 0.55]`, giving `[0.024 1.410 7.755]` mW. Its peak-current multipliers are `[1 0.70 0.45]`, giving `[0.01 0.70 9]` mA.

The A6 sensing factors are composite relative sensing-service assumptions. They are not derived from the power multipliers, peak-current multipliers, SNR, or measured clinical sensing quality.

### Service score

The table values `S(i,a)` and `T(i,a)` are the predefined sensing-service and requested TX-rate factors before voltage-warning suppression.

After any warning-level suppression,

```text
Sdel = S(i,a) * (1 - sense_supp)
Tdel = T(i,a) * (1 - tx_supp)
```

and the relative service score is

```text
Q(i,a) = u_a * (0.60*Sdel + 0.40*Tdel)
```

The coefficients 0.60 and 0.40 are service-value weights, not energy proportions.

`Tdel` is not capped at one, so the A5 HIGH-state value may exceed nominal A1 service.

## 4. Battery and Loaded-Voltage Model

The battery specification combines datasheet-grounded quantities, derived quantities, and explicit modeling assumptions.

| Battery | Vnom (V) | Enom (Wh) | Rint (ohm) | n | Iref (mA) | Vwarn (V) | Vmin (V) |
|---|---:|---:|---:|---:|---:|---:|---:|
| LIR2450 | 3.7 | 0.370 | 0.40 | 1.03 | 20 | 3.3 | 3.0 |
| LIR2032H | 3.7 | 0.222 | 0.65 | 1.03 | 12 | 3.2 | 2.75 |
| CR2032 | 3.0 | 0.705 | 18 | 1.08 | 0.19 | 2.4 | 2.0 |
| CR1632 | 3.0 | 0.390 | 30 | 1.09 | 0.19 | 2.4 | 2.0 |

- **`Vnom`** — nominal cell voltage. Within the simplified OCV model it is used as the SoC = 1 endpoint, `Voc(1) = Vnom`. This is a modeling convention and should not be interpreted as the manufacturer's charge-termination voltage for rechargeable cells.
- **`Enom`** — nominal stored-energy budget in Wh, obtained from nominal voltage and rated capacity.
- **`Rint`** — representative effective internal resistance used for loaded-voltage calculations.
- **`n`** — dimensionless Peukert-like rate-derating exponent.
- **`Iref`** — reference current used by the rate correction and OCV endpoint construction.
- **`Vwarn`** — warning-level loaded-voltage threshold.
- **`Vmin`** — minimum loaded-voltage threshold used for sensing feasibility and termination.

For the rechargeable LIR cases, the selected resistance values use reported impedance limits. For CR2032 and CR1632, the resistance values are representative modeling assumptions and are explicitly examined through sensitivity analysis.

`n`, `Vwarn`, `Vmin`, and the interior OCV shape are model parameters. The voltage thresholds are system-level modeling thresholds rather than measured limits of a fabricated patch.

### 4.1 Rate-dependent energy use

Effective interval energy is multiplied by

```text
fP(I) = max(1, (I/Iref)^(n-1))
```

so currents below `Iref` do not create artificial capacity gain.

For sensing-state energy,

```text
Istate_avg = Pstate_eff / Vnom
```

and for TX energy,

```text
Itx_avg = Ptx / Vnom
```

These average currents are used only for the Peukert-like energy correction. Peak currents are used separately for loaded-voltage checks.

### 4.2 Open-circuit voltage

The empty-cell endpoint is

```text
Voc(0) = Vmin + (Iref/1000)*Rint
```

and the upper model endpoint is

```text
Voc(1) = Vnom
```

The interior OCV--SoC curve is piecewise linear with a knee at `s = 0.35`. A fraction `0.65` of the total modeled voltage rise occurs below that knee:

```text
g(s) = 0.65*s/0.35,                                  s < 0.35
g(s) = 0.65 + 0.35*(s - 0.35)/(1 - 0.35),           s >= 0.35
```

The OCV is then

```text
Voc(s) = Voc(0) + (Vnom - Voc(0))*g(s)
```

The knee location `0.35` and lower-region voltage-span fraction `0.65` are modeling assumptions rather than measured battery discharge-curve characteristics.

### 4.3 Loaded voltage

Sensing-state and TX current peaks are assumed not to overlap, so their loaded voltages are evaluated separately:

```text
Vstate = Voc(s) - (Istate_peak/1000)*Rint
Vtx    = Voc(s) - (Itx_peak/1000)*Rint
```

The TX-event parameters are:

```text
TX event-average power = 14.1 mW
TX duration            = 0.05 s
TX startup energy      = 2 mJ
TX peak current        = 12 mA
```

These are system-level model parameters rather than measured prototype waveforms.

### 4.4 Warning and minimum-voltage behavior

Sensing and TX limits are evaluated independently.

If

```text
Vstate <= Vwarn
```

sensing service is reduced by 50%, and effective sensing-state power becomes

```text
Pstate_eff = 0.5*Pstate + 0.5*Psleep
```

If

```text
Vstate <= Vmin
```

the active sensing mode is physically unsupported and useful monitoring terminates.

For TX, if

```text
Vtx <= Vwarn
```

50% of requested TX service is suppressed. During Monte Carlo evaluation this is implemented by independently retaining each requested TX event with probability 0.5.

If

```text
Vtx <= Vmin
```

the affected TX is fully suppressed, but sensing may continue.

No independent fixed-SoC warning or termination threshold is used.

### 4.5 CR1632 voltage sanity check

For CR1632,

```text
Voc(0) = 2.0 + (0.19/1000)*30 = 2.0057 V
```

For A1 in HIGH, `Istate_peak = 20 mA`, so

```text
voltage drop = (20/1000)*30 = 0.600 V
```

At the upper OCV endpoint,

```text
Vstate = 3.0 - 0.600 = 2.400 V
```

which is exactly the CR1632 warning threshold `Vwarn = 2.4 V`.

Because the warning comparison uses `<=`, A1 in HIGH is at the warning boundary at `s = 1` in this model.

## 5. MDP and Value Iteration

The MDP state is

```text
(E, i)
```

where `E` is remaining battery energy and `i` is SLEEP, LOW, or HIGH.

The main analysis uses:

```text
N_E       = 800 energy bins
gamma     = 1
tolerance = 1e-6
max_iter  = 25000
```

`gamma = 1` is used because the finite-battery process is terminating.

A0 is the terminal fallback action. Active candidate actions are A1--A6.

### 5.1 Brownout-aware versus brownout-blind optimization

For brownout-aware optimization, loaded-voltage warning and minimum-voltage effects are applied while each candidate action is evaluated. An active action is excluded when

```text
Vstate <= Vmin
```

If no active action is feasible, the policy stores A0.

For brownout-blind optimization, loaded voltages may still be computed internally, but warning and minimum-voltage effects are not applied during optimization.

This distinction applies only while the policy is being solved. During Monte Carlo evaluation, both blind and aware policies are tested using the same physical loaded-voltage and brownout model.

### 5.2 Expected energy of one state-action dwell

Value iteration uses the mean dwell duration `dbar_i`.

Expected sensing-state energy is

```text
Estate = Pstate_eff * fP(Istate_avg) * dbar_i / 3600
```

The expected requested TX count is

```text
E[N_TX] = dbar_i/tau_i * T(i,a)
```

and the expected delivered TX count after suppression is

```text
E[N_TX_del] = E[N_TX] * (1 - tx_supp)
```

Energy per TX event is

```text
Eone = Ptx*TX_duration/3600 + TX_startup_mJ/3600
```

in mWh, and expected TX energy is

```text
Etx = E[N_TX_del] * Eone * fP(Itx_avg)
```

Therefore,

```text
Eexp(i,a) = Estate + Etx
```

### 5.3 Partial dwell completion and continuous post-action energy

If the available energy supports only part of the expected dwell,

```text
factive = E / Eexp(i,a)
```

and

```text
tcomp = factive * dbar_i / 3600
```

hours are credited. No future value is assigned after depletion.

If the full dwell can be completed,

```text
E' = E - Eexp(i,a)
```

is the post-action energy.

`E'` is generally not an exact energy-grid point. The future value at `E'` is therefore obtained by linear interpolation between the two adjacent energy bins rather than by rounding to one bin.

### 5.4 Bellman update

For every energy/state combination, value iteration tests each feasible action A1--A6 and computes

```text
V(E,i) = max_a {
    tcomp * [1 + lambda_QoS*Q(i,a)]
    + gamma * sum_j Pexit(i,j) * V_tilde(E',j)
}
```

where `V_tilde(E',j)` denotes the linearly interpolated future value.

The first term rewards completed monitoring time and delivered service. The second term is the expected future value after the current dwell.

The MATLAB variable `lambda` in `solve_policy.m` is `lambda_QoS`; it is unrelated to the Poisson mean `lambda_TX`.

Value iteration repeatedly applies this Bellman update until

```text
max(abs(V_new - V_old)) < 1e-6
```

or the maximum iteration count is reached. The action achieving the highest value is stored as the policy for that energy/state combination.

No additional voltage-headroom reward penalty is used in the refined model.

## 6. Monte Carlo Policy Evaluation

The main sweep uses

```text
200 Monte Carlo runs per policy point
```

and each run starts in the LOW physiological state with a full nominal energy budget.

Within each simulated dwell:

1. the stored policy selects an action using the current energy bin and physiological state;
2. an empirical MMASH dwell duration is sampled;
3. physical loaded-voltage conditions are evaluated;
4. sensing-state energy is calculated;
5. a requested TX count is sampled;
6. voltage-dependent TX suppression is applied;
7. TX energy and delivered service are accumulated;
8. remaining battery energy is updated; and
9. the next physiological state is sampled from `Pexit`.

The simulator records lifetime, delivered TX rate, time-weighted QoS, residual SoC, termination type, action-selection counts, and completed monitoring time by action and physiological state.

### 6.1 Termination classes

The Monte Carlo evaluator records three mutually exclusive termination classes:

1. **State-load minimum-voltage violation** — an active action is selected, but its sensing-state loaded voltage satisfies `Vstate <= Vmin`.
2. **A0 fallback** — the solved policy selects A0 because no active monitoring action was stored for that energy/state condition.
3. **Energy depletion** — the remaining energy is insufficient to complete the sampled dwell; only the completed fraction is credited before termination.

### 6.2 Random seeds

Battery seed bases are:

| Battery | Seed base |
|---|---:|
| LIR2450 | 42000 |
| LIR2032H | 43000 |
| CR2032 | 44000 |
| CR1632 | 45000 |

Run `r` uses

```text
seed_base + r
```

Blind and aware simulations therefore use the same run-index seeds. This is matched run-index seeding rather than strict common random numbers because random-number consumption can diverge after the two policies begin making different decisions.

## 7. QoS Sweep and Matched-Service Analysis

The tested QoS-weight values are

```text
[0 0.1 0.2 0.3 0.5 0.75 1 1.5 2 3 5 10 30]
```

For each battery and each `lambda_QoS`, blind and aware policies are solved independently and evaluated by Monte Carlo simulation.

Matched-service comparisons are performed separately for:

- delivered TX rate; and
- overall delivered QoS.

Nondominated lifetime--service points are first retained separately for blind and aware policies. A point is removed if another tested point has at least as much lifetime and at least as much service, with one quantity strictly better.

For blind service `a` and aware service `b`, percentage mismatch is

```text
mismatch_pct = 100*abs(a-b)/mean(abs([a b]))
```

Matching uses the following hierarchy:

```text
preferred mismatch <= 2%
fallback mismatch  <= 5%
otherwise          UNMATCHED
```

Within the applicable tier, the pair with the smallest service mismatch is selected. If two pairs have exactly the same mismatch, the pair with the higher mean service is selected.

Lifetime gain is reported relative to the blind policy:

```text
gain_pct = 100*(aware_lifetime - blind_lifetime)/blind_lifetime
```

For non-headline comparisons, the code reports a paired normal-approximation confidence interval based on run-wise lifetime differences.

For the two CR1632 headline comparisons, the complete front-construction and service-matching procedure is repeated within

```text
2000 bootstrap resamples
```

using fixed seeds:

```text
TX matching  : 91428
QoS matching : 91429
```

If a bootstrap replicate has no pair within the 5% fallback threshold, the closest pair is still used to calculate that replicate's gain and the replicate is counted as unmatched.

## 8. Internal-Resistance Sensitivity Analysis

The reported resistance-sensitivity analysis is performed for CR2032 and CR1632 using

```text
R/R0 = [2/3 0.8 1 1.25]
```

which gives:

| Battery | Resistance values (ohm) |
|---|---|
| CR2032 | `[12 14.4 18 22.5]` |
| CR1632 | `[20 24 30 37.5]` |

At every resistance value:

1. the battery model is updated with the perturbed resistance;
2. blind and aware policies are re-solved over the full `lambda_QoS` grid;
3. both policies are re-evaluated using the same perturbed battery model and run-index seeds; and
4. matched-TX and matched-QoS comparisons are repeated.

Thus, the sensitivity analysis does not evaluate a nominal policy under a different resistance; the policy itself is re-optimized for each resistance value.

## 9. Model Scope and Assumptions

The implementation is a system-level simulation rather than a measured hardware prototype model. Its main assumptions include:

- constant effective internal resistance within each nominal battery case;
- a simplified piecewise-linear OCV--SoC model;
- non-overlapping sensing and TX current peaks;
- predefined firmware actions rather than continuous control variables;
- predefined sensing-service and utility factors;
- time-homogeneous SMM behavior after estimation from MMASH;
- LOW assignment for timeline intervals without an explicit mapped physiological label;
- mean-dwell and expected-TX approximations during value iteration; and
- Monte Carlo evaluation using empirical dwell durations and stochastic TX events.

The computed policy is optimal only within the predefined action set and the stated model assumptions. Hardware validation with measured current profiles, SoC- and age-dependent battery resistance, and experimentally measured sensing-quality factors remains future work.
