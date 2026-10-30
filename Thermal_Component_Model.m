% Raaghav Lele, Zach Alles
% Date created: 10/19/2026
% Thermal Component Model 
clc
clear
close all;



%% Part zero: Properties and Problem Definition
% To call on a thermo property for water, use the following callout: 
% XSteam('Thermo Prop','Pressure in bar','Temperature in C')
% water_cp = 4.184; %J/g*C
% water_rho = 1; %g/cm^3
% sigma = 5.670374419e-8; % W/(m^2 K^4)
% H = 0.5; % m height of the plss
% W = 0.33; % m width of the plss
% D = 0.3; % m depth of the plss
% A_faces = [H*W; H*D; H*D; W*D; W*D]; % Face order: rear, right, left, top, bottom
% theta = linspace(0,180,181); % sunrise - sunset assuming 2D rise and fall.
% 
% 
% %% Part one: System Wide I/O - Heat acquisition and rejection [Zach Alles]
% % This section will focus on taking in the source heat.
% % The modeled human heat will come directly from the metabolic model. The 
% % heat from each subsystem will also be added as inputs. This won't be just modeled as heat
% % acquisition, but the way that we plan to acquire heat out of htat system
% % (fans, radiators or whatever) will be modeled
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % Assumptions: 
% % Inputs include: (1) Incident Solar Irradiation
% %                     -Solar flux at surface is 175W/m^2 (ASEN 5158 lecture
% %                     notes)
% %                 (2) Metabolic Heat Generation
% %                     - Data importd from metabolic model
% %                 (3) Solar Albedo
% %                 (4) Ground IR
% % Outpus include:
% %                 (1) IR radiation (radiator)
% %                 (2) Atmospheric convection
% %
% 
% %%%%%%%%%%%%%% System Heat inputs %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% % Metabolic Rates
% load("MetData.mat")
% Metabolic_rates = Metdata.metrate; % W
% time = Metdata.time;
% 
% % Solar Irradiance on the PLSS
% q_flux_solar = 175; %W/m2 % Solar Irradiance on the Martian Surface 5158 textbook value
% alpha_rad = 0.2; % Aeroglaze coating
% A_rad_cross = sum(A_faces.*sind(theta)); % Cross sectional area receiving incident solar radiation.
% Q_solar_irradiance = alpha_rad*A_rad_cross*q_flux_solar;
% 
% 
% 
% 
% % Ground thermal infrared emission absorbed by one exposed face
% % Assumptions: uniform diffuse ground, gray surfaces,
% % flat terrain, no blockage, negligible short-path attenuation
% 
% T_ground = 235;        % average ground temp at perservance rover landing zone K; possibly replace with site/time-dependent input
% epsilon_ground = 0.95; % emissivity of the ground
% 
% A_face_cross = 0.20;        % m^2; actual exposed face area
% alpha_IR_face = 0.2; % Gray-surface approximation with aeroglaze coating
% 
% beta_deg = 90;        % Tilt of plate facing ground 0 = up-facing, 90 = vertical, 180 = down
% F_ground = (1 - cosd(beta_deg))/2;
% 
% E_ground_IR = epsilon_ground * sigma * T_ground^4; % W/m^2
% G_ground_IR = F_ground * E_ground_IR;              % W/m^2
% Q_ground_IR_abs = alpha_IR_face * A_face * G_ground_IR; % W
% 
% % Q from Albedo
% A_faces = [H*W; H*D; H*D; W*D; W*D];
% F_ground = [0.5; 0.5; 0.5; 0; 1];
% F_sky = 1 - F_ground;
% 
% Arad = sum(A_faces);
% A_ground_weighted = sum(A_faces .* F_ground);
% A_sky_weighted = sum(A_faces .* F_sky);
% 
% Q_albedo = alpha_solar .* rho_ground .* ...
%            G_solar_ground .* A_ground_weighted;
% 
% %%%%%%%%%%%% System Outputs %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% % Convection (Forced) from the air on the PLSS
% %Assume wind speeds of about 5 m/s, h = 1 W/m2K (From Hayman 2025)
% h = 1; % W/(m^2K) average based on Hayman 2025
% T_Rad = 309.6; % 
% T_air = 210; % K; representative Martian near-surface temperature average
% Q_conv = h * Arad * (T_Rad - T_air); % W leaving radiator surface
% 
% % Q needed out of the radiator
% Q_rad = Q_solar + Q_ground_IR_abs + Metabolic_rates + Q_albedo - Q_conv;


%% Chat edited Below

clc
clear
close all

%% Part zero: Properties and geometry

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
Metabolic_rates = Metdata.metrate(:); % Column vector, W
time = Metdata.time;

