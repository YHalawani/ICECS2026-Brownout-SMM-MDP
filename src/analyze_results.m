function [MatchedService,headline] = analyze_results(study,cfg,outDir)
%ANALYZE_RESULTS Compare blind and aware policies at similar delivered service.
%
% For each battery, the function:
%   1) builds the nondominated lifetime-service front,
%   2) finds the blind/aware pair with the closest delivered service,
%   3) computes the corresponding lifetime gain, and
%   4) reports confidence intervals.
%
% Comparisons are performed separately for:
%   TX  : delivered transmissions per hour
%   QoS : overall delivered service score
%
% CR1632 confidence intervals additionally repeat the complete
% policy-selection and service-matching procedure within bootstrap samples.

    metrics={'TX','QoS'};
    rows={};
    headline=struct();

    % Analyze every battery independently
    for b=1:numel(cfg.battery_names)

        name=cfg.battery_names{b};
        points=study.(name);

        % Perform both TX-matched and QoS-matched comparisons
        for m=1:numel(metrics)

            metric=metrics{m};

            % Construct nondominated lifetime-service fronts for the
            % brownout-blind and brownout-aware policies
            B=front(points,'blind',metric,[]);
            A=front(points,'aware',metric,[]);

            % Select the blind/aware pair having the closest service level
            M=best_pair(B,A, ...
                cfg.match_preferred_pct,cfg.match_fallback_pct);

            % Lifetime gain and paired normal-approximation CI for the
            % selected pair
            C=paired_gain( ...
                M.blind.sm.raw.life_h,M.aware.sm.raw.life_h);

            boot=struct('ci',[NaN NaN],'preferred_rate',NaN, ...
                'fallback_rate',NaN,'unmatched_rate',NaN);


            % -------------------------------------------------------------
            % Selection-aware bootstrap for the CR1632 headline results
            % -------------------------------------------------------------
            if strcmp(name,'CR1632')

                % Use separate fixed seeds for TX- and QoS-matched analyses
                % so that the reported intervals are reproducible
                switch metric

                    case 'TX'
                        bootSeed=cfg.bootstrap_seed_tx;

                    case 'QoS'
                        bootSeed=cfg.bootstrap_seed_qos;

                    otherwise
                        error('Unknown bootstrap metric: %s',metric);

                end

                % Repeat front construction, service matching, and lifetime
                % gain calculation within every bootstrap replicate
                boot=selection_bootstrap(points,metric,cfg,bootSeed);

                % Replace the simple paired CI with the selection-aware
                % bootstrap interval for the headline CR1632 comparison
                C.ci_low_pct=boot.ci(1);
                C.ci_high_pct=boot.ci(2);

                headline.(metric)=M;
                headline.(metric).ci=boot.ci;
                headline.(metric).bootstrap=boot;

            end


            % Store one summary row for this battery/service metric
            rows(end+1,:)={name,metric,M.blind.lambda,M.aware.lambda, ...
                M.blind.service,M.aware.service,M.mismatch,M.tier, ...
                M.blind.life,M.aware.life,C.gain_pct,C.ci_low_pct,C.ci_high_pct, ...
                M.blind.sm.tx_per_hour_mean,M.aware.sm.tx_per_hour_mean, ...
                M.blind.sm.qos_time_mean,M.aware.sm.qos_time_mean, ...
                boot.preferred_rate,boot.fallback_rate,boot.unmatched_rate}; %#ok<AGROW>

        end
    end


    % Convert all matched comparisons to a table
    MatchedService=cell2table(rows,'VariableNames',{ ...
        'Battery','Metric','BlindLambda','AwareLambda','BlindService','AwareService', ...
        'Mismatch_pct','Tier','BlindLife_h','AwareLife_h','Gain_pct','CI95Low_pct', ...
        'CI95High_pct','BlindTX_h','AwareTX_h','BlindQoS','AwareQoS', ...
        'BootstrapMatch2Fraction','BootstrapMatch5Fraction','BootstrapUnmatchedFraction'});

    % Save analysis results for reproducibility
    writetable(MatchedService,fullfile(outDir,'matched_service.csv'));

end



% =========================================================================
% BUILD NONDOMINATED LIFETIME-SERVICE FRONT
% =========================================================================
function pts=front(points,ptype,metric,idx)

    n=numel(points);

    pts=repmat( ...
        struct('lambda',0,'service',0,'life',0,'sm',[]),1,n);


    % Obtain lifetime and delivered service for every lambda_QoS value
    for k=1:n

        sm=points{k}.(ptype).summary;

        if isempty(idx)

            % Original Monte Carlo means
            life=sm.life_h_mean;

            if strcmp(metric,'TX')
                svc=sm.tx_per_hour_mean;
            else
                svc=sm.qos_time_mean;
            end

        else

            % Bootstrap means using the resampled run indices
            life=mean(sm.raw.life_h(idx));

            if strcmp(metric,'TX')
                svc=mean(sm.raw.tx_per_hour(idx));
            else
                svc=mean(sm.raw.qos_time(idx));
            end

        end

        pts(k)=struct( ...
            'lambda',points{k}.lambda, ...
            'service',svc, ...
            'life',life, ...
            'sm',sm);

    end


    % ---------------------------------------------------------------------
    % Remove dominated operating points.
    %
    % A point is dominated if another tested lambda provides:
    %   >= lifetime AND >= service,
    % with at least one being strictly better.
    % ---------------------------------------------------------------------
    keep=true(1,n);

    for i=1:n
        for j=1:n

            if i~=j && ...
                    pts(j).service>=pts(i).service && ...
                    pts(j).life>=pts(i).life && ...
                    (pts(j).service>pts(i).service || ...
                     pts(j).life>pts(i).life)

                keep(i)=false;
                break

            end
        end
    end

    % Keep only the lifetime-service tradeoff frontier
    pts=pts(keep);

