function run_paper_results(mmashRoot,outDir)
%RUN_PAPER_RESULTS Reproduce the paper results and main figure. 
%
% This function performs the complete paper workflow:
%   1) build the MMASH-derived model and fixed configuration,
%   2) solve brownout-blind and brownout-aware policies,
%   3) evaluate every policy using Monte Carlo simulation,
%   4) match blind/aware policies at similar delivered TX rate and QoS,
%   5) run the reported primary-cell internal-resistance sensitivity sweep,
%   6) recreate the CR1632 lifetime-transmission figure.
%
% mmashRoot : path to the MMASH dataset root folder
% outDir    : folder used to save all generated results
%
% Core model functions are kept in the src/ folder.

    if nargin<2
        outDir='results';
    end
    if ~isfolder(outDir)
        mkdir(outDir);
    end

    % Make the core model functions in src/ available 
    addpath(fullfile(fileparts(mfilename('fullpath')),'src'));

    % Build the complete paper configuration, including the MMASH-derived
    % SMM, battery models, firmware actions, and optimization settings
    cfg=paper_model(mmashRoot);


    % =====================================================================
    % 1. MAIN BATTERY / LAMBDA_QOS STUDY
    % =====================================================================
    % For every battery and lambda_QoS value, solve one brownout-blind and
    % one brownout-aware MDP policy, then physically evaluate both policies
    % using the same Monte Carlo run-index seeds

    rows={};
    study=struct();

    for b=1:numel(cfg.battery_names)

        name=cfg.battery_names{b};
        bat=cfg.batteries.(name);
        seed=cfg.seed.(name);
        points=cell(1,numel(cfg.lambda));

        fprintf('\n%s\n',name);

        for k=1:numel(cfg.lambda)

            lam=cfg.lambda(k);

            % Solve the MDP twice at the same QoS reward weight:
            % false = brownout-blind, true = brownout-aware.
            [pB,~,iB]=solve_policy(cfg,bat,lam,false);
            [pA,~,iA]=solve_policy(cfg,bat,lam,true);

            if ~iB.converged || ~iA.converged
                error('Value iteration did not converge.');
            end

            % Monte Carlo evaluation of the two optimized policies.
            sB=simulate_policy(cfg,bat,pB,cfg.n_runs,seed);
            sA=simulate_policy(cfg,bat,pA,cfg.n_runs,seed);

            % Keep the policy and its simulation summary for later matching
            % and plotting.
            points{k}=struct('lambda',lam, ...
                'blind',struct('policy',pB,'summary',sB), ...
                'aware',struct('policy',pA,'summary',sA));

            % Store the main reported performance and termination metrics.
            rows(end+1,:)={name,lam,'blind',sB.life_h_mean,sB.tx_per_hour_mean, ...
                sB.qos_time_mean,100*sB.residual_soc_mean,sB.terminal_state_hard_rate, ...
                sB.terminal_A0_rate,sB.terminal_depletion_rate}; %#ok<AGROW>

            rows(end+1,:)={name,lam,'aware',sA.life_h_mean,sA.tx_per_hour_mean, ...
                sA.qos_time_mean,100*sA.residual_soc_mean,sA.terminal_state_hard_rate, ...
                sA.terminal_A0_rate,sA.terminal_depletion_rate}; %#ok<AGROW>

            fprintf('  lambda=%-4g  blind %.1fh  aware %.1fh\n', ...
                lam,sB.life_h_mean,sA.life_h_mean);
        end

        study.(name)=points;

        % Save an incremental checkpoint after each battery in case the
        % complete study is interrupted.
        save(fullfile(outDir,'main_results_checkpoint.mat'),'cfg','study','-v7.3');
    end


    % Convert the main results to a table and save both CSV and MAT forms.
    MainResults=cell2table(rows,'VariableNames',{ ...
        'Battery','Lambda','Policy','Life_h','TX_per_h','QoS','ResidualSOC_pct', ...
        'TermStateHardRate','TermA0Rate','TermDepletionRate'});

    writetable(MainResults,fullfile(outDir,'main_results.csv'));
    save(fullfile(outDir,'main_results.mat'),'cfg','study','MainResults','-v7.3');


    % =====================================================================
    % 2. ACTION-USAGE DIAGNOSTICS
    % =====================================================================
    % Export how the optimized policies use A0-A6 overall and separately
    % within SLEEP, LOW, and HIGH.
    write_action_usage(cfg,study,outDir);


    % =====================================================================
    % 3. MATCHED-SERVICE ANALYSIS
    % =====================================================================
    % Compare brownout-blind and brownout-aware operating points at similar
    % delivered TX rate and similar overall QoS. analyze_results also builds
    % the CR1632 selection-aware bootstrap intervals.
    [MatchedService,headline]=analyze_results(study,cfg,outDir); %#ok<NASGU>

    save(fullfile(outDir,'analysis_results.mat'),'MatchedService','headline');


    % Print the two CR1632 headline matched-service comparisons.
    fprintf('\nCR1632 TX match: blind lambda=%g, aware lambda=%g, gain=%.2f%%\n', ...
        headline.TX.blind.lambda,headline.TX.aware.lambda, ...
        100*(headline.TX.aware.life-headline.TX.blind.life)/headline.TX.blind.life);
    fprintf('Selection-aware 95%% CI: [%.2f, %.2f]%%\n',headline.TX.bootstrap.ci);

    fprintf('CR1632 QoS match: blind lambda=%g, aware lambda=%g, gain=%.2f%%\n', ...
        headline.QoS.blind.lambda,headline.QoS.aware.lambda, ...
        100*(headline.QoS.aware.life-headline.QoS.blind.life)/headline.QoS.blind.life);
    fprintf('Selection-aware 95%% CI: [%.2f, %.2f]%%\n',headline.QoS.ci);


    % =====================================================================
    % 4. PRIMARY-CELL INTERNAL-RESISTANCE SENSITIVITY
    % =====================================================================
    % Re-solve and re-evaluate blind/aware policies after perturbing R_int
    % for CR2032 and CR1632. The same matching rules used in the paper are
    % applied separately to TX rate and overall QoS.
    run_resistance_sensitivity_from_cfg(cfg,outDir);


    % =====================================================================
    % 5. PAPER FIGURE
    % =====================================================================
    % Recreate the CR1632 lifetime-transmission tradeoff figure directly
    % from the main study and selected TX-matched comparison.
    plot_lifetime_tx_figure(study,headline,outDir);

    fprintf('\nComplete paper workflow finished. Results saved in: %s\n',outDir);

