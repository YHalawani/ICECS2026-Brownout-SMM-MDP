function plot_paper_figure(outDir)
%PLOT_PAPER_FIGURE Recreate the CR1632 lifetime-transmission figure.
%
% Uses saved main-study and matched-service results. No simulation is run.

    if nargin<1, outDir='results'; end

    S=load(fullfile(outDir,'main_results.mat'),'study');
    A=load(fullfile(outDir,'analysis_results.mat'),'headline');
    points=S.study.CR1632;
    M=A.headline.TX;

    xb=cellfun(@(p)p.blind.summary.tx_per_hour_mean,points);
    yb=cellfun(@(p)p.blind.summary.life_h_mean,points);
    xa=cellfun(@(p)p.aware.summary.tx_per_hour_mean,points);
    ya=cellfun(@(p)p.aware.summary.life_h_mean,points);

    B=nondominated_points(xb,yb);
    W=nondominated_points(xa,ya);
    [B.x,ib]=sort(B.x); B.y=B.y(ib);
    [W.x,ia]=sort(W.x); W.y=W.y(ia);

    fig=figure('Color','w','Visible','off','Position',[100 100 680 470]);
    ax=axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');
    colors=ax.ColorOrder;
    cBlind=colors(1,:); cAware=colors(2,:);

    % All tested operating points.
    hB=plot(ax,xb,yb,'o','LineStyle','none','Color',cBlind, ...
        'MarkerSize',6,'LineWidth',1.0,'DisplayName','Brownout-blind');
    hA=plot(ax,xa,ya,'s','LineStyle','none','Color',cAware, ...
        'MarkerSize',6,'LineWidth',1.0,'DisplayName','Brownout-aware');

    % Connect adjacent nondominated points. The largest empty blind TX gap
    % is dashed to show that no intermediate tested blind operating point
    % was obtained in that transmission-rate range.
    gapIdx=[];
    if numel(B.x)>1
        dx=diff(B.x);
        [~,gapIdx]=max(dx);
        for k=1:numel(B.x)-1
            style='-';
            if k==gapIdx, style='--'; end
            plot(ax,B.x(k:k+1),B.y(k:k+1),style,'Color',cBlind, ...
                'LineWidth',1.35,'HandleVisibility','off');
        end
    end
    if numel(W.x)>1
        plot(ax,W.x,W.y,'-','Color',cAware,'LineWidth',1.35, ...
            'HandleVisibility','off');
    end

    % Selected TX-matched comparison.
    plot(ax,[M.blind.service M.aware.service], ...
        [M.blind.life M.aware.life],'k:','LineWidth',1.35, ...
        'HandleVisibility','off');
    hSel=plot(ax,M.blind.service,M.blind.life,'o','Color',cBlind, ...
        'MarkerFaceColor',cBlind,'MarkerSize',7,'LineWidth',1.0, ...
        'DisplayName','Selected TX match');
    plot(ax,M.aware.service,M.aware.life,'s','Color',cAware, ...
        'MarkerFaceColor',cAware,'MarkerSize',7,'LineWidth',1.0, ...
        'HandleVisibility','off');

    xlabel(ax,'Transmission rate (TX/h)');
    ylabel(ax,'Monitoring lifetime (h)');
    legend(ax,[hB hA hSel],'Location','best','Box','off');
    set(ax,'FontName','Times New Roman','FontSize',10,'LineWidth',0.8);

    exportgraphics(fig,fullfile(outDir,'fig_lifetime_transmission_cr1632.png'), ...
        'Resolution',300);
    close(fig);

    fprintf('Paper figure saved to %s\n', ...
        fullfile(outDir,'fig_lifetime_transmission_cr1632.png'));
end

function P=nondominated_points(x,y)
    x=x(:); y=y(:);
    keep=true(size(x));
    for i=1:numel(x)
        for j=1:numel(x)
            if i~=j && x(j)>=x(i) && y(j)>=y(i) && ...
                    (x(j)>x(i) || y(j)>y(i))
                keep(i)=false;
                break
            end
        end
    end
    P.x=x(keep).';
    P.y=y(keep).';
end
