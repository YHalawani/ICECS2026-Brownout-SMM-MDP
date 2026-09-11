# MATLAB Implementation of the SMM-MDP Framework Used in the ICECS 2026 Paper

**"Brownout-Aware Energy Management for Wearable Health Patches Using SMM-MDP Optimization"**

This repository contains the MATLAB implementation used to:

- derive the three-state SLEEP/LOW/HIGH Semi-Markov Model (SMM) from MMASH;
- model battery-energy depletion and loaded-voltage constraints;
- optimize brownout-blind and brownout-aware firmware policies using an MDP;
- evaluate the policies using Monte Carlo simulation;
- compare blind and aware policies at matched delivered TX rate and QoS;
- perform the reported internal-resistance sensitivity analysis; and
- recreate the CR1632 lifetime-transmission figure reported in the paper.

For the complete numerical model specification and assumptions, see `MODEL.md`.

## Requirements

- MATLAB R2026a or a recent compatible release.
- MMASH dataset downloaded separately from PhysioNet.
- The supplied dataset path must point to the MMASH `DataPaper` folder containing:

```text
user_1
user_2
...
user_22
```

The MMASH dataset is not redistributed in this repository.

## Main Reproduction

Set the MMASH dataset path and an output directory:

```matlab
mmashRoot = 'D:/Datasets/MMASH/DataPaper';
outDir = 'results';

run_paper_results(mmashRoot,outDir);
```

All generated files are stored in the directory specified by `outDir`.

- **`run_paper_results.m`** — main reproduction script that runs the complete paper workflow: loads the model, solves and simulates brownout-blind and brownout-aware policies, performs matched-service and resistance-sensitivity analyses, exports result tables, and recreates the paper figure.

## Source Files

The core implementation is contained in the `src` folder:

- **`paper_model.m`** — defines the fixed model configuration, including battery parameters, sensing and TX loads, firmware actions A0--A6, MDP settings, Monte Carlo settings, and service-matching parameters.

- **`build_mmash_smm.m`** — processes the MMASH activity and sleep annotations to construct the SLEEP/LOW/HIGH workload model, empirical dwell distributions, state occupancies, and exit-transition matrix.

- **`peukert_factor.m`** — implements the Peukert-like load-rate correction used to adjust battery-energy consumption.

- **`brownout_state.m`** — computes SoC-dependent open-circuit voltage, sensing-state and TX loaded voltages, and the warning/minimum-voltage suppression conditions.

- **`solve_policy.m`** — solves the brownout-blind or brownout-aware MDP using value iteration and returns the best firmware action for each battery-energy and physiological state.

- **`simulate_policy.m`** — evaluates a solved policy using Monte Carlo simulation with empirical MMASH dwell durations, stochastic TX events, battery-energy depletion, and physical loaded-voltage constraints.

- **`analyze_results.m`** — compares blind and aware policies at similar TX rate or QoS and calculates the resulting lifetime gains and confidence intervals.


## Citation

If this code is used in academic work, please cite the ICECS 2026 paper above.

## License

This code is released under the MIT License. See `LICENSE.txt` for details.
