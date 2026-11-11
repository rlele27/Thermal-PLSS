function Fin = wetFinPerformance(Gas, W, C)
% WETFINPERFORMANCE One-dimensional graphite conduction, including local condensation latent heat.
% Inputs: Gas, W, C.
% Outputs: Fin.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
% Two cooled roots: solve half the height, with zero gradient at the midplane.
% Insulated-tip dry benchmark: eta = tanh(mL)/(mL), Nellis/Klein fin theory.
N = C.FinNodes;
L = C.ChannelHeight_m / 2;
dx = L / N;
Conduction = C.FinConductivity_W_mK * C.FinThickness_m / dx^2;
h = Gas.HeatTransfer_W_m2K;
LatentHeat = W.VaporEnthalpyAtZero_J_kg + (W.VaporCp_J_kgK - W.Cp_J_kgK) * C.SurfaceTemperature_C;
LatentFilm = LatentHeat * Gas.DryDensity_kg_m3 * Gas.MassTransfer_m_s;
Root = C.SurfaceTemperature_C;
Temperature = repmat(Root, 1, N);
for Iteration = 1:30
    p = Data_Functions.Properties.saturationPressure(Temperature);
    ws = Gas.MolecularMassRatio * p ./ (Gas.Pressure_Pa - p);
    dp = (Data_Functions.Properties.saturationPressure(Temperature + 0.001) - Data_Functions.Properties.saturationPressure(Temperature - 0.001)) / 0.002;
    dws = Gas.MolecularMassRatio * Gas.Pressure_Pa * dp ./ (Gas.Pressure_Pa - p).^2;
    Wet = Gas.InletHumidityRatio > ws;
    dws = dws .* Wet;
    VaporDifference = max(0, Gas.InletHumidityRatio - ws);
    Diagonal = 2 * Conduction + 2 * h + 2 * LatentFilm * dws;
    Right = 2 * h * Gas.SuitTemperature_C + 2 * LatentFilm * (VaporDifference + dws .* Temperature);
    Right(1) = Right(1) + Conduction * Root;
    % Tridiagonal Newton solve; reflected last node enforces zero tip gradient.
    Upper = repmat(-Conduction, 1, N - 1);
    Lower = repmat(-Conduction, 1, N - 1);
    Lower(end) = -2 * Conduction;
    for Node = 2:N
        Multiplier = Lower(Node - 1) / Diagonal(Node - 1);
        Diagonal(Node) = Diagonal(Node) - Multiplier * Upper(Node - 1);
        Right(Node) = Right(Node) - Multiplier * Right(Node - 1);
    end
    NewTemperature = Right ./ Diagonal;
    for Node = N-1:-1:1
        NewTemperature(Node) = (Right(Node) - Upper(Node) * NewTemperature(Node + 1)) / Diagonal(Node);
    end
    Change = max(abs(NewTemperature - Temperature));
    Temperature = NewTemperature;
    if Change < 1e-7
        break;
    end
end
assert(Change < 1e-5, 'RH:FinConvergence', 'Wet fin temperature did not converge.');
Temperature = [Root, Temperature];
p = Data_Functions.Properties.saturationPressure(Temperature);
ws = Gas.MolecularMassRatio * p ./ (Gas.Pressure_Pa - p);
pRoot = Data_Functions.Properties.saturationPressure(Root);
wRoot = Gas.MolecularMassRatio * pRoot / (Gas.Pressure_Pa - pRoot);
MeanTemperature = trapz(Temperature) / N;
MeanVaporDifference = trapz(max(0, Gas.InletHumidityRatio - ws)) / N;
HeatRatio = (Gas.SuitTemperature_C - MeanTemperature) / (Gas.SuitTemperature_C - Root);
MassRatio = 1;
if Gas.InletHumidityRatio > wRoot
    MassRatio = MeanVaporDifference / (Gas.InletHumidityRatio - wRoot);
end
IdealFlux = h * (Gas.SuitTemperature_C - Root) + LatentFilm * max(0, Gas.InletHumidityRatio - wRoot);
ActualFlux = h * (Gas.SuitTemperature_C - MeanTemperature) + LatentFilm * MeanVaporDifference;
Fin.Efficiency = ActualFlux / IdealFlux;
mL = sqrt(2 * h / (C.FinConductivity_W_mK * C.FinThickness_m)) * L;
Fin.DryEfficiency = tanh(mL) / mL;
FinFraction = C.ChannelHeight_m / (C.ChannelHeight_m + C.ChannelGap_m);
Fin.SurfaceHeatEfficiency = 1 - FinFraction * (1 - HeatRatio);
Fin.SurfaceMassEfficiency = 1 - FinFraction * (1 - MassRatio);
Fin.MeanTemperature_C = MeanTemperature;
Fin.TipTemperature_C = Temperature(end);
% Efficiencies evaluated at inlet conditions give no downstream recovery credit.
end
