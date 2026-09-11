function cfg = paper_model(mmashRoot)
% Table 1 in the paper.
%PAPER_MODEL Return the workload, battery, action, and MDP parameters.

    smm = build_mmash_smm(mmashRoot);

    cfg.states = {'SLEEP','LOW','HIGH'};
    cfg.P_exit = smm.P_exit;
    cfg.dwell_s = smm.dwell_s;
    cfg.mean_dwell_s = smm.mean_dwell_s;
    cfg.occupancy = smm.occupancy;
    cfg.n_users = smm.n_users;

    cfg.P_base_mW = [0.024 1.880 14.100]; %State Power
    cfg.I_base_mA = [0.01 1.00 20.00]; %State Peak Current

    cfg.tx.period_s = [300 120 60]; %Nominal Tx Periods
    cfg.tx.P_mW = 14.1; %Tx event-avg power
    cfg.tx.I_peak_mA = 12.0; %Tx peak current
    cfg.tx.duration_s = 0.05; %Tx duration
    cfg.tx.startup_mJ = 2.0; %Tx startup energy

    % act(action mode name, State average power in mW, ordered SLEEP/LOW/HIGH,
% Relative sensing-service factor, Requested TX-rate/service factor relative 
% to A1, Utility multiplier, State peak current in mA). A1 defines the nominal 
% hardware operating point, while A2–A6 are predefined firmware-mode abstractions 
% constructed to represent processing, aggregation, alerting, and reduced-load 
% tradeoffs. Their power, service, and peak-current parameters are system-level 
% modeling assumptions rather than measurements from a fabricated prototype.
    cfg.actions = [ ...
        act('A0_FALLBACK',    [0.024 0.024 0.024], [0 0 0],       [0 0 0],       0.0, [0.01 0.01 0.01]); ...
        act('A1_NOMINAL',     [0.024 1.880 14.10], [1 1 1],       [1 1 1],       1.0, [0.01 1.00 20.0]); ...
        act('A2_PROCESSING',  [0.224 2.880 15.10], [1 1 1],       [1 1 1],       1.1, [0.01 1.00 20.0]); ...
        act('A3_AGGREGATION', [0.024 1.930 14.15], [1 1 1],       [.33 .33 .33], 1.0, [0.01 1.00 20.0]); ...
        act('A4_PROC_AGG',    [0.224 2.580 14.80], [1 1 1],       [.17 .17 .17], 1.1, [0.01 1.00 20.0]); ...
        act('A5_EVENT_ALERT', [0.024 2.380 15.10], [1 1 1],       [.20 .50 2.0], 1.0, [0.01 1.00 20.0]); ...
        act('A6_REDUCED_LOAD',[0.024 1.410 7.755], [1 .75 .55],   [.25 .35 .50], 1.0, [0.01 .70 9.0])];

    cfg.batteries.LIR2450  = bat('LIR2450',  3.7, 0.370, 0.40, 1.03, 20.0, 3.30, 3.00);
    cfg.batteries.LIR2032H = bat('LIR2032H', 3.7, 0.222, 0.65, 1.03, 12.0, 3.20, 2.75);
    cfg.batteries.CR2032   = bat('CR2032',   3.0, 0.705, 18.0, 1.08, 0.19, 2.40, 2.00);
    cfg.batteries.CR1632   = bat('CR1632',   3.0, 0.390, 30.0, 1.09, 0.19, 2.40, 2.00);

    cfg.battery_names = {'LIR2450','LIR2032H','CR2032','CR1632'};
    cfg.N_E = 800;
    cfg.gamma = 1.0;
    cfg.max_iter = 25000;
    cfg.tol = 1e-6;
    cfg.lambda = [0 .1 .2 .3 .5 .75 1 1.5 2 3 5 10 30];
    cfg.n_runs = 200;
    cfg.seed.LIR2450 = 42000;
    cfg.seed.LIR2032H = 43000;
    cfg.seed.CR2032 = 44000;
    cfg.seed.CR1632 = 45000;
    cfg.bootstrap_reps = 2000;
    cfg.bootstrap_seed_tx = 91428;
    cfg.bootstrap_seed_qos = 91429;
    cfg.match_preferred_pct = 2;
    cfg.match_fallback_pct = 5;
end

function a = act(name,P,S,T,u,Ipk)
    a = struct('name',name,'P_mW',P,'S',S,'T',T,'u',u,'I_peak_mA',Ipk);
end

function b = bat(name,V,E,R,n,Iref,Vwarn,Vmin)
    b = struct('name',name,'V_nom',V,'E_Wh',E,'R_int',R,'n',n, ...
        'I_ref_mA',Iref,'V_warn',Vwarn,'V_min',Vmin, ...
        'ocv_knee_soc',0.35,'ocv_low_span',0.65); %The OCV–SoC curve uses a 
% knee at 35% SoC, below which the modeled voltage decreases more rapidly. 
% The parameter 0.65 assigns 65% of the total OCV variation to the 0--35% 
% SoC region; both values are modeling assumptions rather than measured 
% battery characteristics.
end
