function sm = simulate_policy(cfg,bat,policy,nRuns,baseSeed)
%SIMULATE_POLICY Physically evaluate one policy with Monte Carlo runs.

    life=zeros(nRuns,1); txh=zeros(nRuns,1); qos=zeros(nRuns,1);
    soc=zeros(nRuns,1); hard=zeros(nRuns,1); a0=zeros(nRuns,1); dep=zeros(nRuns,1);

    for r=1:nRuns
        rng(baseSeed+r,'twister');
        x=one_run(cfg,bat,policy);
        life(r)=x.life_h; txh(r)=x.tx_h; qos(r)=x.qos;
        soc(r)=x.soc; hard(r)=x.term_hard; a0(r)=x.term_a0; dep(r)=x.term_dep;
    end

    sm.life_h_mean=mean(life);
    sm.tx_per_hour_mean=mean(txh);
    sm.qos_time_mean=mean(qos);
    sm.residual_soc_mean=mean(soc);
    sm.terminal_state_hard_rate=mean(hard);
    sm.terminal_A0_rate=mean(a0);
    sm.terminal_depletion_rate=mean(dep);
    sm.raw.life_h=life;
    sm.raw.tx_per_hour=txh;
    sm.raw.qos_time=qos;
    sm.raw.residual_soc=soc;
    sm.raw.terminal_state_hard=hard;
    sm.raw.terminal_A0=a0;
    sm.raw.terminal_depletion=dep;
end

function out=one_run(cfg,bat,policy)
    C=bat.E_Wh*1000; E=C; op=2; t=0; ntx=0; qtime=0;
    termHard=0; termA0=0; termDep=0;

    maxSteps=1e6;
    for step=1:maxSteps %#ok<NASGU>
        if E<=eps, termDep=1; break; end
        soc=E/C;
        if isscalar(policy)
            ai=policy;
        else
            ebin=max(1,min(cfg.N_E,ceil(soc*cfg.N_E)));
            ai=policy(ebin,op);
        end
        if ai==1, termA0=1; break; end

        a=cfg.actions(ai);
        d=sample_dwell(cfg.dwell_s{op});
        bo=brownout_state(cfg,bat,soc,op,a,true);
        if bo.state_hard, termHard=1; break; end

        P=(1-bo.sense_supp)*a.P_mW(op)+bo.sense_supp*cfg.P_base_mW(1);
        I=P/bat.V_nom;
        E_state=P*peukert_factor(bat,I)*d/3600;

        lambdaTx=d/cfg.tx.period_s(op)*a.T(op);
        nRaw=poisson_draw(lambdaTx);
        keep=1-bo.tx_supp;
        if keep<=0, nTx=0;
        elseif keep>=1, nTx=nRaw;
        else, nTx=sum(rand(nRaw,1)<keep); end

        E_one=cfg.tx.P_mW*cfg.tx.duration_s/3600+cfg.tx.startup_mJ/3600;
        I_tx=cfg.tx.P_mW/bat.V_nom;
        E_tx=nTx*E_one*peukert_factor(bat,I_tx);
        demand=E_state+E_tx;
        frac=min(1,E/max(demand,eps));
        done=frac*d;

        S=a.S(op)*(1-bo.sense_supp);
        T=a.T(op)*(1-bo.tx_supp);
        Q=a.u*(0.60*S+0.40*T);

        t=t+done;
        ntx=ntx+frac*nTx;
        qtime=qtime+Q*done;
        E=max(0,E-frac*demand);

        if frac<1, termDep=1; break; end
        op=draw_state(cfg.P_exit(op,:));
    end

    if ~(termHard||termA0||termDep)
        error('Simulation reached maxSteps without a terminal condition.');
    end

    h=t/3600;
    out.life_h=h;
    out.tx_h=ntx/max(h,eps);
    out.qos=qtime/max(t,eps);
    out.soc=E/C;
    out.term_hard=termHard;
    out.term_a0=termA0;
    out.term_dep=termDep;
end

function d=sample_dwell(pool)
    d=pool(randi(numel(pool)));
end

function s=draw_state(p)
    c=cumsum(p/sum(p));
    s=find(rand<=c,1,'first');
end

function n=poisson_draw(lambda)
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
