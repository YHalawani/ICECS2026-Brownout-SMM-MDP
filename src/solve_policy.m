function [policy,V,info] = solve_policy(cfg,bat,lambda,aware)
%SOLVE_POLICY Find the optimal firmware policy using value iteration.
%
% The MDP state is:
%       (remaining battery energy, physiological state)
%
% For each state, test actions A1-A6 and keep the action with the highest
% value based on current reward and expected future reward.
%
% cfg    : model, SMM, action, TX, and optimization parameters
% bat    : selected battery model
% lambda : QoS reward weight lambda_QoS
% aware  : true  -> brownout-aware optimization
%          false -> brownout-blind optimization
%
% policy : optimal action index for every energy/state combination
% V      : value function for every energy/state combination
% info   : convergence information


    % Divide total battery energy into N discrete energy bins
    N=cfg.N_E;
    bin=bat.E_Wh*1000/N;       % energy represented by one bin [mWh]

    % V(e,op) stores the value of each energy/state combination
    % policy(e,op) stores the selected action for that combination
    V=zeros(N,3);
    policy=ones(N,3);          % initialize to A0; A0 is action index 1


    % =====================================================================
    % VALUE ITERATION
    % Repeatedly update V until the values stop changing significantly.
    % =====================================================================
    for it=1:cfg.max_iter

        % Keep the previous value function for Bellman updates
        old=V;

        % -------------------------------------------------------------
        % Evaluate every battery-energy bin
        % -------------------------------------------------------------
        for e=1:N

            E=e*bin;           % remaining battery energy [mWh]
            soc=e/N;           % corresponding SoC in [0,1]

            % ---------------------------------------------------------
            % Evaluate each physiological state:
            % op = 1 SLEEP, 2 LOW, 3 HIGH
            % ---------------------------------------------------------
            for op=1:3

                best=-inf;     % best Bellman value found so far
                bestA=1;       % default fallback action A0

                % -----------------------------------------------------
                % Test all active firmware actions A1-A6.
                % MATLAB index 1 is A0, so active actions start at ai=2.
                % -----------------------------------------------------
                for ai=2:numel(cfg.actions)

                    a=cfg.actions(ai);

                    % Compute the expected energy use, delivered QoS,
                    % and brownout feasibility of this candidate action
                    [Ec,Q,hard]=expected_step( ...
                        cfg,bat,soc,op,a,aware);

                    % In brownout-aware optimization, an action whose
                    % sensing load violates Vmin is not allowed
                    if hard
                        continue;
                    end


                    % Mean dwell duration of the current physiological state
                    d=cfg.mean_dwell_s(op);

                    % -------------------------------------------------
                    % Determine how much of the expected dwell can be
                    % completed with the currently remaining energy
                    % -------------------------------------------------
                    if Ec>=E

                        % Remaining energy cannot support the full dwell
                        frac=E/max(Ec,eps);

                        % Battery depletes during this dwell, therefore
                        % no future state value remains
                        future=0;

                    else

                        % The full dwell can be completed
                        frac=1;

                        % Continuous post-action energy:
                        %       E' = E - Ec
                        %
                        % E' usually lies between two discrete grid bins,
                        % so its future value is linearly interpolated.
                        future=interp_future( ...
                            old,(E-Ec)/bin,cfg.P_exit(op,:));

                    end


                    % Completed dwell duration in hours
                    t=frac*d/3600;

                    % -------------------------------------------------
                    % Bellman value for this candidate action:
                    %
                    % immediate lifetime/QoS reward
                    %       +
                    % discounted expected future value
                    % -------------------------------------------------
                    value=t*(1+lambda*Q)+cfg.gamma*future;

                    % Bellman maximization: keep the action with the
                    % highest value for this energy/state combination
                    if value>best
                        best=value;
                        bestA=ai;
                    end

                end


                % -----------------------------------------------------
                % Store the Bellman-optimal action
                % -----------------------------------------------------
                if isfinite(best)

                    V(e,op)=best;
                    policy(e,op)=bestA;

                else

                    % No active action is feasible -> choose A0 fallback
                    V(e,op)=0;
                    policy(e,op)=1;

                end

            end
        end


        % Maximum change in V between successive value-iteration passes
        delta=max(abs(V(:)-old(:)));

        % Stop when value iteration has converged
        if delta<cfg.tol
            break;
        end

    end


    % Store solver/convergence information
    info.iterations=it;
    info.delta=delta;
    info.converged=delta<cfg.tol;
    info.aware=aware;
    info.lambda=lambda;