end


% =========================================================================
% EXPORT ACTION-USAGE DIAGNOSTICS
% =========================================================================
function write_action_usage(cfg,study,outDir)
%WRITE_ACTION_USAGE Export policy-bin and Monte Carlo action-use diagnostics.
%
% Every battery, lambda, policy type, physiological state, and action is
% included, including actions that receive zero use.

    rows=cell(0,10);

    for b=1:numel(cfg.battery_names)

        batName=cfg.battery_names{b};
        points=study.(batName);

        for k=1:numel(points)

            lam=points{k}.lambda;

            for pt={'blind','aware'}

                ptype=pt{1};
                pol=points{k}.(ptype).policy;
                sm=points{k}.(ptype).summary;

                for s=1:numel(cfg.states)
                    for ai=1:numel(cfg.actions)

                        % Fraction of energy bins assigned to this action
                        % for the current physiological state.
                        binFrac=mean(pol(:,s)==ai);

                        % Monte Carlo action-selection and completed-time
                        % fractions within the current physiological state.
                        selState=sm.action_selection_fraction_by_state(ai,s);
                        timeState=sm.action_time_fraction_by_state(ai,s);

                        rows(end+1,:)={batName,lam,ptype,cfg.states{s}, ...
                            cfg.actions(ai).name,100*binFrac,100*selState,100*timeState, ...
                            100*sm.action_selection_fraction(ai), ...
                            100*sm.action_time_fraction(ai)}; %#ok<AGROW>
                    end
                end
            end
        end
    end

    ActionUsage=cell2table(rows,'VariableNames',{ ...
        'Battery','Lambda','Policy','State','Action','PolicyBinFraction_pct', ...
        'MCSelectionWithinState_pct','MCTimeWithinState_pct', ...
        'MCSelectionOverall_pct','MCTimeOverall_pct'});

    writetable(ActionUsage,fullfile(outDir,'action_usage.csv'));
