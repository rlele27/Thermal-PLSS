% Raaghav Lele, [Add your name if you contribute]
% Date created: 10/19/2026
% Thermal Component Model 

%% Part one: Heat acquisition
% This section will focus on taking in the source heat.
% The modeled human heat will come directly from the metabolic model. The 
% heat from each subsystem will also be added as unputs. This won't be just modeled as heat
% acquisition, but the way that we plan to acquire heat out of htat system
% (fans, radiators or whatever) will be modeled

%% Part two: Heat Transport
% This section will follow that heat acquisition section and the results
% from the previous section will be used as an input. Heat that is lost or
% created through pipe flow will be modeled. Things such as heat loss through an insulation layer,
% major and minor presssure losses, and laminar v turbulent flow will be modeled

%% Part three: Heat Rejection
% The results from the previous section will be used at inputs fro this
% section. Heat that is trasnferred from the pipes to our radiator
% will be modeled. Thereafter, 1D heat transfer will be applied across the
% radiator, and the radiative, conductive, and convective heat rejection
% into the Martian atmosphere will be measured. 
%% Part four: Analysis
% After part 3, The remaining values will be the temperature of the water 
% after the entire process is done, and the time taken to complete the loop
% from part 1 thru 3. The entire process will be iterative and will see if
% the heat rejection rate and system durability will last a full 8 hour EVA