function bo = brownout_state(cfg,bat,soc,op,a,enabled)
% BROWNOUT_STATE checks whether the selected action is electrically safe for the current battery state.
% Its inputs are:
% cfg = general model settings
% bat = current battery parameters
% soc = current state of charge
% op = current physiological state: SLEEP/LOW/HIGH
% a = selected firmware action A0–A6
% enabled = whether brownout logic is active
% It returns bo, a structure containing voltages and warning/suppression flags.
    
    soc=max(0,min(1,soc)); % This prevents invalid SoC values: below 0 becomes 0, above 1 becomes 1
    V0=bat.V_min+(bat.I_ref_mA/1000)*bat.R_int; % The modeled open-circuit voltage at 0% SoC (empty-cell).
    k=bat.ocv_knee_soc; h=bat.ocv_low_span; % Read the OCV curve-shape parameters knee at 35% SoC, 65% of the modeled OCV change occurs below that knee
    % Compute the normalized piecewise OCV shape g(s)
    if soc<k, g=h*soc/k;
    else, g=h+(1-h)*(soc-k)/(1-k); end
    % Compute open-circuit voltage (battery voltage before applying any load)
    Voc=V0+(bat.V_nom-V0)*g;
    % Compute loaded voltage under sensing and TX peaks
    bo.Voc=Voc;
    bo.Vstate=Voc-(a.I_peak_mA(op)/1000)*bat.R_int;
    bo.Vtx=Voc-(cfg.tx.I_peak_mA/1000)*bat.R_int;
    % Initialize all warning flags as false
    bo.state_warn=false; bo.state_hard=false;
    bo.tx_warn=false; bo.tx_hard=false;
    bo.sense_supp=0; bo.tx_supp=0;

    if ~enabled, return; end % If brownout checking is disabled, stop here (important for the brownout-blind optimizer)

    txActive=a.T(op)>0; % If the selected action requests no TX in that state, then there is no reason to check TX brownout.
    % Check sensing voltage against warning and minimum limits
    bo.state_warn=bo.Vstate<=bat.V_warn;
    bo.state_hard=bo.Vstate<=bat.V_min;
    % Check TX voltage that matters when active
    bo.tx_warn=txActive && bo.Vtx<=bat.V_warn;
    bo.tx_hard=txActive && bo.Vtx<=bat.V_min;

    % Apply graceful degradation:
    % above Vwarn: 100% sensing / 100% requested TX
    % at or below Vwarn: 50% sensing / 50% requested TX
    % at or below Vmin: sensing terminates; TX is fully suppressed

    if bo.state_warn, bo.sense_supp=.50; end
    if bo.state_hard, bo.sense_supp=1.00; end
    if bo.tx_warn, bo.tx_supp=.50; end
    if bo.tx_hard, bo.tx_supp=1.00; end
end
