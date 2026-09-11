function smm = build_mmash_smm(dataRoot)
%BUILD_MMASH_SMM Build the three-state SMM from MMASH annotations.
% States: 1=SLEEP, 2=LOW, 3=HIGH. Timeline resolution: 60 s.

    % occ = occupancy: total time spent in each physiological state.
    % dwell time = how long we stay continuously in each state each time you enter it.
    dt=60; T=zeros(3); occ=zeros(3,1); dwell={[],[],[]}; nUsers=0;

    % Loop over the 22 MMASH users
    for uid=1:22
        folder=fullfile(dataRoot,sprintf('user_%d',uid));
        if ~isfolder(folder), continue; end
        [activity,sleep]=load_subject(folder);
        state=make_timeline(activity,sleep,dt);
        if isempty(state), continue; end
        nUsers=nUsers+1;
        
        % Calculate occupancy and state transitions
        for i=1:3
            occ(i)=occ(i)+sum(state==i)*dt;
            for j=1:3
                T(i,j)=T(i,j)+sum(state(1:end-1)==i & state(2:end)==j);
            end
        end

        edge=[1;find(diff(state)~=0)+1;numel(state)+1];
        for k=1:numel(edge)-1
            s=state(edge(k));
            dwell{s}(end+1,1)=(edge(k+1)-edge(k))*dt; %#ok<AGROW>
        end
    end

    if nUsers==0, error('No MMASH subjects found in %s.',dataRoot); end
    
    % Convert transition counts into probabilities
    P=T./sum(T,2); Pexit=zeros(3);

    % Create the SMM exit-transition matrix
    for i=1:3
        d=1-P(i,i);
        if d<=0, error('State %d has no observed exits.',i); end
        for j=1:3
            if i~=j, Pexit(i,j)=P(i,j)/d; end
        end
    end

    % Save everything in the SMM structure
    smm.P_phys=P;
    smm.P_exit=Pexit;
    smm.dwell_s=dwell;
    smm.mean_dwell_s=cellfun(@mean,dwell).';
    smm.occupancy=(occ/sum(occ)).';
    smm.n_users=nUsers;
end

% Read that user's activity and sleep annotations
function [activity,sleep]=load_subject(folder)
    % This entire function prepares the raw CSV annotations before the SMM sees them.
    A=read_csv(fullfile(folder,'Activity.csv'));
    code=activity_values(get_col(A,{'Activity','ActivityCode','Activity Code'},true));
    st=get_col(A,{'Start','StartTime','Start Time'},true);
    en=get_col(A,{'End','EndTime','End Time'},true);
    day=day_index(get_col(A,{'Day','Date'},false),height(A));
    t0=column_time(st,day); t1=column_time(en,day);

    keep=~(isnan(t0)&isnan(t1)); % removes rows where both start and end are missing.
    code=code(keep); t0=t0(keep); t1=t1(keep); day=day(keep);
    % Then these loops try to repair a missing start or end
    for k=1:numel(t0)
        if isnan(t0(k))
            if k>1 && isfinite(t1(k-1)), t0(k)=t1(k-1);
            elseif isfinite(t1(k)), t0(k)=t1(k)-900; % The end time is known, but the start time is missing, so assume the activity started 15 minutes earlier.
            else, t0(k)=0; end
        end
    end
    for k=1:numel(t1)
        if isnan(t1(k))
            if k<numel(t0) && isfinite(t0(k+1)), t1(k)=t0(k+1);
            elseif isfinite(t0(k)), t1(k)=t0(k)+900; end % The start time is known, but the end time is missing, so assume the activity lasted 15 minutes.
        end
    end

    % Handle activities crossing midnight
    bad=find(t1<t0);
    for q=bad(:).'
        candidate=t1(q)+86400;
        if candidate-t0(q)>0 && candidate-t0(q)<=16*3600
            t1(q)=candidate;
        else
            t1(q)=NaN;
        end
    end
    t1(t1==t0)=t1(t1==t0)+60;
    dur=t1-t0;

    % Remove invalid intervals
    good=isfinite(code)&isfinite(t0)&isfinite(t1)&dur>0&dur<=24*3600;

    % Creates the clean activity table that will be later used
    activity=table(code(good),t0(good),t1(good),day(good), ...
        'VariableNames',{'Code','Start_s','End_s','Day'});

    % Creates the cleaned sleep table
    sf=fullfile(folder,'sleep.csv');
    if ~isfile(sf), sf=fullfile(folder,'Sleep.csv'); end
    if ~isfile(sf)
        sleep=table(zeros(0,1),zeros(0,1),'VariableNames',{'Start_s','End_s'});
        return
    end

    S=read_csv(sf);
    st=get_col(S,{'InBedTime','In Bed Time','BedTime','InBed'},true);
    en=get_col(S,{'OutBedTime','Out Bed Time','WakeTime','OutBed'},true);
    d0=day_index(get_col(S,{'InBedDate','In Bed Date','Date','SleepDate'},false),height(S));
    d1col=get_col(S,{'OutBedDate','Out Bed Date','WakeDate'},false);
    if isempty(d1col), d1=d0; else, d1=day_index(d1col,height(S)); end
    t0=column_time(st,d0); t1=column_time(en,d1);
    cross=t1<t0; t1(cross)=t1(cross)+86400;
    dur=t1-t0; good=isfinite(t0)&isfinite(t1)&dur>0&dur<=16*3600;
    sleep=table(t0(good),t1(good),'VariableNames',{'Start_s','End_s'});
