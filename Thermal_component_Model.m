% Raaghav Lele, Zach Alles
% Date created: 10/19/2026
% Thermal Component Model 

clc
clear
close all

%% Part zero: Properties and geometry
fprintf("System Inputs/Output Analysis \n\n")
water_cp = 4184;       % J/(kg K)
water_rho = 1000;      % kg/m^3
sigma = 5.670374419e-8; % W/(m^2 K^4)

H = 0.50; % m
W = 0.33; % m
D = 0.30; % m

% Face order: rear, right, left, top, bottom
A_faces = [H*W; H*D; H*D; W*D; W*D];
Arad = sum(A_faces);   % 0.663 m^2

% Flat terrain; no body blockage, view factors
F_ground = [0.5; 0.5; 0.5; 0; 1];
F_sky = 1 - F_ground;

A_ground_weighted = sum(A_faces .* F_ground);
A_sky_weighted = sum(A_faces .* F_sky);

%% Metabolic input

load("MetData.mat")
Metabolic_rates = MetData.metrate; % Column vector, W
time = MetData.time;

% Preliminary assumption: all metabolic heat reaches cooling system
Q_electrical = 10; % average assumption
Q_internal = Metabolic_rates + Q_electrical;
fprintf("Average internal heat generation due to metabolic and electical sources is %.2f Watts\n",mean(Q_internal))


%% Environmental cases

% Idealized 2D Sun path, not a calculated Mars time history:
% 0 deg = Sun at rear horizon
% 90 deg = overhead
% 180 deg = Sun at front horizon
theta = linspace(0,180,181); % Row vector

% Optical properties
alpha_solar = 0.2;
epsilon_rad = 0.9; 
alpha_IR = epsilon_rad;

epsilon_ground = 0.95;
rho_ground = 0.2;   % average Martian ground albedo

% Environmental temperatures
T_ground = 235; % K; prescribed ground-temperature scenario
T_air = 210;    % K; prescribed air-temperature scenario
T_sky = 170;    % K; EFFECTIVE radiative sky temperature
T_Rad = 300;  % K; trial radiator surface temperature Assume Skin temp is 307 and delta of 5 K drop from skin to Radiator 

h = 1;         % W/(m^2 K); prescribed convection coefficient - Assumed from Hayman 2025 paper based on wind speed of 5 m/s


%% Direct solar heating

% Assumed direct-normal irradiance; from ASEN 5158 lecture notes
q_solar_DNI = 175; % W/m^2

A_rad_cross = H*W .* max(0, cosd(theta)) ...
            + W*D .* sind(theta); 

Q_solar = alpha_solar .* A_rad_cross .* q_solar_DNI;
fprintf("Direct normal incident Solar is %.2f Watts\n",mean(Q_solar))

%% Reflected solar heating: albedo

% Direct sunlight on horizontal ground; diffuse sunlight neglected
G_solar_ground = q_solar_DNI .* sind(theta);

Q_albedo = alpha_solar .* rho_ground .* ...
           G_solar_ground .* A_ground_weighted;
fprintf("Albedo is %.2f Watts\n",mean(Q_albedo))

%% Absorbed thermal infrared

% Ground emission only; reflected atmospheric IR neglected
Q_ground_IR_abs = alpha_IR * epsilon_ground * sigma * ...
                  T_ground^4 * A_ground_weighted;

fprintf("Ground IR is %.2f Watts\n",mean(Q_ground_IR_abs))

% Effective sky temperature represents incident sky IR
Q_sky_IR_abs = alpha_IR * sigma * ...
               T_sky^4 * A_sky_weighted;
fprintf("Sky IR is %.2f Watts\n",mean(Q_sky_IR_abs))

%% Heat leaving radiator

Q_conv = h * Arad * (T_Rad - T_air); % Signed: positive outward
fprintf("Heat lost to Atmospheric Convection assuming 5 m/s windspeed is %.2f Watts\n",Q_conv)

Q_IR_emit = epsilon_rad * sigma * Arad * T_Rad^4;
fprintf("IR emitted from  the radiator is %.2f Watts\n",Q_IR_emit)
fprintf("\n")

%% System balance

% Net heat that the radiator can remove from internal sources
% One value per solar-position case
Q_cooling_available = Q_IR_emit + Q_conv ...
                    - Q_solar - Q_albedo ...
                    - Q_ground_IR_abs - Q_sky_IR_abs;
fprintf("Average Cooling available is %.2f Watts\n",mean(Q_cooling_available))

Q_cooling_available_nowind = Q_cooling_available - Q_conv;
fprintf("Average Cooling available is %.2f Watts\n",mean(Q_cooling_available_nowind))
fprintf("\n")

