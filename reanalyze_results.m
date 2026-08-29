function reanalyze_results(outDir)
%REANALYZE_RESULTS Re-run matched-service inference without Monte Carlo.

    if nargin<1, outDir='results'; end
    root=fileparts(mfilename('fullpath'));
    addpath(fullfile(root,'src'));

    S=load(fullfile(outDir,'main_results.mat'),'cfg','study');
    [MatchedService,headline]=analyze_results(S.study,S.cfg,outDir); %#ok<NASGU>
    save(fullfile(outDir,'analysis_results.mat'),'MatchedService','headline');

    fprintf('\nCR1632 TX match: blind lambda=%g, aware lambda=%g, gain=%.2f%%\n', ...
        headline.TX.blind.lambda,headline.TX.aware.lambda, ...
        100*(headline.TX.aware.life-headline.TX.blind.life)/headline.TX.blind.life);
    fprintf('Selection-aware 95%% CI: [%.2f, %.2f]%%\n',headline.TX.ci);
    fprintf('Bootstrap tiers: %.2f%% preferred, %.2f%% fallback, %.2f%% unmatched\n', ...
        100*headline.TX.bootstrap.preferred_rate, ...
        100*headline.TX.bootstrap.fallback_rate, ...
        100*headline.TX.bootstrap.unmatched_rate);

    fprintf('CR1632 QoS match: blind lambda=%g, aware lambda=%g, gain=%.2f%%\n', ...
        headline.QoS.blind.lambda,headline.QoS.aware.lambda, ...
        100*(headline.QoS.aware.life-headline.QoS.blind.life)/headline.QoS.blind.life);
    fprintf('95%% CI: [%.2f, %.2f]%%\n',headline.QoS.ci);

end