end

% This is where the cleaned annotations become the three physiological states
function state=make_timeline(activity,sleep,dt)
    starts=[activity.Start_s;sleep.Start_s]; ends=[activity.End_s;sleep.End_s];
    if isempty(starts), state=[]; return; end
    t=(floor(min(starts)/dt)*dt:dt:ceil(max(ends)/dt)*dt).';
    state=2*ones(size(t));
    for r=1:height(activity)
        s=code_to_state(activity.Code(r));
        if s>0, state(t>=activity.Start_s(r)&t<activity.End_s(r))=s; end
    end
    for r=1:height(sleep)
        state(t>=sleep.Start_s(r)&t<sleep.End_s(r))=1;
    end
end

% MMASH-to-SMM mapping (1: SLEEP, 2,3,4: LOW, 5,6: HIGH).
function s=code_to_state(c)
    if c==1, s=1;
    elseif any(c==2:4), s=2;
    elseif any(c==5:6), s=3;
    else, s=-1; end
end

function T=read_csv(file)
    if ~isfile(file), error('Missing MMASH file: %s',file); end
    try, T=readtable(file,'VariableNamingRule','preserve');
    catch, T=readtable(file); end
end

function c=get_col(T,names,required)
    vn=T.Properties.VariableNames;
    key=cellfun(@norm_name,vn,'UniformOutput',false);
    wanted=cellfun(@norm_name,names,'UniformOutput',false); idx=[];
    for k=1:numel(wanted)
        idx=find(strcmp(key,wanted{k}),1); if ~isempty(idx), break; end
    end
    if isempty(idx)
        for k=1:numel(wanted)
            idx=find(contains(key,wanted{k}),1); if ~isempty(idx), break; end
        end
    end
    if isempty(idx)
        if required, error('Required column not found: %s',strjoin(names,', ')); end
        c=[];
    else
        c=T.(vn{idx});
    end
end

function s=norm_name(x)
    s=lower(regexprep(char(string(x)),'[^a-zA-Z0-9]',''));
end

