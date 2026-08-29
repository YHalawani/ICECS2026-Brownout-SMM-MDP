function [MatchedService,headline] = analyze_results(study,cfg,outDir)
%ANALYZE_RESULTS Match blind and aware policies at similar delivered service.

    metrics={'TX','QoS'}; rows={}; headline=struct();

    for b=1:numel(cfg.battery_names)
        name=cfg.battery_names{b}; points=study.(name);

        for m=1:numel(metrics)
            metric=metrics{m};
            B=front(points,'blind',metric,[]);
            A=front(points,'aware',metric,[]);
            M=best_pair(B,A,cfg.match_preferred_pct,cfg.match_fallback_pct);
            C=paired_gain(M.blind.sm.raw.life_h,M.aware.sm.raw.life_h);
            boot=struct('ci',[NaN NaN],'preferred_rate',NaN, ...
                'fallback_rate',NaN,'unmatched_rate',NaN);

            % Repeat the complete service-matching procedure in bootstrap
            % samples for the two CR1632 headline comparisons.
            if strcmp(name,'CR1632')
                boot=selection_bootstrap(points,metric,cfg,cfg.bootstrap_seed);
                C.ci_low_pct=boot.ci(1);
                C.ci_high_pct=boot.ci(2);
                headline.(metric)=M;
                headline.(metric).ci=boot.ci;
                headline.(metric).bootstrap=boot;
            end

            rows(end+1,:)={name,metric,M.blind.lambda,M.aware.lambda, ...
                M.blind.service,M.aware.service,M.mismatch,M.tier, ...
                M.blind.life,M.aware.life,C.gain_pct,C.ci_low_pct,C.ci_high_pct, ...
                M.blind.sm.tx_per_hour_mean,M.aware.sm.tx_per_hour_mean, ...
                M.blind.sm.qos_time_mean,M.aware.sm.qos_time_mean, ...
                boot.preferred_rate,boot.fallback_rate,boot.unmatched_rate}; %#ok<AGROW>
        end
    end

    MatchedService=cell2table(rows,'VariableNames',{ ...
        'Battery','Metric','BlindLambda','AwareLambda','BlindService','AwareService', ...
        'Mismatch_pct','Tier','BlindLife_h','AwareLife_h','Gain_pct','CI95Low_pct', ...
        'CI95High_pct','BlindTX_h','AwareTX_h','BlindQoS','AwareQoS', ...
        'BootstrapMatch2Fraction','BootstrapMatch5Fraction','BootstrapUnmatchedFraction'});

    writetable(MatchedService,fullfile(outDir,'matched_service.csv'));
end

function pts=front(points,ptype,metric,idx)
    n=numel(points);
    pts=repmat(struct('lambda',0,'service',0,'life',0,'sm',[]),1,n);

    for k=1:n
        sm=points{k}.(ptype).summary;
        if isempty(idx)
            life=sm.life_h_mean;
            if strcmp(metric,'TX'), svc=sm.tx_per_hour_mean;
            else, svc=sm.qos_time_mean; end
        else
            life=mean(sm.raw.life_h(idx));
            if strcmp(metric,'TX'), svc=mean(sm.raw.tx_per_hour(idx));
            else, svc=mean(sm.raw.qos_time(idx)); end
        end
        pts(k)=struct('lambda',points{k}.lambda,'service',svc,'life',life,'sm',sm);
    end

    keep=true(1,n);
    for i=1:n
        for j=1:n
            if i~=j && pts(j).service>=pts(i).service && pts(j).life>=pts(i).life && ...
                    (pts(j).service>pts(i).service || pts(j).life>pts(i).life)
                keep(i)=false;
                break
            end
        end
    end
    pts=pts(keep);
end

function M=best_pair(B,A,pref,fallback)
    C=[];
    for i=1:numel(B)
        for j=1:numel(A)
            z.bi=i;
            z.ai=j;
            z.mis=mismatch(B(i).service,A(j).service);
            z.meanService=mean([B(i).service A(j).service]);
            C=[C z]; %#ok<AGROW>
        end
    end

    mis=[C.mis];
    if any(mis<=pref)
        eligible=find(mis<=pref); tier='<=2%';
    elseif any(mis<=fallback)
        eligible=find(mis<=fallback); tier='<=5%';
    else
        eligible=1:numel(C); tier='UNMATCHED';
    end

    best=min(mis(eligible));
    short=eligible(abs(mis(eligible)-best)<=1e-12);
    if numel(short)>1
        [~,q]=max([C(short).meanService]); k=short(q);
    else
        k=short(1);
    end

    M=struct('blind',B(C(k).bi),'aware',A(C(k).ai), ...
        'mismatch',C(k).mis,'tier',tier);
end

function p=mismatch(a,b)
    d=mean(abs([a b]));
    if d<=eps, p=0; else, p=100*abs(a-b)/d; end
end

function C=paired_gain(ref,test)
    ref=ref(:); test=test(:);
    d=test-ref; den=mean(ref); mu=mean(d);
    se=std(d)/sqrt(numel(d));
    ci=mu+[-1 1]*1.96*se;
    C=struct('gain_pct',100*mu/den, ...
        'ci_low_pct',100*ci(1)/den,'ci_high_pct',100*ci(2)/den);
end

function out=selection_bootstrap(points,metric,cfg,seed)
    n=numel(points{1}.blind.summary.raw.life_h);
    gain=nan(cfg.bootstrap_reps,1);
    tier=zeros(cfg.bootstrap_reps,1);

    old=rng;
    cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
    rng(seed,'twister');

    for r=1:cfg.bootstrap_reps
        idx=randi(n,n,1);
        B=front(points,'blind',metric,idx);
        A=front(points,'aware',metric,idx);
        M=best_pair(B,A,cfg.match_preferred_pct,cfg.match_fallback_pct);

        if strcmp(M.tier,'<=2%')
            tier(r)=2;
        elseif strcmp(M.tier,'<=5%')
            tier(r)=5;
        end

        % If no pair meets the fallback threshold, best_pair reports the
        % closest pair and the replicate is also counted as unmatched.
        gain(r)=100*(M.aware.life-M.blind.life)/M.blind.life;
    end

    x=sort(gain(isfinite(gain)));
    out.ci=[percentile(x,2.5) percentile(x,97.5)];
    out.preferred_rate=mean(tier==2);
    out.fallback_rate=mean(tier==5);
    out.unmatched_rate=mean(tier==0);
end

function y=percentile(x,p)
    if isempty(x), y=NaN; return; end
    q=1+(numel(x)-1)*p/100;
    a=floor(q); b=ceil(q);
    if a==b, y=x(a);
    else, y=x(a)+(q-a)*(x(b)-x(a)); end
end