end



% =========================================================================
% SELECT THE CLOSEST BLIND/AWARE SERVICE PAIR
% =========================================================================
function M=best_pair(B,A,pref,fallback)

    C=[];

    % Compare every point on the blind front with every point on the
    % brownout-aware front
    for i=1:numel(B)
        for j=1:numel(A)

            z.bi=i;
            z.ai=j;

            % Symmetric percentage difference in delivered service
            z.mis=mismatch(B(i).service,A(j).service);

            % Used only to break exact mismatch ties
            z.meanService=mean([B(i).service A(j).service]);

            C=[C z]; %#ok<AGROW>

        end
    end


    mis=[C.mis];

    % ---------------------------------------------------------------------
    % Service-matching hierarchy:
    %   preferred : mismatch <= 2%
    %   fallback  : mismatch <= 5%
    %   unmatched : no pair satisfies the fallback threshold
    % ---------------------------------------------------------------------
    if any(mis<=pref)

        eligible=find(mis<=pref);
        tier='<=2%';

    elseif any(mis<=fallback)

        eligible=find(mis<=fallback);
        tier='<=5%';

    else

        % Still report the closest available pair, but label it unmatched
        eligible=1:numel(C);
        tier='UNMATCHED';

    end


    % Choose the eligible pair having the smallest service mismatch
    best=min(mis(eligible));

    short=eligible(abs(mis(eligible)-best)<=1e-12);


    % If two pairs have exactly the same mismatch, prefer the pair
    % operating at the higher average delivered service
    if numel(short)>1

        [~,q]=max([C(short).meanService]);
        k=short(q);

    else

        k=short(1);

    end


    % Return the selected blind/aware comparison
    M=struct( ...
        'blind',B(C(k).bi), ...
        'aware',A(C(k).ai), ...
        'mismatch',C(k).mis, ...
        'tier',tier);

end



% =========================================================================
% SYMMETRIC SERVICE MISMATCH
% =========================================================================
function p=mismatch(a,b)

    % Percentage difference relative to the mean of the two service values
    d=mean(abs([a b]));

    if d<=eps
        p=0;
    else
        p=100*abs(a-b)/d;
    end

end



% =========================================================================
% PAIRED LIFETIME GAIN
% =========================================================================
function C=paired_gain(ref,test)

    ref=ref(:);
    test=test(:);

    % Run-by-run lifetime difference between aware and blind simulations
    d=test-ref;

    % Blind lifetime is the reference for percentage improvement
    den=mean(ref);

    % Mean paired lifetime difference
    mu=mean(d);

    % Standard error of the paired differences
    se=std(d)/sqrt(numel(d));

    % 95% normal-approximation confidence interval
    ci=mu+[-1 1]*1.96*se;


    % Express lifetime difference and CI relative to blind mean lifetime
    C=struct( ...
        'gain_pct',100*mu/den, ...
        'ci_low_pct',100*ci(1)/den, ...
        'ci_high_pct',100*ci(2)/den);

end



% =========================================================================
% SELECTION-AWARE BOOTSTRAP
% =========================================================================
function out=selection_bootstrap(points,metric,cfg,seed)

    % Number of Monte Carlo lifetime runs available per policy
    n=numel(points{1}.blind.summary.raw.life_h);

    gain=nan(cfg.bootstrap_reps,1);
    tier=zeros(cfg.bootstrap_reps,1);


    % Preserve the caller's random-number state
    old=rng;
    cleanup=onCleanup(@()rng(old)); %#ok<NASGU>

    % Fixed bootstrap seed for reproducibility
    rng(seed,'twister');


    % ---------------------------------------------------------------------
    % In each bootstrap replicate:
    %   1) resample MC runs with replacement,
    %   2) rebuild blind and aware nondominated fronts,
    %   3) repeat service matching,
    %   4) calculate the selected lifetime gain.
    %
    % This includes uncertainty caused by the service-matching selection,
    % not only uncertainty in the lifetime of one preselected pair.
    % ---------------------------------------------------------------------
    for r=1:cfg.bootstrap_reps

        % Resample the same run indices across operating points
        idx=randi(n,n,1);

        B=front(points,'blind',metric,idx);
        A=front(points,'aware',metric,idx);

        M=best_pair( ...
            B,A,cfg.match_preferred_pct,cfg.match_fallback_pct);


        % Record which matching tier was achieved
        if strcmp(M.tier,'<=2%')

            tier(r)=2;

        elseif strcmp(M.tier,'<=5%')

            tier(r)=5;

        end


        % If no pair satisfies the 5% fallback threshold, best_pair still
        % returns the closest pair, while this replicate remains classified
        % as unmatched.
        gain(r)=100*(M.aware.life-M.blind.life)/M.blind.life;

    end


    % Remove invalid values and sort bootstrap lifetime gains
    x=sort(gain(isfinite(gain)));

    % Percentile 95% confidence interval
    out.ci=[percentile(x,2.5) percentile(x,97.5)];

    % Fraction of bootstrap samples falling into each matching tier
    out.preferred_rate=mean(tier==2);
    out.fallback_rate=mean(tier==5);
    out.unmatched_rate=mean(tier==0);

    out.seed=seed;

end



% =========================================================================
% LINEARLY INTERPOLATED SAMPLE PERCENTILE
% =========================================================================
function y=percentile(x,p)

    if isempty(x)
        y=NaN;
        return;
    end

    % Fractional location of percentile within the sorted sample
    q=1+(numel(x)-1)*p/100;

    a=floor(q);
    b=ceil(q);

    if a==b

        y=x(a);

    else

        % Linear interpolation between neighboring ordered samples
        y=x(a)+(q-a)*(x(b)-x(a));

    end

end