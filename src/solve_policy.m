function [policy,V,info] = solve_policy(cfg,bat,lambda,aware)
%SOLVE_POLICY Offline value iteration for blind or brownout-aware control.

    N=cfg.N_E; bin=bat.E_Wh*1000/N;
    V=zeros(N,3); policy=ones(N,3); % A0 is index 1

    for it=1:cfg.max_iter
        old=V;
        for e=1:N
            E=e*bin; soc=e/N;
            for op=1:3
                best=-inf; bestA=1;
                for ai=2:numel(cfg.actions)
                    a=cfg.actions(ai);
                    [Ec,Q,hard]=expected_step(cfg,bat,soc,op,a,aware);
                    if hard, continue; end

                    d=cfg.mean_dwell_s(op);
                    if Ec>=E
                        frac=E/max(Ec,eps);
                        future=0;
                    else
                        frac=1;
                        future=interp_future(old,(E-Ec)/bin,cfg.P_exit(op,:));
                    end
                    t=frac*d/3600;
                    value=t*(1+lambda*Q)+cfg.gamma*future;
                    if value>best
                        best=value; bestA=ai;
                    end
                end
                if isfinite(best), V(e,op)=best; policy(e,op)=bestA;
                else, V(e,op)=0; policy(e,op)=1; end
            end
        end
        delta=max(abs(V(:)-old(:)));
        if delta<cfg.tol, break; end
    end

    info.iterations=it;
    info.delta=delta;
    info.converged=delta<cfg.tol;
    info.aware=aware;
    info.lambda=lambda;
end

function [E_mWh,Q,hard] = expected_step(cfg,bat,soc,op,a,aware)
    bo=brownout_state(cfg,bat,soc,op,a,aware);
    hard=bo.state_hard;
    if hard, E_mWh=0; Q=0; return; end

    d=cfg.mean_dwell_s(op);
    P=(1-bo.sense_supp)*a.P_mW(op)+bo.sense_supp*cfg.P_base_mW(1);
    I=P/bat.V_nom;
    E_state=P*peukert_factor(bat,I)*d/3600;

    tx_raw=d/cfg.tx.period_s(op)*a.T(op);
    tx_del=tx_raw*(1-bo.tx_supp);
    E_one=cfg.tx.P_mW*cfg.tx.duration_s/3600+cfg.tx.startup_mJ/3600;
    I_tx=cfg.tx.P_mW/bat.V_nom;
    E_tx=tx_del*E_one*peukert_factor(bat,I_tx);
    E_mWh=E_state+E_tx;

    S=a.S(op)*(1-bo.sense_supp);
    T=a.T(op)*(1-bo.tx_supp); % relative to A1; intentionally uncapped
    Q=a.u*(0.60*S+0.40*T);
end

function f=interp_future(V,econt,p)
    N=size(V,1);
    econt=max(0,min(N,econt));
    lo=floor(econt); hi=ceil(econt);
    vlo=state_value(V,lo,p);
    vhi=state_value(V,hi,p);
    if lo==hi, f=vlo;
    else, f=(hi-econt)*vlo+(econt-lo)*vhi; end
end

function x=state_value(V,e,p)
    if e<1, x=0; else, x=p*V(e,:).'; end
end
