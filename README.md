# MATLAB implementation of the SMM-MDP method used in the ICECS 2026 paper:

**"Brownout-Aware Energy Management for Wearable Health Patches Using SMM--MDP Optimization."**

The repository contains the code used to derive the three-state SMM workload from the MMASH dataset, model battery energy depletion and loaded-voltage constraints, optimize brownout-blind and brownout-aware policies, perform Monte Carlo evaluation, carry out the matched-service analysis, and recreate the paper figure.

For the complete numerical model specification, see `MODEL.md`.

For the reported results, confidence-interval information, and reproduction notes, see `RESULTS.md`.

## Requirements

- MATLAB R2026a or a recent compatible release.
- MMASH downloaded separately from PhysioNet.
- The path supplied to the MATLAB code should point to the MMASH `DataPaper` folder containing `user_1`, ..., `user_22`.

The MMASH dataset is not redistributed in this repository.

## Main reproduction

Set the MMASH dataset path and an output directory:

```matlab
mmashRoot = 'D:/Datasets/MMASH/DataPaper';
outDir = 'results';

run_paper_results(mmashRoot,outDir);


## Citation

If this code is used in academic work, please cite the ICECS 2026 paper above.


## License

This code is released under the MIT License. See `LICENSE` for details.
