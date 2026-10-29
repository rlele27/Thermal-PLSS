function Model = createJOS3(Body)
% Initialize a native MATLAB JOS-3 state using the reference neutral procedure.
% Temperatures and setpoints persist when this state is passed to stepJOS3.
if nargin == 0
    Body = struct();
end
Model.Parameters = jos3Parameters(Body);
Model.Temperature_C = ones(Model.Parameters.NumberOfNodes, 1) * 36;
Model.CoreSetpoint_C = ones(17, 1) * 37;
Model.SkinSetpoint_C = ones(17, 1) * 34;

%% Neutral Setpoints
P = Model.Parameters;
BasalRate_W_m2 = P.BasalRate_W / sum(P.Area_m2);
NeutralTemperature_C = jos3NeutralTemperature(BasalRate_W_m2 * 1.25 / 58.15);
Environment = struct('AirTemperature_C', NeutralTemperature_C, ...
    'RadiantTemperature_C', NeutralTemperature_C, 'RelativeHumidity_percent', 50, ...
    'AirSpeed_m_s', 0.1, 'Clothing_clo', 0, 'VaporPermeationEfficiency', 0.45, ...
    'Pressure_kPa', 101.33, 'Posture', "standing");
for Iteration = 1:10
    Model = stepJOS3(Model, Environment, 1.25, 60000, true);
end
Model.CoreSetpoint_C = Model.Temperature_C(P.Node(:, 4));
Model.SkinSetpoint_C = Model.Temperature_C(P.Node(:, 7));
end
