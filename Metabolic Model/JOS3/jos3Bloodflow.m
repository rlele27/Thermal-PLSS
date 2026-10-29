function Flow_W_K = jos3Bloodflow(P, TissueFlow_L_hr, HandFlow_L_hr, FootFlow_L_hr)
% Directed heat transport by local perfusion and the whole-body vessel network.
% Tissue columns: core, muscle, fat, skin. Rows are receiving nodes.
Node = P.Node;
Flow_W_K = zeros(P.NumberOfNodes);
% Fixed tissue/vessel indices are prepared once for each body.
Flow_W_K(P.PerfusionInIndex) = TissueFlow_L_hr(P.TissueMask);
Flow_W_K(P.PerfusionOutIndex) = TissueFlow_L_hr(P.TissueMask);
Flow_W_K(P.HandAVAIndex) = HandFlow_L_hr;
Flow_W_K(P.FootAVAIndex) = FootFlow_L_hr;

%% Vessel Flow Rates
TotalTissueFlow_L_hr = sum(TissueFlow_L_hr, 2);
ArteryFlow_L_hr = TotalTissueFlow_L_hr;
VeinFlow_L_hr = TotalTissueFlow_L_hr;
ArteryFlow_L_hr(2) = sum(TotalTissueFlow_L_hr(1:2));
VeinFlow_L_hr(2) = ArteryFlow_L_hr(2);
ArteryFlow_L_hr(5) = TotalTissueFlow_L_hr(5) + sum(TotalTissueFlow_L_hr(12:17)) + 2 * FootFlow_L_hr;
VeinFlow_L_hr(5) = ArteryFlow_L_hr(5);
for Start = [6, 9, 12, 15]
    AVAFlow_L_hr = FootFlow_L_hr;
    if Start < 12
        AVAFlow_L_hr = HandFlow_L_hr;
    end
    for Segment = Start:Start + 2
        VeinFlow_L_hr(Segment) = sum(TotalTissueFlow_L_hr(Segment:Start + 2));
        ArteryFlow_L_hr(Segment) = VeinFlow_L_hr(Segment) + AVAFlow_L_hr;
    end
end

%% Central Blood, Head and Trunk
% Each row is [upstream node, downstream node, blood flow in L/hr].
Connections = zeros(46, 3); % Four head, six trunk and 36 limb connections.
Connections(1:4, :) = [ ...
    1, Node(2, 1), ArteryFlow_L_hr(2); ...
    Node(2, 1), Node(1, 1), ArteryFlow_L_hr(1); ...
    Node(1, 2), Node(2, 2), VeinFlow_L_hr(1); ...
    Node(2, 2), 1, VeinFlow_L_hr(2)];
NextConnection = 5;
for Segment = 3:5
    Connections(NextConnection:NextConnection + 1, :) = [ ...
        1, Node(Segment, 1), ArteryFlow_L_hr(Segment); ...
        Node(Segment, 2), 1, VeinFlow_L_hr(Segment)];
    NextConnection = NextConnection + 2;
end

%% Arms and Legs
for Start = [6, 9, 12, 15]
    Middle = Start + 1;
    End = Start + 2;
    UpstreamArtery = 1;
    DownstreamVein = 1;
    AVAFlow_L_hr = HandFlow_L_hr;
    if Start >= 12
        UpstreamArtery = Node(5, 1);
        DownstreamVein = Node(5, 2);
        AVAFlow_L_hr = FootFlow_L_hr;
    end
    Connections(NextConnection:NextConnection + 8, :) = [ ...
        UpstreamArtery, Node(Start, 1), ArteryFlow_L_hr(Start); ...
        Node(Start, 1), Node(Middle, 1), ArteryFlow_L_hr(Middle); ...
        Node(Middle, 1), Node(End, 1), ArteryFlow_L_hr(End); ...
        Node(End, 2), Node(Middle, 2), VeinFlow_L_hr(End); ...
        Node(Middle, 2), Node(Start, 2), VeinFlow_L_hr(Middle); ...
        Node(Start, 2), DownstreamVein, VeinFlow_L_hr(Start); ...
        Node(End, 3), Node(Middle, 3), AVAFlow_L_hr; ...
        Node(Middle, 3), Node(Start, 3), AVAFlow_L_hr; ...
        Node(Start, 3), DownstreamVein, AVAFlow_L_hr];
    NextConnection = NextConnection + 9;
end
for Connection = 1:size(Connections, 1)
    Upstream = Connections(Connection, 1);
    Downstream = Connections(Connection, 2);
    Flow_W_K(Downstream, Upstream) = Flow_W_K(Downstream, Upstream) + Connections(Connection, 3);
end
Flow_W_K = Flow_W_K * 1.067; % Blood heat capacity, Wh/(L K).
end
