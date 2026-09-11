function sm = simulate_policy(cfg,bat,policy,nRuns,baseSeed)
%SIMULATE_POLICY Monte Carlo evaluation of a supplied control policy.
% The policy maps battery-energy level and physiological state to actions A0-A6.
%
% cfg      : model, SMM, action, and TX parameters
% bat      : selected battery model
% policy   : optimized MDP policy or fixed action
% nRuns    : number of Monte Carlo lifetime simulations
% baseSeed : base random seed for reproducibility
%
% sm contains mean lifetime, TX rate, QoS, termination statistics,
% action usage, and individual-run results.

    % Storage for lifetime, service, residual SoC, and termination outcomes
    life=zeros(nRuns,1); txh=zeros(nRuns,1); qos=zeros(nRuns,1);
    soc=zeros(nRuns,1); hard=zeros(nRuns,1);
    a0=zeros(nRuns,1);   % terminal fallback action
    dep=zeros(nRuns,1);  % energy-depletion termination

    % Record how often and how long each action is used overall and by state
    nA=numel(cfg.actions); nS=numel(cfg.states);
    actionCount=zeros(nRuns,nA);
    actionTime=zeros(nRuns,nA);
    actionStateCount=zeros(nRuns,nA,nS);
    actionStateTime=zeros(nRuns,nA,nS);

    % Run independent, reproducible lifetime simulations
    for r=1:nRuns
        rng(baseSeed+r,'twister');
        x=one_run(cfg,bat,policy);
        life(r)=x.life_h; txh(r)=x.tx_h; qos(r)=x.qos;
        soc(r)=x.soc; hard(r)=x.term_hard; a0(r)=x.term_a0; dep(r)=x.term_dep;
        actionCount(r,:)=x.action_count;
        actionTime(r,:)=x.action_time_s;
        actionStateCount(r,:,:)=reshape(x.action_state_count,[1 nA nS]);
        actionStateTime(r,:,:)=reshape(x.action_state_time_s,[1 nA nS]);
    end
    
    % Average performance and termination statistics across Monte Carlo runs
    sm.life_h_mean=mean(life);
    sm.tx_per_hour_mean=mean(txh);
    sm.qos_time_mean=mean(qos);
    sm.residual_soc_mean=mean(soc);
    sm.terminal_state_hard_rate=mean(hard);
    sm.terminal_A0_rate=mean(a0);
    sm.terminal_depletion_rate=mean(dep);

    % Overall action-selection and completed-time fractions
    totalCount=sum(actionCount,'all');
    totalTime=sum(actionTime,'all');
    sm.action_selection_fraction=sum(actionCount,1)/max(totalCount,eps);
    sm.action_time_fraction=sum(actionTime,1)/max(totalTime,eps);

    % Action usage conditioned on physiological state
    sumStateCount=squeeze(sum(actionStateCount,1)); % action x state
    sumStateTime=squeeze(sum(actionStateTime,1));   % action x state
    stateCountDen=sum(sumStateCount,1);
    stateTimeDen=sum(sumStateTime,1);
    sm.action_selection_fraction_by_state= ...
        sumStateCount./max(stateCountDen,eps);
    sm.action_time_fraction_by_state= ...
        sumStateTime./max(stateTimeDen,eps);

    % Preserve run-level outputs for statistical and matched-service analysis
    sm.raw.life_h=life;
    sm.raw.tx_per_hour=txh;
    sm.raw.qos_time=qos;
    sm.raw.residual_soc=soc;
    sm.raw.terminal_state_hard=hard;
    sm.raw.terminal_A0=a0;
    sm.raw.terminal_depletion=dep;
    sm.raw.action_count=actionCount;
    sm.raw.action_time_s=actionTime;
    sm.raw.action_state_count=actionStateCount;
    sm.raw.action_state_time_s=actionStateTime;
end

function out=one_run(cfg,bat,policy)
    % Start with a full battery and LOW physiological state
    C=bat.E_Wh*1000;   % battery capacity in mWh
    E=C;               % remaining energy
    op=2;              % initial physiological state: LOW
    t=0; ntx=0; qtime=0;

    % Termination indicators: voltage violation, A0 fallback, or depletion
    termHard=0; termA0=0; termDep=0;

    nA=numel(cfg.actions); nS=numel(cfg.states);
    actionCount=zeros(1,nA); actionTime=zeros(1,nA);
    actionStateCount=zeros(nA,nS); actionStateTime=zeros(nA,nS);
    
    % Each iteration represents one physiological-state dwell
    maxSteps=1e6;
    for step=1:maxSteps %#ok<NASGU>
        if E<=eps, termDep=1; break; end
        % Current energy-based state of charge
        soc=E/C;
        % Select the action prescribed for the current energy bin and physiological state
        if isscalar(policy)
            ai=policy; % fixed-action evaluation
        else
            ebin=max(1,min(cfg.N_E,ceil(soc*cfg.N_E)));
            ai=policy(ebin,op); % the policy may return a different action at each step changes
