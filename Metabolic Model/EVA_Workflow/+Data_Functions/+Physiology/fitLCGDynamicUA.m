function Fit = fitLCGDynamicUA(Metabolic_W,Flow_kg_s,UA_W_K,Family,ReferenceMetabolic_W,ReferenceFlow_kg_s)
% FITLCGDYNAMICUA Fit a three-coefficient empirical garment conductance model.
% Inputs: paired positive training data, family and positive feature reference scales.
% Outputs: coefficients, training bounds, family/scales and monotonicity flag.
% Units: W, kg/s, W/K. Side effects: None. No held-out data or fitted defaults.
validateattributes(ReferenceMetabolic_W,{'numeric'},{'scalar','finite','positive'});
validateattributes(ReferenceFlow_kg_s,{'numeric'},{'scalar','finite','positive'});
validateattributes(Metabolic_W,{'numeric'},{'vector','real','finite','positive'});
validateattributes(Flow_kg_s,{'numeric'},{'vector','real','finite','positive'});
validateattributes(UA_W_K,{'numeric'},{'vector','real','finite','positive'});
Demand = Metabolic_W(:)/ReferenceMetabolic_W;
Flow = Flow_kg_s(:)/ReferenceFlow_kg_s;
Response = UA_W_K(:);
assert(numel(Demand)==numel(Flow) && numel(Flow)==numel(Response), ...
    'LCG:FitData','Use paired metabolic, flow and UA records.');
Family = string(Family);
switch Family
    case "Linear"
        X = [ones(size(Demand)),Demand,Flow];
    case {"LogAdditive","PowerLaw"}
        X = [ones(size(Demand)),log(Demand),log(Flow)];
        if Family == "PowerLaw", Response = log(Response); end
    otherwise
        error('LCG:FitFamily','Unsupported dynamic-UA family: %s.',Family);
end
assert(rank(X)==3,'LCG:FitRank','UA calibration does not identify all three coefficients.');
Fit.Family = Family;
Fit.Coefficients = X\Response;
Fit.ReferenceMetabolic_W = ReferenceMetabolic_W;
Fit.ReferenceFlow_kg_s = ReferenceFlow_kg_s;
Fit.MetabolicBounds_W = [min(Metabolic_W),max(Metabolic_W)];
Fit.FlowBounds_kg_s = [min(Flow_kg_s),max(Flow_kg_s)];
Fit.UABounds_W_K = [min(UA_W_K),max(UA_W_K)];
Fit.Monotonic = all(Fit.Coefficients(2:3)>=0);
end