end


% =========================================================================
% PRIMARY-CELL INTERNAL-RESISTANCE SENSITIVITY
% =========================================================================
function run_resistance_sensitivity_from_cfg(cfg,outDir)
% Reproduce the resistance sweep reported for CR2032 and CR1632.
%
% Resistance multipliers are R/R0 = [2/3, 0.8, 1, 1.25]. At every
% resistance, both policies are re-solved and re-evaluated before matching.

    names={'CR2032','CR1632'};
    rMult=[2/3 0.8 1 1.25];

    rows=cell(0,17);
    SensitivityStudy=struct();

    for b=1:numel(names)

        name=names{b};
        baseBat=cfg.batteries.(name);
        seed=cfg.seed.(name);
        Rpoints=cell(1,numel(rMult));

        fprintf('\n%s resistance sensitivity\n',name);

        for ri=1:numel(rMult)

            % Copy the nominal battery model and change only R_int.
            bat=baseBat;
            bat.R_int=baseBat.R_int*rMult(ri);

            points=cell(1,numel(cfg.lambda));

            fprintf('  R_int = %.4g ohm\n',bat.R_int);

            % Re-solve and re-simulate every lambda_QoS point because the
            % optimal policy itself can change when internal resistance changes.
            for k=1:numel(cfg.lambda)

                lam=cfg.lambda(k);

                [pB,~,iB]=solve_policy(cfg,bat,lam,false);
                [pA,~,iA]=solve_policy(cfg,bat,lam,true);

                if ~iB.converged || ~iA.converged
                    error('Value iteration did not converge for %s, R=%g, lambda=%g.', ...
                        name,bat.R_int,lam);
                end

                sB=simulate_policy(cfg,bat,pB,cfg.n_runs,seed);
                sA=simulate_policy(cfg,bat,pA,cfg.n_runs,seed);

                points{k}=struct('lambda',lam, ...
                    'blind',struct('policy',pB,'summary',sB), ...
                    'aware',struct('policy',pA,'summary',sA));
            end

            % Preserve all operating points for this resistance value.
            Rpoints{ri}=struct('RMultiplier',rMult(ri), ...
                'R_ohm',bat.R_int,'points',{points});


            % Match blind and aware policies separately by TX rate and QoS.
            for metric={'TX','QoS'}

                m=metric{1};

                B=sensitivity_front(points,'blind',m);
                A=sensitivity_front(points,'aware',m);
                M=best_service_pair(B,A, ...
                    cfg.match_preferred_pct,cfg.match_fallback_pct);

                C=paired_lifetime_gain( ...
                    M.blind.sm.raw.life_h,M.aware.sm.raw.life_h);

                rows(end+1,:)={name,rMult(ri),baseBat.R_int,bat.R_int,m, ...
                    M.blind.lambda,M.aware.lambda,M.blind.service,M.aware.service, ...
                    M.mismatch,M.tier,M.blind.life,M.aware.life,C.gain_pct, ...
                    C.ci_low_pct,C.ci_high_pct,cfg.n_runs}; %#ok<AGROW>
            end
        end

        SensitivityStudy.(name)=Rpoints;
    end


    ResistanceSensitivity=cell2table(rows,'VariableNames',{ ...
        'Battery','RMultiplier','NominalR_ohm','R_ohm','MatchMetric', ...
        'BlindLambda','AwareLambda','BlindService','AwareService', ...
        'ServiceMismatch_pct','MatchTier','BlindLife_h','AwareLife_h', ...
        'AwareLifeGain_pct','LifeCI95Low_pct','LifeCI95High_pct','MonteCarloRuns'});

    writetable(ResistanceSensitivity, ...
        fullfile(outDir,'resistance_sensitivity.csv'));

    save(fullfile(outDir,'resistance_sensitivity.mat'), ...
        'ResistanceSensitivity','SensitivityStudy','rMult','-v7.3');