% Plot I/O bar chart
IOs = [mean(Q_solar); mean(Q_albedo); mean(Q_ground_IR_abs); ...
       mean(Q_sky_IR_abs); Q_conv; Q_IR_emit];


labels = ["Incident Solar", "Albedo", "Ground IR", "Sky IR", ...
          "Convection Losses (wind)", "Radiator Output"];

colors = lines(numel(IOs));  % One distinct color per bar

figure()
hold on

for i = 1:numel(IOs)
    bar(i, IOs(i), ...
        "FaceColor", colors(i,:), ...
        "DisplayName", labels(i));
end

hold off
xticks(1:numel(IOs))
xticklabels(labels)
xtickangle(25)

xlabel("System Thermal Inputs and Outputs (average magnitude)")
ylabel("Watts")
title("Martian PLSS Thermal Inputs and Outputs Model")
legend("show", "Location", "northwest")
grid on


% Rows = metabolic samples; columns = solar-position cases
% Uses MATLAB implicit expansion
Q_shortfall = Q_internal - Q_cooling_available;

% Positive shortfall: additional cooling/storage required
% Negative shortfall: excess cooling capacity at prescribed T_Rad

% Gross IR emission required to balance each combination
Q_IR_required = Q_internal + Q_solar + Q_albedo ...
              + Q_ground_IR_abs + Q_sky_IR_abs - Q_conv;


% Calculate short fall in worst possible sun angle scenario
Q_shortfall_design = Metabolic_rates(:) ...
                   - min(Q_cooling_available);

% Cooling Shortfall across the EVA
figure
plot(time(:), Q_shortfall_design, 'LineWidth', 1.5);
yline(0, 'k--', 'Cooling capacity');

xlabel('EVA time [hr]');
ylabel('Cooling shortfall [W]');
title('Cooling shortfall across nominal EVA');
grid on

% Plot Heat loads at various sun angles
% unique sorts the rates and returns their original row indices
[metabolic_unique, idx] = unique(Metabolic_rates);
Q_unique = Q_shortfall(idx, :);

figure
contourf(metabolic_unique, theta, Q_unique.', ...
         30, 'LineColor', 'none');

hold on
contour(metabolic_unique, theta, Q_unique.', ...
        [0 0], 'k', 'LineWidth', 2);

cb = colorbar;
cb.Label.String = 'Cooling shortfall [W]';

xlabel('Metabolic heat load [W]');
ylabel('Idealized Sun-path angle [deg]');
title('Cooling shortfall versus metabolic load and Sun angle');
colormap(turbo)
grid on