% Preliminary assumption: all metabolic heat reaches cooling system
Q_electrical = 10; % average assumption
Q_internal = Metabolic_rates + Q_electrical;

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
T_sky = 170;    % K; illustrative EFFECTIVE radiative sky temperature
T_Rad = 309.6;  % K; trial radiator surface temperature

h = 1;         % W/(m^2 K); prescribed convection coefficient - Assumed from Hayman 2025 paper based on wind speed of 5 m/s

%% Direct solar heating

% Assumed direct-normal irradiance; from ASEN 5158 lecture notes
q_solar_DNI = 175; % W/m^2

A_rad_cross = H*W .* max(0, cosd(theta)) ...
            + W*D .* sind(theta); 

Q_solar = alpha_solar .* A_rad_cross .* q_solar_DNI;

%% Reflected solar heating: albedo

% Direct sunlight on horizontal ground; diffuse sunlight neglected
G_solar_ground = q_solar_DNI .* sind(theta);

Q_albedo = alpha_solar .* rho_ground .* ...
           G_solar_ground .* A_ground_weighted;

%% Absorbed thermal infrared

% Ground emission only; reflected atmospheric IR neglected
Q_ground_IR_abs = alpha_IR * epsilon_ground * sigma * ...
                  T_ground^4 * A_ground_weighted;

% Effective sky temperature represents incident sky IR
Q_sky_IR_abs = alpha_IR * sigma * ...
               T_sky^4 * A_sky_weighted;

%% Heat leaving radiator

Q_conv = h * Arad * (T_Rad - T_air); % Signed: positive outward

Q_IR_emit = epsilon_rad * sigma * Arad * T_Rad^4;

%% System balance

% Net heat that the radiator can remove from internal sources
% One value per solar-position case
Q_cooling_available = Q_IR_emit + Q_conv ...
                    - Q_solar - Q_albedo ...
                    - Q_ground_IR_abs - Q_sky_IR_abs;

Q_cooling_available_nowind = Q_cooling_available - Q_conv;

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



%% Part two: Heat Transport and Mass Flow [Raaghav Lele]
% This section will follow that heat acquisition section and the results
% from the previous section will be used as an input. Heat that is lost or
% created through pipe flow will be modeled. Things such as heat loss through an insulation layer,
% major and minor presssure losses, and laminar v turbulent flow will be
% modeled. Heat added/lost through pumps and valves will be considered

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Assumptions:
% - Air in the PLSS is between 22-30 deg C. Air blows in around 30C and
%   is cooled and then is passed back into the PLSS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Heat Pipes (Interface between HEX and Radiator shell

N_loops = 5;
Q_transport = min(Q_cooling_available);        % W; selected heat transport requirement
DeltaT_allow = 5;        % K; example design allocation

Q_per_loop = Q_transport / N_loops;

R_branch_max = DeltaT_allow / Q_per_loop; % K/W per branch
R_parallel_max = DeltaT_allow / Q_transport; % K/W overall


%% Heat-pipe condenser attachment: diameter sensitivity

N_pipes = 5;
Q_transport = 306;              % W; selected total transport requirement
Q_pipe = Q_transport/N_pipes;   % Equal sharing assumption

D_outer = linspace(4,20,100)*1e-3; % m; exploratory diameter range
L_total = 1.10;                   % m
L_cond = 0.60;                    % m; assumed attached condenser length

% Pipe-to-saddle bond
f_wrap = 0.5;          % Half circumference
t_bond_pipe = 0.2e-3;  % m; illustrative
k_bond_pipe = 1;       % W/(m K); illustrative

A_pipe_saddle = f_wrap*pi.*D_outer*L_cond;
R_pipe_saddle = t_bond_pipe ./ ...
               (k_bond_pipe .* A_pipe_saddle);

% Saddle-to-shell bond
% Assumed saddle width scales with diameter for this sweep
b_saddle = 2*D_outer;

t_bond_shell = 0.2e-3; % m; illustrative
k_bond_shell = 1;      % W/(m K); illustrative

A_saddle_shell = b_saddle*L_cond;
R_saddle_shell = t_bond_shell ./ ...
                (k_bond_shell .* A_saddle_shell);

% Bond layers only: excludes heat-pipe internal resistance,
% saddle conduction, tube wall and radiator spreading resistance
R_bonds = R_pipe_saddle + R_saddle_shell;
DeltaT_bonds = Q_pipe .* R_bonds;

figure
plot(D_outer*1000, DeltaT_bonds, 'LineWidth', 1.5);
xlabel('Heat-pipe outside diameter [mm]');
ylabel('Temperature drop across both bond layers [K]');
title('Condenser attachment sensitivity at 61.2 W per pipe');
grid on


% Condesing Heat Exchanger (Water/Air - RH)

% Freezable Heat Exchanger (Nitrogen/Water - Thermal)


% Pipe Flow (Convective losses in the PLSS)

% Pumps (Account for frictional and heating effects from the pump)

% Valves (Minimal

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