function d=day_index(col,n)
    d=ones(n,1);
    if isempty(col), return; end
    if isnumeric(col)
        x=double(col(:)); good=isfinite(x)&x>=1&x<=10;
        d(good)=round(x(good)); return
    end

    dates=NaT(n,1); anyDate=false;
    for k=1:n
        z=parse_date(scalar_value(col,k));
        if ~isnat(z), dates(k)=dateshift(z,'start','day'); anyDate=true; end
    end
    if anyDate
        base=min(dates(~isnat(dates)));
        for k=1:n
            if ~isnat(dates(k)), d(k)=days(dates(k)-base)+1; end
        end
        return
    end

    for k=1:n
        nums=regexp(char(string(scalar_value(col,k))),'\d+','match');
        if ~isempty(nums)
            x=str2double(nums{1});
            if isfinite(x)&&x>=1&&x<=10, d(k)=round(x); end
        end
    end
end

function t=column_time(col,day)
    n=numel(day); t=nan(n,1);
    for k=1:n
        q=seconds_of_day(scalar_value(col,k));
        if isfinite(q), t(k)=q+(day(k)-1)*86400; end
    end
end

function q=seconds_of_day(v)
    q=NaN; if iscell(v), v=v{1}; end
    if isempty(v), return; end
    if isduration(v), q=mod(seconds(v),86400); return; end
    if isdatetime(v)
        if ~isnat(v), q=hour(v)*3600+minute(v)*60+second(v); end
        return
    end
    if isnumeric(v)
        if isempty(v)||~isfinite(v), return; end
        if v>=0&&v<1, q=v*86400; elseif v>=0&&v<86400, q=v; end
        return
    end
    x=strtrim(char(string(v))); a=sscanf(x,'%d:%d:%f');
    if numel(a)>=2
        q=a(1)*3600+a(2)*60; if numel(a)==3, q=q+a(3); end; return
    end
    z=parse_date(x);
    if ~isnat(z), q=hour(z)*3600+minute(z)*60+second(z); end
end

function z=parse_date(v)
    z=NaT; if iscell(v), v=v{1}; end
    if isempty(v), return; end
    if isdatetime(v), z=v; return; end
    if isnumeric(v)
        if isfinite(v)&&v>1000
            try
                z=datetime(v,'ConvertFrom','datenum');
                if year(z)<1990||year(z)>2100, z=NaT; end
            catch, z=NaT; end
        end
        return
    end
    x=strtrim(char(string(v))); if isempty(x), return; end
    fmts={'dd/MM/yyyy','MM/dd/yyyy','yyyy-MM-dd','dd-MM-yyyy','MM-dd-yyyy', ...
        'dd.MM.yyyy','yyyy/MM/dd','dd/MM/yyyy HH:mm:ss','MM/dd/yyyy HH:mm:ss', ...
        'yyyy-MM-dd HH:mm:ss'};
    for k=1:numel(fmts)
        try
            y=datetime(x,'InputFormat',fmts{k});
            if ~isnat(y), z=y; return; end
        catch
        end
    end
    try, z=datetime(x); catch, z=NaT; end
end

function x=activity_values(col)
    n=numel(col); x=nan(n,1);
    if isnumeric(col), x=double(col(:)); return; end
    for k=1:n
        s=lower(strtrim(char(string(scalar_value(col,k))))); z=str2double(s);
        if isfinite(z), x(k)=z;
        elseif contains(s,'sleep'), x(k)=1;
        elseif contains(s,'lay'), x(k)=2;
        elseif contains(s,'sit'), x(k)=3;
        elseif contains(s,'light'), x(k)=4;
        elseif contains(s,'medium'), x(k)=5;
        elseif contains(s,'heavy')||contains(s,'vigorous'), x(k)=6;
        elseif contains(s,'eat'), x(k)=7;
        elseif contains(s,'small')||contains(s,'phone'), x(k)=8;
        elseif contains(s,'large')||contains(s,'computer')||contains(s,'tv'), x(k)=9;
        elseif contains(s,'caffe'), x(k)=10;
        elseif contains(s,'smok'), x(k)=11;
        elseif contains(s,'alcohol'), x(k)=12;
        elseif contains(s,'other'), x(k)=13;
        end
    end
end

function v=scalar_value(col,k)
    if iscell(col), v=col{k}; else, v=col(k); end
end
