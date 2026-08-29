function bo = brownout_state(cfg,bat,soc,op,a,enabled)
%BROWNOUT_STATE Evaluate state and TX loaded-voltage conditions.

    soc=max(0,min(1,soc));
    V0=bat.V_min+(bat.I_ref_mA/1000)*bat.R_int;
    k=bat.ocv_knee_soc; h=bat.ocv_low_span;
    if soc<k, g=h*soc/k;
    else, g=h+(1-h)*(soc-k)/(1-k); end
    Voc=V0+(bat.V_nom-V0)*g;

    bo.Voc=Voc;
    bo.Vstate=Voc-(a.I_peak_mA(op)/1000)*bat.R_int;
    bo.Vtx=Voc-(cfg.tx.I_peak_mA/1000)*bat.R_int;
    bo.state_warn=false; bo.state_hard=false;
    bo.tx_warn=false; bo.tx_hard=false;
    bo.sense_supp=0; bo.tx_supp=0;

    if ~enabled, return; end

    txActive=a.T(op)>0;
    bo.state_warn=bo.Vstate<=bat.V_warn;
    bo.state_hard=bo.Vstate<=bat.V_min;
    bo.tx_warn=txActive && bo.Vtx<=bat.V_warn;
    bo.tx_hard=txActive && bo.Vtx<=bat.V_min;

    if bo.state_warn, bo.sense_supp=.50; end
    if bo.state_hard, bo.sense_supp=1.00; end
    if bo.tx_warn, bo.tx_supp=.50; end
    if bo.tx_hard, bo.tx_supp=1.00; end
end
