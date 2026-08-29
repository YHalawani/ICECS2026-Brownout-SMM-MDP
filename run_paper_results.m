function run_paper_results(mmashRoot,outDir)
%RUN_PAPER_RESULTS Reproduce the main battery and matched-service analysis.

    if nargin<2, outDir='results'; end
    if ~isfolder(outDir), mkdir(outDir); end
    addpath(fullfile(fileparts(mfilename('fullpath')),'src'));

    cfg=paper_model(mmashRoot);
    rows={}; study=struct();

    for b=1:numel(cfg.battery_names)
        name=cfg.battery_names{b}; bat=cfg.batteries.(name); seed=cfg.seed.(name);
        points=cell(1,numel(cfg.lambda));
        fprintf('\n%s\n',name);
        for k=1:numel(cfg.lambda)
            lam=cfg.lambda(k);
            [pB,~,iB]=solve_policy(cfg,bat,lam,false);
            [pA,~,iA]=solve_policy(cfg,bat,lam,true);
            if ~iB.converged || ~iA.converged, error('Value iteration did not converge.'); end

            sB=simulate_policy(cfg,bat,pB,cfg.n_runs,seed);
            sA=simulate_policy(cfg,bat,pA,cfg.n_runs,seed);
            points{k}=struct('lambda',lam, ...
                'blind',struct('policy',pB,'summary',sB), ...
                'aware',struct('policy',pA,'summary',sA));

            rows(end+1,:)={name,lam,'blind',sB.life_h_mean,sB.tx_per_hour_mean, ...
                sB.qos_time_mean,100*sB.residual_soc_mean,sB.terminal_state_hard_rate, ...
                sB.terminal_A0_rate,sB.terminal_depletion_rate}; %#ok<AGROW>
            rows(end+1,:)={name,lam,'aware',sA.life_h_mean,sA.tx_per_hour_mean, ...
                sA.qos_time_mean,100*sA.residual_soc_mean,sA.terminal_state_hard_rate, ...
                sA.terminal_A0_rate,sA.terminal_depletion_rate}; %#ok<AGROW>
            fprintf('  lambda=%-4g  blind %.1fh  aware %.1fh\n',lam,sB.life_h_mean,sA.life_h_mean);
        end
        study.(name)=points;
        save(fullfile(outDir,'main_results_checkpoint.mat'),'cfg','study','-v7.3');
    end

    MainResults=cell2table(rows,'VariableNames',{ ...
        'Battery','Lambda','Policy','Life_h','TX_per_h','QoS','ResidualSOC_pct', ...
        'TermStateHardRate','TermA0Rate','TermDepletionRate'});
    writetable(MainResults,fullfile(outDir,'main_results.csv'));
    save(fullfile(outDir,'main_results.mat'),'cfg','study','MainResults','-v7.3');

    [MatchedService,headline]=analyze_results(study,cfg,outDir); %#ok<NASGU>
    save(fullfile(outDir,'analysis_results.mat'),'MatchedService','headline');
    write_fixed_chain(cfg,study,headline,outDir);

    fprintf('\nCR1632 TX match: blind lambda=%g, aware lambda=%g, gain=%.2f%%\n', ...
        headline.TX.blind.lambda,headline.TX.aware.lambda, ...
        100*(headline.TX.aware.life-headline.TX.blind.life)/headline.TX.blind.life);
    fprintf('Selection-aware 95%% CI: [%.2f, %.2f]%%\n',headline.TX.bootstrap.ci);
    fprintf('CR1632 QoS match: blind lambda=%g, aware lambda=%g, gain=%.2f%%\n', ...
        headline.QoS.blind.lambda,headline.QoS.aware.lambda, ...
        100*(headline.QoS.aware.life-headline.QoS.blind.life)/headline.QoS.blind.life);
    fprintf('95%% CI: [%.2f, %.2f]%%\n',headline.QoS.ci);

end

function write_fixed_chain(cfg,study,headline,outDir)
    bat=cfg.batteries.CR1632; seed=cfg.seed.CR1632;
    idx=find(strcmp({cfg.actions.name},'A5_EVENT_ALERT'),1);
    fixed=simulate_policy(cfg,bat,idx,cfg.n_runs,seed);
    B=headline.TX.blind.sm; A=headline.TX.aware.sm;
    fb=paired_gain(fixed.raw.life_h,B.raw.life_h);
    fa=paired_gain(fixed.raw.life_h,A.raw.life_h);
    ba=paired_gain(B.raw.life_h,A.raw.life_h);

    T=table(fixed.life_h_mean,fixed.tx_per_hour_mean, ...
        B.life_h_mean,B.tx_per_hour_mean,A.life_h_mean,A.tx_per_hour_mean, ...
        fb.gain_pct,fb.ci_low_pct,fb.ci_high_pct,fa.gain_pct,ba.gain_pct, ...
        'VariableNames',{'FixedA5Life_h','FixedA5TX_h','BlindLife_h','BlindTX_h', ...
        'AwareLife_h','AwareTX_h','FixedToBlindGain_pct','FixedToBlindCI95Low_pct', ...
        'FixedToBlindCI95High_pct','FixedToAwareGain_pct','BlindToAwareFixedPairGain_pct'});
    writetable(T,fullfile(outDir,'cr1632_fixed_chain.csv'));
end

function C=paired_gain(ref,test)
    d=test(:)-ref(:); den=mean(ref(:)); mu=mean(d); se=std(d)/sqrt(numel(d));
    ci=mu+[-1 1]*1.96*se;
    C=struct('gain_pct',100*mu/den,'ci_low_pct',100*ci(1)/den,'ci_high_pct',100*ci(2)/den);
end