% once the physiological state op changes, or the battery energy bin ebin
% changes.

        end

        % Record the selected action before checking terminal conditions
        actionCount(ai)=actionCount(ai)+1;
        actionStateCount(ai,op)=actionStateCount(ai,op)+1;

        % A0 is the terminal fallback when active monitoring cannot continue
        if ai==1, termA0=1; break; end 

        a=cfg.actions(ai);

        % Sample an empirical MMASH dwell duration for the current state
        d=sample_dwell(cfg.dwell_s{op});

        % Evaluate sensing and TX loaded-voltage conditions at the current SoC
        bo=brownout_state(cfg,bat,soc,op,a,true);
        if bo.state_hard, termHard=1; break; end

        % Effective sensing power after any warning-level sensing reduction
        P=(1-bo.sense_supp)*a.P_mW(op)+bo.sense_supp*cfg.P_base_mW(1);
        % State energy consumption with Peukert-like rate derating
        I=P/bat.V_nom;
        E_state=P*peukert_factor(bat,I)*d/3600;
        
        % Poisson mean lambda (Expected requested TX count during this
        % dwell)
        lambdaTx=d/cfg.tx.period_s(op)*a.T(op);

        % Generating random number of requested TX events (Sample the requested TX count from the Poisson model)
        nRaw=poisson_draw(lambdaTx);

        % Apply voltage-dependent TX suppression
        keep=1-bo.tx_supp;
        if keep<=0, nTx=0;
        elseif keep>=1, nTx=nRaw;
        else, nTx=sum(rand(nRaw,1)<keep); end

        % Energy per delivered TX event, including startup energy
        E_one=cfg.tx.P_mW*cfg.tx.duration_s/3600+cfg.tx.startup_mJ/3600;

        % Total TX energy with Peukert-like rate derating
        I_tx=cfg.tx.P_mW/bat.V_nom;
        E_tx=nTx*E_one*peukert_factor(bat,I_tx);

        % Determine whether the remaining battery can complete the entire dwell
        demand=E_state+E_tx;
        frac=min(1,E/max(demand,eps));
        done=frac*d;

        % Delivered sensing/TX service after voltage-warning suppression
        S=a.S(op)*(1-bo.sense_supp);
        T=a.T(op)*(1-bo.tx_supp);

        % Relative service score
        Q=a.u*(0.60*S+0.40*T);

        % Relative service score
        t=t+done;
        ntx=ntx+frac*nTx;
        qtime=qtime+Q*done;
        E=max(0,E-frac*demand);

        % Accumulate completed monitoring time for the selected action
        actionTime(ai)=actionTime(ai)+done; 
        actionStateTime(ai,op)=actionStateTime(ai,op)+done;

        % Partial dwell completion indicates energy depletion
        if frac<1, termDep=1; break; end
        % Sample the next physiological state using the SMM exit probabilities
        op=draw_state(cfg.P_exit(op,:));
    end

    if ~(termHard||termA0||termDep)
        error('Simulation reached maxSteps without a terminal condition.');
    end

    % Sample the next physiological state using the SMM exit probabilities
    h=t/3600;
    out.life_h=h;
    out.tx_h=ntx/max(h,eps);
    out.qos=qtime/max(t,eps);
    out.soc=E/C;
    out.term_hard=termHard;
    out.term_a0=termA0;
    out.term_dep=termDep;
    out.action_count=actionCount;
    out.action_time_s=actionTime;
    out.action_state_count=actionStateCount;
    out.action_state_time_s=actionStateTime;
end

function d=sample_dwell(pool)
    % Sample one empirical dwell duration from the MMASH-derived distribution
    d=pool(randi(numel(pool)));
end

function s=draw_state(p)
    % Sample the next physiological state from the SMM exit probabilities
    c=cumsum(p/sum(p));
    s=find(rand<=c,1,'first');
end

function n=poisson_draw(lambda)
    % Sample a Poisson TX count; use a normal approximation for large means
    lambda=max(lambda,0);
    if lambda==0, n=0; return; end
    if lambda<30
        L=exp(-lambda); k=0; p=1;
        while p>L, k=k+1; p=p*rand; end
        n=k-1;
    else
        n=max(0,round(lambda+sqrt(lambda)*randn));
    end
end
