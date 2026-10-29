function P = jos3Parameters(Body)
% Body geometry, tissue capacities and conductances for the 85-node JOS-3 model.
% Port of TanabeLab/JOS-3, commit 3c74ee2 (MIT). See LICENSE.

%% Body Parameters
Defaults = struct('Height_m', 1.72, 'Weight_kg', 74.43, 'Fat_percent', 15, ...
    'Age_years', 20, 'Sex', "male", 'CardiacIndex_L_min_m2', 2.59, ...
    'SurfaceAreaEquation', "dubois", 'BasalMetabolicEquation', "harris-benedict");
Names = fieldnames(Body);
assert(all(ismember(Names, fieldnames(Defaults))), ...
    'JOS3:BodyParameter', 'Unknown body parameter. See jos3Parameters.');
for Name = reshape(fieldnames(Defaults), 1, [])
    if ~isfield(Body, Name{1})
        Body.(Name{1}) = Defaults.(Name{1});
    end
end
validateattributes(Body.Height_m, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(Body.Weight_kg, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(Body.Fat_percent, {'numeric'}, {'scalar', 'finite', '>=', 0, '<=', 100});
validateattributes(Body.Age_years, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(Body.CardiacIndex_L_min_m2, {'numeric'}, {'scalar', 'finite', 'positive'});
Body.Sex = validatestring(Body.Sex, {'male', 'female'});
P.Body = Body;
P.Coefficients = jos3Coefficients();
C = P.Coefficients;

%% Body Surface Area and Blood Flow
Height_m = Body.Height_m;
Weight_kg = Body.Weight_kg;
Age_years = Body.Age_years;
switch lower(Body.SurfaceAreaEquation)
    case 'dubois'
        Area_m2 = 0.2025 * Height_m^0.725 * Weight_kg^0.425;
    case 'takahira'
        Area_m2 = 0.2042 * Height_m^0.725 * Weight_kg^0.425;
    case 'fujimoto'
        Area_m2 = 0.1882 * Height_m^0.663 * Weight_kg^0.444;
    case 'kurazumi'
        Area_m2 = 0.2440 * Height_m^0.693 * Weight_kg^0.383;
    otherwise
        error('JOS3:SurfaceAreaEquation', 'Unknown surface area equation.');
end
P.AreaRatio = Area_m2 / sum(C.StandardArea_m2);
P.Area_m2 = C.StandardArea_m2 * P.AreaRatio;
WeightRatio = Weight_kg / 74.43;
if Age_years < 50
    BloodAgeFactor = 1;
elseif Age_years < 60
    BloodAgeFactor = 0.85;
elseif Age_years < 70
    BloodAgeFactor = 0.75;
else
    BloodAgeFactor = 0.7;
end
P.BloodFlowRatio = Body.CardiacIndex_L_min_m2 * 60 * BloodAgeFactor * Area_m2 / 290;

%% Basal Metabolism
Male = strcmp(Body.Sex, 'male');
switch lower(Body.BasalMetabolicEquation)
    case 'harris-benedict'
        if Male
            Basal_kcal_day = 88.362 + 13.397 * Weight_kg + 500.3 * Height_m - 5.677 * Age_years;
        else
            Basal_kcal_day = 447.593 + 9.247 * Weight_kg + 479.9 * Height_m - 4.330 * Age_years;
        end
    case 'harris-benedict_origin'
        if Male
            Basal_kcal_day = 66.4730 + 13.7516 * Weight_kg + 500.33 * Height_m - 6.7550 * Age_years;
        else
            Basal_kcal_day = 655.0955 + 9.5634 * Weight_kg + 184.96 * Height_m - 4.6756 * Age_years;
        end
    case {'japanese', 'ganpule'}
        SexOffset = 0.9708;
        if Male
            SexOffset = 0.4235;
        end
        Basal_kcal_day = (0.0481 * Weight_kg + 2.34 * Height_m - 0.0138 * Age_years - SexOffset) * 1000 / 4.186;
    otherwise
        error('JOS3:BasalEquation', 'Unknown basal metabolic equation.');
end
P.BasalRate_W = Basal_kcal_day * 0.048;
assert(P.BasalRate_W > 0, 'JOS3:BasalRate', 'Body parameters give a nonpositive basal rate.');
P.BasalHeat_W = P.BasalRate_W * [C.BasalCoreFraction, C.BasalMuscleFraction, ...
    C.BasalFatFraction, C.BasalSkinFraction];

%% Fixed Thermoregulation Factors
P.BasalTotal_W = sum(P.BasalHeat_W, 'all');
P.LCGContactArea_m2 = P.Area_m2;
P.LCGContactArea_m2([1, 2, 8, 11, 14, 17]) = 0;
P.SweatAgeFactor = ones(17, 1);
if Age_years >= 60
    P.SweatAgeFactor = C.SweatAgeFactor;
end
AgeBin = 1 + sum(Age_years >= [30, 40, 50, 60, 70, 80]);
ShiveringAgeFactors = [1, 0.97514, 0.95028, 0.92818, 0.90055, 0.86188, 0.82597];
P.ShiveringAgeFactor = ShiveringAgeFactors(AgeBin);
BMI = Weight_kg / Height_m^2;
BAT = 10^(-0.10502 * BMI + 2.7708);
if Age_years < 30
    BAT = BAT * 1.61 * 44 / 83;
elseif Age_years < 40
    BAT = BAT * 15 / 38;
elseif Age_years < 50
    BAT = BAT * 0.80 * 7 / 26;
else
    BAT = 0; % Preserve the reference incidence at age 50 and above.
end
P.NonshiveringLimit_W = 1.80 * BAT + 2.43 + 5.62;

%% Node Order
% Columns: artery, vein, superficial vein, core, muscle, fat, skin.
% Central blood is node 1. Absent layers have index zero.
P.BodyNames = ["Head", "Neck", "Chest", "Back", "Pelvis", ...
    "LShoulder", "LArm", "LHand", "RShoulder", "RArm", "RHand", ...
    "LThigh", "LLeg", "LFoot", "RThigh", "RLeg", "RFoot"];
P.Node = zeros(17, 7);
NextNode = 2;
for Segment = 1:17
    if Segment == 1 || Segment == 5
        Layers = [1, 2, 4, 5, 6, 7];
    elseif Segment <= 5
        Layers = [1, 2, 4, 7];
    else
        Layers = [1, 2, 3, 4, 7];
    end
    P.Node(Segment, Layers) = NextNode:NextNode + numel(Layers) - 1;
    NextNode = NextNode + numel(Layers);
end
P.NumberOfNodes = NextNode - 1;

%% Fixed Tissue and Perfusion Indices
P.TissueNodes = P.Node(:, 4:7);
P.TissueMask = P.TissueNodes > 0;
P.HasMuscle = P.Node(:, 5) > 0;
ArteryNodes = repmat(P.Node(:, 1), 1, 4);
VeinNodes = repmat(P.Node(:, 2), 1, 4);
P.PerfusionInIndex = sub2ind([P.NumberOfNodes, P.NumberOfNodes], ...
    P.TissueNodes(P.TissueMask), ArteryNodes(P.TissueMask));
P.PerfusionOutIndex = sub2ind([P.NumberOfNodes, P.NumberOfNodes], ...
    VeinNodes(P.TissueMask), P.TissueNodes(P.TissueMask));
P.HandAVAIndex = sub2ind([P.NumberOfNodes, P.NumberOfNodes], P.Node([8, 11], 3), P.Node([8, 11], 1));
P.FootAVAIndex = sub2ind([P.NumberOfNodes, P.NumberOfNodes], P.Node([14, 17], 3), P.Node([14, 17], 1));

%% Tissue Conductance
FatBin = 1 + sum(Body.Fat_percent >= [12.5, 17.5, 22.5, 27.5]);
CoreSkin_W_K = C.(sprintf('CoreSkinConductance%d', FatBin));
CoreMuscle_W_K = zeros(17, 1);
MuscleFat_W_K = zeros(17, 1);
FatSkin_W_K = zeros(17, 1);
CoreMuscle_W_K([1, 5]) = [1.601, 3.0813];
MuscleFat_W_K([1, 5]) = [13.222, 10.3738];
FatSkin_W_K([1, 5]) = [16.008, 41.4954];
SizeFactor = ones(17, 1) * P.AreaRatio^2 / WeightRatio;
SizeFactor(1:2) = WeightRatio / P.AreaRatio;
Conductance_W_K = [CoreSkin_W_K, CoreMuscle_W_K, MuscleFat_W_K, FatSkin_W_K, ...
    C.VesselCoreConductance, C.SuperficialSkinConductance, C.ArteryVeinConductance] .* SizeFactor;
P.Conductance_W_K = zeros(P.NumberOfNodes);
for Segment = 1:17
    Node = P.Node(Segment, :);
    Values = Conductance_W_K(Segment, :);
    P.Conductance_W_K(Node(1), Node(2)) = Values(7);
    P.Conductance_W_K(Node(1), Node(4)) = Values(5);
    P.Conductance_W_K(Node(2), Node(4)) = Values(5);
    if Node(3) > 0
        P.Conductance_W_K(Node(3), Node(7)) = Values(6);
    end
    if Node(5) > 0
        P.Conductance_W_K(Node(4), Node(5)) = Values(2);
        P.Conductance_W_K(Node(5), Node(6)) = Values(3);
        P.Conductance_W_K(Node(6), Node(7)) = Values(4);
    else
        P.Conductance_W_K(Node(4), Node(7)) = Values(1);
    end
end
P.Conductance_W_K = P.Conductance_W_K + P.Conductance_W_K';

%% Tissue Heat Capacity
MuscleCapacity_Wh_K = zeros(17, 1);
FatCapacity_Wh_K = zeros(17, 1);
MuscleCapacity_Wh_K([1, 5]) = [0.305, 7.409];
FatCapacity_Wh_K([1, 5]) = [0.203, 1.947];
Capacity_Wh_K = [P.BloodFlowRatio * [C.ArteryCapacity_Wh_K, C.VeinCapacity_Wh_K, C.SuperficialCapacity_Wh_K], ...
    WeightRatio * [C.CoreCapacity_Wh_K, MuscleCapacity_Wh_K, FatCapacity_Wh_K, C.SkinCapacity_Wh_K]];
P.Capacity_J_K = zeros(P.NumberOfNodes, 1);
P.Capacity_J_K(1) = 1.999 * P.BloodFlowRatio * 3600;
for Segment = 1:17
    Layers = P.Node(Segment, :) > 0;
    P.Capacity_J_K(P.Node(Segment, Layers)) = Capacity_Wh_K(Segment, Layers) * 3600;
end
end