end


% ======================================================================================
% BUILD NONDOMINATED (optimal tradeoff points) FRONT FOR RESISTANCE-SENSITIVITY MATCHING
% ======================================================================================
function pts=sensitivity_front(points,ptype,metric)

    n=numel(points);
    pts=repmat(struct('lambda',0,'service',0,'life',0,'sm',[]),1,n);

    % Convert each lambda_QoS operating point into lifetime + service.
    for k=1:n

        sm=points{k}.(ptype).summary;

        if strcmp(metric,'TX')
            svc=sm.tx_per_hour_mean;
        else
            svc=sm.qos_time_mean;
        end

        pts(k)=struct('lambda',points{k}.lambda, ...
            'service',svc,'life',sm.life_h_mean,'sm',sm);
    end


    % Remove any point for which another tested point provides at least as
    % much lifetime and service, with one of the two being strictly better.
    keep=true(1,n);

    for i=1:n
        for j=1:n

            if i~=j && ...
                    pts(j).service>=pts(i).service && ...
                    pts(j).life>=pts(i).life && ...
                    (pts(j).service>pts(i).service || ...
                     pts(j).life>pts(i).life)

                keep(i)=false;
                break;
            end
        end
    end

    pts=pts(keep);
end


% =========================================================================
% SELECT CLOSEST BLIND/AWARE SERVICE PAIR
% =========================================================================
function M=best_service_pair(B,A,pref,fallback)

    C=[];

    % Compare every point on the blind front with every point on the aware
    % front and calculate their delivered-service mismatch.
    for i=1:numel(B)
        for j=1:numel(A)

            z.bi=i;
            z.ai=j;
            z.mis=service_mismatch_pct(B(i).service,A(j).service);
            z.meanService=mean([B(i).service A(j).service]);
            C=[C z]; %#ok<AGROW>
        end
    end


    mis=[C.mis];

    % Prefer <=2% service mismatch; allow <=5% if no preferred pair exists.
    % If neither threshold can be met, report the closest pair as UNMATCHED.
    if any(mis<=pref)

        eligible=find(mis<=pref);
        tier='<=2%';

    elseif any(mis<=fallback)

        eligible=find(mis<=fallback);
        tier='<=5%';

    else

        eligible=1:numel(C);
        tier='UNMATCHED';
    end


    % Choose the eligible pair with the smallest mismatch.
    best=min(mis(eligible));
    short=eligible(abs(mis(eligible)-best)<=1e-12);

    % If there is an exact mismatch tie, prefer the higher-service pair.
    if numel(short)>1
        [~,q]=max([C(short).meanService]);
        k=short(q);
    else
        k=short(1);
    end

    M=struct('blind',B(C(k).bi),'aware',A(C(k).ai), ...
        'mismatch',C(k).mis,'tier',tier);
end


% =========================================================================
% SERVICE MISMATCH
% =========================================================================
function p=service_mismatch_pct(a,b)

    % Percentage difference relative to the mean magnitude of the two values.
    d=mean(abs([a b]));

    if d<=eps
        p=0;
    else
        p=100*abs(a-b)/d;
    end
end


% =========================================================================
% PAIRED LIFETIME GAIN FOR RESISTANCE-SENSITIVITY RESULTS
% =========================================================================
function C=paired_lifetime_gain(ref,test)

    ref=ref(:);
    test=test(:);

    % Run-by-run aware-minus-blind lifetime difference.
    d=test-ref;
    den=mean(ref);
    mu=mean(d);
    se=std(d)/sqrt(numel(d));

    % 95% normal-approximation CI for the paired lifetime difference.
    ci=mu+[-1 1]*1.96*se;

    C=struct('gain_pct',100*mu/den, ...
        'ci_low_pct',100*ci(1)/den, ...
        'ci_high_pct',100*ci(2)/den);
end