%% Part two: Heat Transport and Mass Flow 
% This section will follow that heat acquisition section and the results
% from the previous section will be used as an input. Heat that is lost or
% created through pipe flow will be modeled. Things such as heat loss through an insulation layer,
% major and minor presssure losses, and laminar v turbulent flow will be
% modeled. Heat added/lost through pumps and valves will be considered

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Assumptions:
% - Air in the PLSS is between 12-30 deg C. Air blows in around 30C and
%   is cooled and then is passed back into the PLSS at 22 deg C
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Heat Pipes (Interface between HEX and Radiator shell



%% Heat Pipe sizing
% Assumptions
% We are aiming for a delta T across the heat pipe evaporator wall to the
% radiator of about 3 deg K. So T_evap ~= 303K if T_rad = 300 which is what
% our I/O model used.
%  This entail buidling a resistance network of
% the evaporator section, the condensor section, and any bonding resistance
% to the shell. If we assume ideal bonding of the integrated saddle/HP, we
% can assume R bonding goes to zero. 
%
% The conductance values of the evaporator and condensor of the ammonia
% heat pipes are pulled from the graphs in source THE doc

N_loops = 5;                                    % # of heat pipes
Q_transport = min(Q_cooling_available);         % W; selected heat transport requirement
DeltaT_allow = 3;                               % K, design selection 

Q_pipe = Q_transport / N_loops;

pipe_diameters = [9.5; 12.7; 15.9]; %mm
Cprime_e = [120; 160; 200]; % W/mK Evaporator Conductance 
Cprime_c = [157; 214; 276]; % W/mK Condensor Conductance
pipe_lengths = linspace(0,1,101); % m
evap_length = 0.25*ones(1,101);%m about 12.5 cm
condensor_length = pipe_lengths-evap_length; % m

T_rad = 300; % Deg K which gives a drop of 5 deg from aveage skin temp 307k

% Calculate resistances including of the evaporator, condensor, and the
% bonds
R_evaporator = 1 ./ (Cprime_e .* evap_length); % Thermal resistance of the evaporator of the heat pipe
R_condensor = 1 ./ (Cprime_c .* condensor_length); % Thermal resistance of the condensor portion of HP

% Resistance of the adhesive bond (if selected)
% Integral pipe/flange, initially neglecting metal spreading resistance
b_contact = 20e-3;      % m; actual flat bonded width
L_contact = pipe_lengths;     % m
t_bond = 0.2e-3;       % m; thickness of adhesive
k_bond = 1;            % W/(m K); illustrative

A_contact = b_contact .* condensor_length;
R_attachment = t_bond ./ (k_bond .* A_contact);
R_bonds = [R_attachment; R_attachment; R_attachment];

Delta_T_sizing_options = Q_pipe.*(R_evaporator + R_condensor + R_bonds);
Delta_T_sizing_options_ideal = Q_pipe*(R_evaporator + R_condensor);

% Plot the results assuming an adhesive bond (Adds resistance to the
% network)
figure()
hold on
plot(condensor_length,Delta_T_sizing_options(1,:))
plot(condensor_length,Delta_T_sizing_options(2,:))
plot(condensor_length,Delta_T_sizing_options(3,:))
title('Heat-pipe temperature-drop sizing - Adhesive Bonding')
xlabel("Condensor Length [m]")
ylabel('Evaporator-wall to radiator temperature drop [K]')
legend('9.5 mm Diameter','12.7 mm Diameter','15.9 mm Diameter')
ylim([0 7])
xlim([0 .8])
grid on
hold off

% Plot the results assuming an ideal bond

figure()
hold on
plot(condensor_length,Delta_T_sizing_options_ideal(1,:))
plot(condensor_length,Delta_T_sizing_options_ideal(2,:))
plot(condensor_length,Delta_T_sizing_options_ideal(3,:))
title('Heat-pipe temperature-drop sizing - Ideally bonded')
xlabel("Condensor Length [m]")
ylabel('Evaporator-wall to radiator temperature drop [K]')
legend('9.5 mm Diameter','12.7 mm Diameter','15.9 mm Diameter')
ylim([0 7])
xlim([0 .8])
grid on
hold off

%% Condesing Heat Exchanger (Water/Air - RH)

%% Freezable Heat Exchanger (Nitrogen/Water - Thermal)
% Assumptions
% T_LCG = 307K ~ Skin temp
% We want
% Q_HEX must match the Q_tranport which is the effective max load of
% cooling available given environmental conditions
% We also want the delta T across the HEX to be about 2 deg K
rho_water = 1000; %g/cm^3
Q_Hex = Q_transport;
T_LCG = 307;

cp_water = 4180;              % J/(kg K)
Q_CHE = 80;                    % W; assumed heat added to water

T_w_in = T_LCG; % Assumed/Designed for
T_evap_surface = 303; % Assumed/Design parameter

mdot_HEX = linspace(5/3600,90/3600,384); % kg/s
T_w_out = T_w_in - Q_Hex./(mdot_HEX.*cp_water);

% Log Mean Temperature Difference through HEX
DT_in = T_w_in - T_evap_surface;
DT_out = T_w_out - T_evap_surface;

% Filter out values that are negative
feasible = DT_out > 0;
Del_T_lm = nan(size(mdot_HEX));
Del_T_lm(feasible) = ...
    (DT_in - DT_out(feasible)) ./ ...
    log(DT_in ./ DT_out(feasible));

R_we_allowable = Del_T_lm/Q_Hex; % K/W


N_water = linspace(1,48*8,384);                % Number of water channels
D_water = 0.001;                            % m Assumed 1 mm hole
L_water = 0.25;                             % m
k_water = 0.62;                             % W/(m K), at 34degC
k_Cu = 400;                                 % W/(m K)
mu_water = 0.80e-3;                         % dynamic viscosity Pa*s = kg/(m*s), water at approximately 30°C

% Check Reynolds number of each pipe to determine flow characteristics
mdot_each = mdot_HEX./N_water;              % mdot of each channel
A_flow_each = pi*D_water^2/4;               % Area of each pipe
v_each = mdot_each/(rho_water*A_flow_each); % velocity of each pipe
Re = rho_water*v_each*D_water/mu_water;     % Reynolds # of each pipe

% Calc thermal resistance of force convection pipes
Nu = 3.66;                                  % fully developed laminar approximation
h_water = Nu*k_water/D_water;               % heat transfer coefficient for convection through the water pipes

A_wetted = N_water.*pi.*D_water.*L_water;      % Contact Area of the pipe in the HEX 
R_conv = 1./(h_water*A_wetted);              % Convective Resistance in the HEX

% Thickness of copper for modeling resistance
t_eff = [1; 3; 5; 10]*1e-3;  % m            % These are sensitivity cases, not dimensions validated from the sketch.
% Retain the previous area assumption for this sensitivity study.
% Actual effective conduction area is geometry-dependent.
A_eff = A_wetted;             % row vector across channel counts

R_Cu = t_eff./(k_Cu.*A_eff);
% Other Resistances not modeled. 
% Heat Pipe Contact Resistance
% Copper spreading resistance

for i=1:length(t_eff)

    R_total = R_conv + R_Cu(i,:);
    U_A = 1./R_total;             % rows = thickness cases
    
    %U_A = 1./R_conv;                             % overallHeat Tran Coefficient
    
    % First flow rate giving T_w_out > T_evap_surface
    idx_flow = find(feasible, 1, 'first');
    
    if isempty(idx_flow)
        error('No flow rate in the sweep is physically feasible.');
    end
    
    
    mdot_min = mdot_HEX(idx_flow);
    U_A_min = Q_Hex/Del_T_lm(idx_flow);
    
    fprintf('First feasible sampled flow: %.2f kg/h\n', mdot_min*3600);
    fprintf('Required UA at that flow: %.2f W/K\n', U_A_min);
    
   idx_channels_min = find(U_A >= U_A_min, 1, 'first');

    N_water_min = NaN;
    if ~isempty(idx_channels_min)
        N_water_min = ceil(N_water(idx_channels_min));
    end
    fprintf('Minimum: %.2f 1mm diameter channels \n', N_water_min)
    
    
    U_A_design_min = Q_Hex/Del_T_lm(end);
    
    idx = find(U_A >= U_A_design_min, 1, 'first');
    
    if isempty(idx)
        error('No channel count meets the required UA.');
    else
        N_water_design = ceil(N_water(idx));
    end
    
    
    figure()
    plot(N_water,U_A,"linewidth",2)
    title(sprintf('HEX Conductance — Effective Copper Thickness: %.0f mm', ...
    t_eff(i)*1000))
    xlabel("Number of 1mm diameter water channels")
    ylabel('Overall Thermal Conductance, UA [W/K]')
    if isfinite(N_water_min)
    xline(N_water_min, '--y', ...
        sprintf('Minimum-flow case: %d channels', N_water_min), ...
        'LabelOrientation', 'horizontal', ...
        'LabelVerticalAlignment', 'bottom');
    end
    xline(N_water_design, '--c', ...
    sprintf('%.1f kg/h design: %d channels', ...
        mdot_HEX(end)*3600, N_water_design), ...
    'LabelOrientation', 'horizontal', ...
    'LabelVerticalAlignment', 'top');
    grid on

end

fprintf('Hex Design Mass Flow Rate: %.2f kg/h\n', mdot_HEX(end)*3600);
fprintf('Hex exit water temperature: %.2f kg/h\n', T_w_out(end));
fprintf('Hex exit water temperature: %.2f kg/h\n', T_w_out(end));




% Design consideration:
% We want to optimize the HEX to have a 4 deg Temp drop to ensure that the
% radiator can stay as hot as possible which increases efficiency.
% Therefore we need to increase the number of water channels to reduce the
% resistance of the convection through the HEX.  





% Ignoring CHE for now

% mdot_total = 90/3600;          % kg/s; example TOTAL HEX flow
% f_CHE = 0.20;                  % illustrative flow fraction, not selected sizing
% 
% mdot_CHE = f_CHE * mdot_total;
% mdot_LCG = (1 - f_CHE) * mdot_total;
% 
% % Supply these temperatures from your model:
% T_HEXw_out = T_LCG - Q_Hex/(mdot_total *cp_water); %cold water leaving HEX [K]
% T_LCG_out = 307; %warm water leaving LCG [K]
% 
% T_CHE_out = T_HEX_out + Q_CHE/(mdot_CHE*cp_water);
% 
% T_HEX_in = ...
%     (mdot_LCG*T_LCG_out + mdot_CHE*T_CHE_out)/mdot_total;
% 
% Q_HEX = mdot_total*cp_water*(T_HEX_in - T_HEX_out);


%% Pipe Flow (Convective losses in the PLSS)

%% Pumps (Account for frictional and heating effects from the pump)

%% Valves (Minimal)

%% Air Warmer

%% Part three: Heat Rejection [Zach Alles]
% The results from the previous section will be used at inputs fro this
% section. Heat that is trasnferred from the pipes to our radiator
% will be modeled. Thereafter, 1D heat transfer will be applied across the
% radiator, and the radiative, conductive, and convective heat rejection
% into the Martian atmosphere will be measured. 

% Back Radiator Rejection

% Suit Radiator Rejection

%% Part four: Analysis [Raaghav Lele]
% After part 3, The remaining values will be the temperature of the water 
% after the entire process is done, and the time taken to complete the loop
% from part 1 thru 3. The entire process will be iterative and will see if
% the heat rejection rate and system durability will last a full 8 hour EVA