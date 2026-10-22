clc
clear
close all;

%% Radiation Area and Temp Model Requirements

% Steady heat rejection
Qreject = 400; % W

% Aluminum emissivity (assumed) with high emission paint
epsilon = 0.9;

% Define range of Areas needed to reject 400 W
A = linspace(0.5,1.5,100); %m^2

% Assumed temperature of the Radiator (assumed body heat)
T_R = 309.6;

%stephan boltmann constant
sigma = 5.67e-8;

% Average temperature at Martian "sea level"
T_inf = 214;

% Calc Watts rejected across varying areas for std Martian sea level
% conditions
Qout = epsilon*A*sigma*(T_R^4 - T_inf^4);

% Identify the minimum area required to reject the target heat load
requiredArea = Qreject ./ (epsilon*sigma*(T_R^4 - T_inf^4));
fprintf('Required radiator area: %.3f m^2\n', requiredArea);
figure()
plot(A,Qout)
title("Heat load rejected across radiator surface areas on Martian std day")
xlabel("Area [m^2]")
ylabel("Qout [W]")
grid on
yline(Qreject,'y--')


% Define Temperature range based on values from the RFP
Trange = linspace(133,293,100);

% Calc A range need to reject 400W across Martian Temps
A_range = Qreject./(epsilon*sigma*(T_R^4 - Trange.^4));

% Plot results of Varying Areas across temperature range
figure()
plot(Trange, A_range)
title("Area required to reject 400W steady state across Martian temperatures")
xlabel("Temperature range [deg K]")
ylabel("Area [m^2] needed to reject 400W")
xline(T_inf, 'y--', 'Avg Surf Temp = 214K', ...
    'LabelOrientation', 'horizontal', ...
    'LabelVerticalAlignment', 'bottom');
yline(requiredArea, 'y--', ...
    sprintf('Area = %.2f m^2', requiredArea), ...
    'LabelHorizontalAlignment', 'left');
grid on