% =========================================================================
% THE CR1632 LIFETIME-TRANSMISSION PAPER FIGURE
% =========================================================================
function plot_lifetime_tx_figure(study,headline,outDir)

    points=study.CR1632;
    M=headline.TX;

    % Extract every tested brownout-blind and brownout-aware operating point.
    xb=cellfun(@(p)p.blind.summary.tx_per_hour_mean,points);
    yb=cellfun(@(p)p.blind.summary.life_h_mean,points);
    xa=cellfun(@(p)p.aware.summary.tx_per_hour_mean,points);
    ya=cellfun(@(p)p.aware.summary.life_h_mean,points);

    % Identify the nondominated lifetime-TX tradeoff points.
    B=nondominated_points(xb,yb);
    W=nondominated_points(xa,ya);

    [B.x,ib]=sort(B.x);
    B.y=B.y(ib);
    [W.x,ia]=sort(W.x);
    W.y=W.y(ia);


    % Create the figure without opening an interactive window.
    fig=figure('Color','w','Visible','off','Position',[100 100 680 470]);
    ax=axes(fig);
    hold(ax,'on');
    box(ax,'on');
    grid(ax,'on');

    colors=ax.ColorOrder;
    cBlind=colors(1,:);
    cAware=colors(2,:);


    % Plot all tested operating points.
    hB=plot(ax,xb,yb,'o','LineStyle','none','Color',cBlind, ...
        'MarkerSize',6,'LineWidth',1.0,'DisplayName','Brownout-blind');

    hA=plot(ax,xa,ya,'s','LineStyle','none','Color',cAware, ...
        'MarkerSize',6,'LineWidth',1.0,'DisplayName','Brownout-aware');


    % Connect adjacent nondominated blind points. The largest empty TX gap
    % is dashed because no intermediate tested blind operating point exists.
    gapIdx=[];

    if numel(B.x)>1

        dx=diff(B.x);
        [~,gapIdx]=max(dx);

        for k=1:numel(B.x)-1

            style='-';
            if k==gapIdx
                style='--';
            end

            plot(ax,B.x(k:k+1),B.y(k:k+1),style,'Color',cBlind, ...
                'LineWidth',1.35,'HandleVisibility','off');
        end
    end


    % Connect adjacent nondominated aware points.
    if numel(W.x)>1
        plot(ax,W.x,W.y,'-','Color',cAware,'LineWidth',1.35, ...
            'HandleVisibility','off');
    end


    % Highlight the selected TX-matched blind/aware comparison.
    plot(ax,[M.blind.service M.aware.service], ...
        [M.blind.life M.aware.life],'k:','LineWidth',1.35, ...
        'HandleVisibility','off');

    hSel=plot(ax,M.blind.service,M.blind.life,'o','Color',cBlind, ...
        'MarkerFaceColor',cBlind,'MarkerSize',7,'LineWidth',1.0, ...
        'DisplayName','Selected TX match');

    plot(ax,M.aware.service,M.aware.life,'s','Color',cAware, ...
        'MarkerFaceColor',cAware,'MarkerSize',7,'LineWidth',1.0, ...
        'HandleVisibility','off');


    xlabel(ax,'Transmission rate (TX/h)');
    ylabel(ax,'Monitoring lifetime (h)');
    legend(ax,[hB hA hSel],'Location','best','Box','off');
    set(ax,'FontName','Times New Roman','FontSize',10,'LineWidth',0.8);


    % Save the camera-ready figure at 300 dpi.
    figFile=fullfile(outDir,'fig_lifetime_transmission_cr1632.png');
    exportgraphics(fig,figFile,'Resolution',300);
    close(fig);

    fprintf('Paper figure saved to %s\n',figFile);
end


% =========================================================================
% FIND NONDOMINATED LIFETIME-TRANSMISSION POINTS FOR THE FIGURE
% =========================================================================
function P=nondominated_points(x,y)

    x=x(:);
    y=y(:);
    keep=true(size(x));

    for i=1:numel(x)
        for j=1:numel(x)

            if i~=j && x(j)>=x(i) && y(j)>=y(i) && ...
                    (x(j)>x(i) || y(j)>y(i))

                keep(i)=false;
                break;
            end
        end
    end

    P.x=x(keep).';
    P.y=y(keep).';
end
