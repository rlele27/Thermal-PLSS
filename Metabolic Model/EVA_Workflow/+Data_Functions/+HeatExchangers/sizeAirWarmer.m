function Design = sizeAirWarmer(A, History, Profile, VaporCp)
% SIZEAIRWARMER Counterflow Q/LMTD conductance, scaled using NASA PLSS 2.0 test 10.
% Inputs: A, History, Profile, VaporCp.
% Outputs: Design.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
% Constant reference UA/volume and mass/volume are preliminary assumptions.
InstantaneousSizing = isfield(History, 'Instantaneous');
if InstantaneousSizing
    Samples = History.Instantaneous;
    Flow = Samples.DryOxygenFlow_kg_s;
    Humidity = Samples.OutletHumidityRatio;
    Cold_C = Samples.ColdTemperature_C;
    Supply_C = Samples.SupplyTemperature_C;
    Duty_W = Samples.Reheat_W;
else
    Flow = Profile.DryOxygenFlow_kg_s;
    Humidity = History.MeanOutletW;
    Cold_C = History.CondenserOutlet_C;
    Supply_C = History.ReheatedTemperature_C;
    Duty_W = History.PeakReheat_W;
end
[Cp, ~, ~] = Data_Functions.Properties.oxygenProperties((Cold_C + Supply_C) / 2 + 273.15);
Capacity_W_K = Flow .* (Cp + Humidity * VaporCp);
if InstantaneousSizing
    Duty_W = max(Duty_W, Capacity_W_K .* max(0, Supply_C - Cold_C));
else
    Cold_C = Supply_C - Duty_W ./ Capacity_W_K;