end



% =========================================================================
% EXPECTED OUTCOME OF ONE STATE-ACTION DWELL
% =========================================================================
function [E_mWh,Q,hard] = expected_step(cfg,bat,soc,op,a,aware)

    % Evaluate loaded-voltage conditions for the selected action.
    % With aware=false, voltage warning/minimum effects are ignored
    % during policy optimization.
    bo=brownout_state(cfg,bat,soc,op,a,aware);

    % A sensing-state minimum-voltage violation makes the action infeasible
    hard=bo.state_hard;

    if hard
        E_mWh=0;
        Q=0;
        return;
    end


    % ---------------------------------------------------------------------
    % EXPECTED SENSING-STATE ENERGY
    % ---------------------------------------------------------------------

    % Value iteration uses the mean empirical dwell duration
    d=cfg.mean_dwell_s(op);

    % Effective sensing power after any warning-level sensing suppression
    P=(1-bo.sense_supp)*a.P_mW(op) + ...
        bo.sense_supp*cfg.P_base_mW(1);

    % Average current used in the Peukert-like rate correction
    I=P/bat.V_nom;

    % Expected sensing-state energy during the dwell [mWh]
    E_state=P*peukert_factor(bat,I)*d/3600;


    % ---------------------------------------------------------------------
    % EXPECTED TRANSMISSION ENERGY
    % ---------------------------------------------------------------------

    % Expected requested number of TX events during this dwell:
    %       E[N_TX] = d/tau_i * T(i,a)
    %
    % Unlike Monte Carlo evaluation, value iteration uses the expected
    % TX count rather than sampling a Poisson realization.
    tx_raw=d/cfg.tx.period_s(op)*a.T(op);

    % Expected delivered TX count after warning-level TX suppression
    tx_del=tx_raw*(1-bo.tx_supp);

    % Energy of one TX event, including startup energy [mWh]
    E_one=cfg.tx.P_mW*cfg.tx.duration_s/3600 + ...
          cfg.tx.startup_mJ/3600;

    % Average TX current for Peukert-like rate correction
    I_tx=cfg.tx.P_mW/bat.V_nom;

    % Expected TX energy during the dwell
    E_tx=tx_del*E_one*peukert_factor(bat,I_tx);


    % Total expected energy consumed by this action during the dwell
    E_mWh=E_state+E_tx;


    % ---------------------------------------------------------------------
    % EXPECTED DELIVERED SERVICE / QoS
    % ---------------------------------------------------------------------

    % Delivered sensing service after any warning-level suppression
    S=a.S(op)*(1-bo.sense_supp);

    % Delivered TX service relative to nominal A1 operation.
    % T may exceed 1 for actions such as the event-alert mode.
    T=a.T(op)*(1-bo.tx_supp);

    % Relative QoS score used in the MDP reward
    Q=a.u*(0.60*S+0.40*T);

end



% =========================================================================
% FUTURE VALUE AT CONTINUOUS POST-ACTION ENERGY
% =========================================================================
function f=interp_future(V,econt,p)

    N=size(V,1);

    % econt is the post-action energy expressed as a continuous bin index
    econt=max(0,min(N,econt));

    % Find the two neighboring discrete energy bins
    lo=floor(econt);
    hi=ceil(econt);

    % Expected future value at the lower and upper energy bins
    vlo=state_value(V,lo,p);
    vhi=state_value(V,hi,p);

    % If E' falls exactly on a grid point, interpolation is unnecessary
    if lo==hi

        f=vlo;

    else

        % Linear interpolation gives V(E') between neighboring bins
        f=(hi-econt)*vlo + (econt-lo)*vhi;

    end

end



% =========================================================================
% EXPECTED VALUE OF THE NEXT PHYSIOLOGICAL STATE
% =========================================================================
function x=state_value(V,e,p)

    if e<1

        % No remaining battery energy -> no future value
        x=0;

    else

        % Expected future value over SLEEP, LOW, and HIGH:
        %
        %       sum_j P_exit(i,j) * V(E',j)
        %
        % p contains the SMM exit probabilities from the current state.
        x=p*V(e,:).';

    end

end