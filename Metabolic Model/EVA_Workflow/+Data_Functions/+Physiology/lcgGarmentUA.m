function [UA_W_K,OutsideCalibration] = lcgGarmentUA(LCG,MetabolicRate_W)
% LCGGARMENTUA Evaluate constant UA or bounded NASA-data regression.
% Inputs: LCG configuration; metabolic rate in W (without design-output FOS).
% Outputs: UA in W/K and an out-of-calibration flag for each input sample.
% Side effects: None; no controller, source writes or assumed transient lag.
% DynamicFit is fitted in the main script to Bue et al. Table 10.
if string(LCG.Model) == "LiteratureDynamicUA"
    Fit = LCG.DynamicFit;
    Flow = LCG.MassFlow_kg_s+zeros(size(MetabolicRate_W));
    OutsideCalibration = MetabolicRate_W < Fit.MetabolicBounds_W(1) ...
        | MetabolicRate_W > Fit.MetabolicBounds_W(2) ...
        | Flow < Fit.FlowBounds_kg_s(1) | Flow > Fit.FlowBounds_kg_s(2);
    Demand = min(max(MetabolicRate_W,Fit.MetabolicBounds_W(1)),Fit.MetabolicBounds_W(2));
    Flow = min(max(Flow,Fit.FlowBounds_kg_s(1)),Fit.FlowBounds_kg_s(2));
    if ~isfield(Fit,'Family')
        % Compatibility with saved coefficients from the original SI linear fit.
        UA_W_K = Fit.Coefficients(1)+Fit.Coefficients(2)*Demand+Fit.Coefficients(3)*Flow;
    else
        Demand = Demand/Fit.ReferenceMetabolic_W;
        Flow = Flow/Fit.ReferenceFlow_kg_s;
        switch Fit.Family
            case "Linear"
                UA_W_K = Fit.Coefficients(1)+Fit.Coefficients(2)*Demand+Fit.Coefficients(3)*Flow;
            case {"LogAdditive","PowerLaw"}
                UA_W_K = Fit.Coefficients(1)+Fit.Coefficients(2)*log(Demand)+Fit.Coefficients(3)*log(Flow);
                if Fit.Family == "PowerLaw", UA_W_K = exp(UA_W_K); end
            otherwise
                error('LCG:FitFamily','Unsupported dynamic-UA family: %s.',Fit.Family);
        end
    end
    UA_W_K = min(max(UA_W_K,Fit.UABounds_W_K(1)),Fit.UABounds_W_K(2));
else
    UA_W_K = LCG.UA_W_K+zeros(size(MetabolicRate_W));
    OutsideCalibration = false(size(MetabolicRate_W));
end
end