end
% Fixed reheater inlet; branch and bypass recombine in the reheater circuit.
Water = Data_Functions.Properties.liquidWaterProperties(A.WaterInlet_C);
validateattributes(A.WaterFlow_kg_h, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(A.ConductanceMargin, {'numeric'}, {'scalar','finite','>=',1});
TotalFlow_kg_s = A.WaterFlow_kg_h/3600;
TotalCapacity_W_K = TotalFlow_kg_s*Water.Cp_J_kgK;
Design.TotalWaterFlow_kg_h = A.WaterFlow_kg_h;
Design.WaterInlet_C = repmat(A.WaterInlet_C,size(Duty_W));
Design.WaterFlow_kg_h = zeros(size(Duty_W));
Design.WaterFlow_L_min = zeros(size(Duty_W));
Design.BypassWaterFlow_kg_h = repmat(A.WaterFlow_kg_h,size(Duty_W));
Design.BypassFraction = ones(size(Duty_W));
% Stagnant branch temperature at zero duty is reported at the inlet boundary.
Design.WaterReturn_C = Design.WaterInlet_C;
Design.MixedReturn_C = A.WaterInlet_C-Duty_W/TotalCapacity_W_K;
Active = Duty_W > 0;
if ~any(Active)
    Design.UA_W_K = 0; Design.Dimensions_m = [0,0,0];
    Design.Volume_m3 = 0; Design.DryMass_kg = 0;
    Design.RequiredUA_W_K = zeros(size(Duty_W)); Design.AirInletAtPeak_C = Cold_C;
    Design.MixingEnergyResidual_W = zeros(size(Duty_W));
    Design.DutyResidual_W = zeros(size(Duty_W));
    return;
end
% First size a fixed exchanger against every full-flow operating sample.
FullFlowReturn_C = A.WaterInlet_C-Duty_W/TotalCapacity_W_K;
Delta1_K = A.WaterInlet_C-Supply_C(Active);
Delta2_K = FullFlowReturn_C(Active)-Cold_C(Active);
assert(all(Delta1_K > 0), 'RH:AirWarmerSupply', ...
    'Fixed water inlet must be hotter than the required air outlet.');
assert(all(Delta2_K > 0), 'RH:AirWarmerFlow', ...
    'Available water flow cannot meet duty without a cold-end temperature pinch.');
RequiredUA_W_K = zeros(size(Duty_W));
RequiredUA_W_K(Active) = Duty_W(Active)./counterflowLMTD(Delta1_K,Delta2_K);
Design.UA_W_K = max(RequiredUA_W_K)*A.ConductanceMargin;

% With installed UA fixed, solve the branch flow delivering each air duty.
% The bypass valve changes flow, not inlet temperature or exchanger area.
% Constant-UA water-side behavior is a preliminary hydraulic approximation.
Q = Duty_W(Active);
Cold = Cold_C(Active);
LowerFlow = Q./(Water.Cp_J_kgK*(A.WaterInlet_C-Cold));
UpperFlow = repmat(TotalFlow_kg_s,size(Q));
for Iteration = 1:36
    TrialFlow = (LowerFlow+UpperFlow)/2;
    TrialReturn_C = A.WaterInlet_C-Q./(TrialFlow*Water.Cp_J_kgK);
    TrialDuty_W = Design.UA_W_K*counterflowLMTD(Delta1_K,TrialReturn_C-Cold);
    TooLittleFlow = TrialDuty_W < Q;
    LowerFlow(TooLittleFlow) = TrialFlow(TooLittleFlow);
    UpperFlow(~TooLittleFlow) = TrialFlow(~TooLittleFlow);
end
BranchFlow_kg_s = zeros(size(Duty_W));
BranchFlow_kg_s(Active) = UpperFlow;
Design.WaterFlow_kg_h = BranchFlow_kg_s*3600;
Design.WaterFlow_L_min = BranchFlow_kg_s/Water.Density_kg_m3*60000;
Design.BypassWaterFlow_kg_h = max(0,A.WaterFlow_kg_h-Design.WaterFlow_kg_h);
Design.BypassFraction = Design.BypassWaterFlow_kg_h/A.WaterFlow_kg_h;
Design.WaterReturn_C(Active) = A.WaterInlet_C-Q./(UpperFlow*Water.Cp_J_kgK);
Design.DutyResidual_W = zeros(size(Duty_W));
Design.DutyResidual_W(Active) = Design.UA_W_K*counterflowLMTD( ...
    Delta1_K,Design.WaterReturn_C(Active)-Cold)-Q;
assert(all(abs(Design.DutyResidual_W(Active)) < 1e-6*max(1,Q)), ...
    'RH:AirWarmerControl', 'Bypass flow could not reproduce the required duty with fixed UA.');
MixedFromBranches_C = (Design.WaterFlow_kg_h.*Design.WaterReturn_C ...
    + Design.BypassWaterFlow_kg_h*A.WaterInlet_C)/A.WaterFlow_kg_h;
Design.MixingEnergyResidual_W = TotalCapacity_W_K*(MixedFromBranches_C-Design.MixedReturn_C);
assert(max(abs(Design.MixingEnergyResidual_W)) < 1e-8 ...
    && all(Design.MixedReturn_C <= A.WaterInlet_C+1e-10), ...
    'RH:AirWarmerMixing', 'Recombined water must conserve energy and cannot warm above the inlet.');
% Invert counterflow effectiveness-NTU using the measured reference flows.
ReferenceGasCapacity = A.ReferenceGasPressure_Pa ...
    / (A.ReferenceGasConstant_J_kgK * A.ReferenceGasTemperature_K) ...
    * A.ReferenceGasFlow_m3_s * A.ReferenceGasCp_J_kgK;
ReferenceWaterCapacity = A.ReferenceWaterFlow_kg_s * A.ReferenceWaterCp_J_kgK;
Cmin = min(ReferenceGasCapacity, ReferenceWaterCapacity);
Cr = Cmin / max(ReferenceGasCapacity, ReferenceWaterCapacity);
e = A.ReferenceEffectiveness;
ReferenceNTU = log((1 - e * Cr) / (1 - e)) / (1 - Cr);
Design.ReferenceUA_W_K = ReferenceNTU * Cmin;
Scale = Design.UA_W_K / Design.ReferenceUA_W_K;
% Similar envelope aspect; constant conductance density is not a fin redesign.
Design.Dimensions_m = A.ReferenceDimensions_m * Scale^(1/3);
Design.Volume_m3 = prod(Design.Dimensions_m);
Design.DryMass_kg = A.ReferenceDryMass_kg * Scale;
Design.RequiredUA_W_K = RequiredUA_W_K;
Design.AirInletAtPeak_C = Cold_C;
end

function LMTD_K = counterflowLMTD(Delta1_K,Delta2_K)
% Stable logarithmic mean for positive counterflow terminal differences.
LMTD_K = (Delta1_K+Delta2_K)/2;
Different = abs(Delta1_K-Delta2_K) > 1e-8;
LMTD_K(Different) = (Delta2_K(Different)-Delta1_K(Different)) ...
    ./ log(Delta2_K(Different)./Delta1_K(Different));
end
