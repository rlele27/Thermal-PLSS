%% Compatibility Launcher
clc;
clear; 
close all;
% All component calculations and assumptions are now in the main script.
% This entry point runs the complete metabolic, RH and component sizing model.
%run(fullfile(fileparts(mfilename('fullpath')), 'Nominal_Metabolic_Profile.m'));
 
%% RH cooling loop -> Work In via compressor
% This section will provide a range of values corresponding to different
% pressure rise scenarios. This will go directly into the COP calculation
efficiency_compressor = 0.70;
efficiency_motor = 0.80;
m_dot = 0.1:0.1:2; %g/s Varying mass flow rate
 
% Loading coolant tables
vap = loadR134aVaporTable("Vapor R134.xlsx");
R_134_liquid_props = readmatrix("Liquid R134.xlsx");  % not used yet
isobaric_table = loadR134aTable("Isobaric_data_R134.xlsx");
isothermal_table = loadR134aTableTherm("Isothermal_R134a.xlsx");
 
% State 1: saturated vapor at T_1 (compressor inlet)
T_1 = 293.15; % K
P_1 = lookupR134a(vap, "T", T_1, "P"); % kPa    saturation pressure at T_1 (~571.7)
h_1 = lookupR134a(vap, "T", T_1, "h"); % kJ/kg
s_1 = lookupR134a(vap, "T", T_1, "s"); % kJ/kg-K
 
% State 2: ACTUAL compressor-exit state at each discharge temperature T_2 (not isentropic).
% The compressor efficiency links the actual and isentropic enthalpy rise at the same P_2:
%   efficiency_compressor = (h_2_s - h_1)/(h_2_a - h_1)
% so P_2 is the pressure at which that holds, and s_2 is read off the tables at (P_2, h_2_a).
T_2 = 294:1:450;% K  actual discharge temperature sweep
[h_2_a, P_2, s_2] = actualStateR134a(isobaric_table, isothermal_table, T_2, s_1, h_1, T_1, P_1, efficiency_compressor);
% kJ/kg, kPa, kJ/kg-K   actual state 2 (s_2 > s_1)
h_2_s = h_1 + efficiency_compressor.*(h_2_a - h_1);% kJ/kg ideal enthalpy at the same P_2 (reference)
 
Power_compressor_pressure = (m_dot(10).*(h_2_a - h_1))./efficiency_motor;% W m_dot set to 1 g/s
 
P_const = 700;                                   % kPa
ok = ~isnan(P_2);                                % T_2 beyond the table's coverage gives NaN
h_2_a_const = interp1(P_2(ok), h_2_a(ok), P_const);
Power_compressor_m_dot = (m_dot.*(h_2_a_const - h_1))./efficiency_motor;% W fixed pressure
 
figure();
plot(m_dot, Power_compressor_m_dot);
xlabel("Mass flow rate [g/s]"); ylabel("Compressor electrical power [W]");
title(sprintf("P_2 = %.0f kPa", P_const));

figure();
plot(P_2, Power_compressor_pressure);
xlabel("Discharge pressure P_2 [kPa]"); ylabel("Compressor electrical power [W]");
title(sprintf("Mass flow = %.1f g/s", m_dot(10)));
 
%% RH cooling loop -> Heat Input
% Heat absorbed in the evaporator (the cooling the cycle delivers):
%   Q_in = m_dot * (h_1 - h_4),   h_4 = h_3  (isenthalpic expansion valve)
% State 3 = saturated liquid leaving the condenser at P_2.
% Units: [g/s] * [kJ/kg] = [W].
sat_liq = loadR134aSatLiquidTable("Saturated liquid.xlsx");   % saturated liquid table (state 3)
T_three = lookupR134a(sat_liq, "P", P_2, "T");              % K, saturation temperature at each P_2
h_three = lookupR134aSatLiquid(sat_liq, T_three, "h");      % kJ/kg, one value per temperature
h_four  = h_three;                                          % valve: h_4 = h_3
 
% (1) Fixed mass flow, varying condenser pressure
Q_in_pressure = m_dot(10).*(h_1 - h_four);                % W at m_dot(10) = 1 g/s
 
% (2) Fixed pressure, varying mass flow (uses P_const from the section above)
T_const = lookupR134a(sat_liq, "P", P_const, "T");          % K
h_four_const = lookupR134aSatLiquid(sat_liq, T_const, "h");
Q_in_m_dot   = m_dot.*(h_1 - h_four_const);               % W

COP = 165./Power_compressor_pressure;
 
figure();
plot(m_dot, Q_in_m_dot);
xlabel("Mass flow rate [g/s]"); ylabel("Evaporator heat input Q_{in} [W]");
title(sprintf("P_2 = %.0f kPa", P_const));
 
figure();
hold on;
plot(P_2, Q_in_pressure);
plot(P_2, Power_compressor_pressure);
xlabel("Condenser pressure P_2 [kPa]"); ylabel("Evaporator heat input Q_{in} [W]");
title(sprintf("Mass flow = %.1f g/s", m_dot(10)));
 
%% Condenser Heat Transfer Analysis
 
%% Pressure Losses - Condenser
 
%% Pressure Losses - Evaporator
 
%% Pressure Losses - Pipe 
%% ========================= Local functions 
% (Local functions must stay at the END of a script file.)
 
function tbl = loadR134aVaporTable(fileName)
% Reads the NIST saturation (vapor) table once and caches it.
% Column order in the sheet (no header row):
%   1 T[K]  2 P[MPa]  3 rho[kg/m3]  4 v[m3/kg]  5 u[kJ/kg]  6 h[kJ/kg]
%   7 s[kJ/kg-K]  8 cv  9 cp  10 sound speed[m/s]  11 JT[K/MPa]
%   12 viscosity[uPa-s]  13 k[W/m-K]  14 phase (text)
    persistent cache cachedName
    fileName = string(fileName);
    if ~isempty(cache) && cachedName == fileName
        tbl = cache;
        return
    end
 
    raw = readmatrix(fileName);                 % text cells come back as NaN
    raw = raw(:, 1:13);                         % drop the phase-text column
    raw = raw(~isnan(raw(:,1)) & ~isnan(raw(:,6)), :);   % drop blank / 'Auxiliary Data' rows
    raw = sortrows(raw, 2);                     % ascending in pressure
 
    raw(:,2) = raw(:,2) * 1e3;                  % MPa -> kPa
 
    tbl.cols = ["T" "P" "rho" "v" "u" "h" "s" "cv" "cp" "w" "jt" "mu" "k"];
    tbl.data = raw;                             % P is in kPa from here on
 
    cache = tbl;
    cachedName = fileName;
end
 
function out = lookupR134a(tbl, inName, inVal, outName)
% Linear interpolation of any property against T or P along the saturation line.
%   out = lookupR134a(vap, "P", 304,        "h")   % h at 304 kPa
%   out = lookupR134a(vap, "T", 274.15,     "h")   % h at 274.15 K
%   out = lookupR134a(vap, "P", 300:10:700, "h")   % vectorized: one call, no loop
% Exact matches return the table value; values between rows are interpolated.
% Values outside the table range return NaN (no extrapolation) and warn.
    ix = find(tbl.cols == string(inName),  1);
    iy = find(tbl.cols == string(outName), 1);
    if isempty(ix) || isempty(iy)
        error("lookupR134a:badName", "Valid names: %s", strjoin(tbl.cols, ", "));
    end
 
    x = tbl.data(:, ix);
    y = tbl.data(:, iy);
    if ~issorted(x, "strictascend")
        error("lookupR134a:notMonotonic", ...
              "'%s' is not monotonic along the saturation line; look up by T or P.", inName);
    end
 
    out = interp1(x, y, inVal, "linear");       % binary search per query point
 
    bad = isnan(out) & ~isnan(inVal);
    if any(bad(:))
        warning("lookupR134a:outOfRange", ...
                "%d value(s) outside table range [%.4g, %.4g] for %s -> NaN.", ...
                nnz(bad), x(1), x(end), inName);
    end
end
 
function tbl = loadR134aTable(fileName)
% Reads the NIST isobaric table once (cached) and keeps only the VAPOR rows.
% Sheet columns (no header row):
%   1 T[K]  2 P[MPa]  3 rho  4 v  5 u  6 h[kJ/kg]  7 s  8 cv  9 cp[kJ/kg-K]
%   10 sound speed  11 JT  12 viscosity  13 k  14 phase (text)
% Pressure is converted from MPa to kPa on load.
    persistent cache cachedName
    fileName = string(fileName);
    if ~isempty(cache) && cachedName == fileName
        tbl = cache;
        return
    end
 
    C = readcell(fileName);                          % need the phase text, so not readmatrix
    isNumRow = cellfun(@(x) isnumeric(x) && isscalar(x), C(:,1));
    C = C(isNumRow, :);                              % drop any blank / note rows
    data  = cell2mat(C(:, 1:13));
    phase = string(C(:, 14));
 
    data = data(phase == "vapor", :);                % saturated-vapor + superheated rows
    data(:,2) = data(:,2) * 1e3;                     % MPa -> kPa
 
    [Pk, ~, grp] = unique(round(data(:,2), 6));      % one group per isobar, ascending in P
    nP = numel(Pk);
    if nP < 2
        error("loadR134aIsobaricTable:fewIsobars", "Need at least two isobars to interpolate in P.");
    end
 
    tbl.cols = ["T" "P" "rho" "v" "u" "h" "s" "cv" "cp" "w" "jt" "mu" "k"];
    tbl.P = Pk;                                      % kPa, ascending
    tbl.D = cell(nP, 1);                             % tbl.D{i}: vapor rows of isobar i, sorted by T
    for i = 1:nP
        Di = sortrows(data(grp == i, :), 1);
        if ~issorted(Di(:,1), "strictascend")
            error("loadR134aIsobaricTable:dupT", "Repeated temperatures in the %.0f kPa vapor rows.", Pk(i));
        end
        tbl.D{i} = Di;
    end
 
    cache = tbl;
    cachedName = fileName;
end
 
function tbl = loadR134aTableTherm(fileName)
% Reads the NIST ISOTHERMAL table once (cached) and keeps only the VAPOR rows.
% Sheet columns (no header row):
%   1 T[K]  2 P[MPa]  3 rho  4 v  5 u  6 h[kJ/kg]  7 s[kJ/kg-K]  8 cv  9 cp[kJ/kg-K]
%   10 sound speed  11 JT  12 viscosity  13 k  14 phase (text)
% Pressure is converted from MPa to kPa on load.
% tbl.T(i) is the temperature of isotherm i; tbl.D{i} holds its vapor rows, ascending in P.
    persistent cache cachedName
    fileName = string(fileName);
    if ~isempty(cache) && cachedName == fileName && isfield(cache, "sortedBy")
        tbl = cache;
        return
    end
 
    C = readcell(fileName);                          % need the phase text, so not readmatrix
    isNumRow = cellfun(@(x) isnumeric(x) && isscalar(x), C(:,1));
    C = C(isNumRow, :);                              % drop any blank / note rows
    data  = cell2mat(C(:, 1:13));
    phase = string(C(:, 14));
 
    data = data(phase == "vapor", :);                % saturated-vapor + superheated rows only
    data(:,2) = data(:,2) * 1e3;                     % MPa -> kPa
 
    [Tk, ~, grp] = unique(round(data(:,1), 6));      % one group per isotherm, ascending in T
    nT = numel(Tk);
    if nT < 2
        error("loadR134aTableTherm:fewIsotherms", "Need at least two isotherms.");
    end
 
    tbl.cols = ["T" "P" "rho" "v" "u" "h" "s" "cv" "cp" "w" "jt" "mu" "k"];
    tbl.T = Tk;                                      % K, ascending
    tbl.D = cell(nT, 1);                             % tbl.D{i}: vapor rows of isotherm i, sorted by P
    for i = 1:nT
        Di = sortrows(data(grp == i, :), 2);         % T is constant inside an isotherm, so sort by P (col 2)
        if ~issorted(Di(:,2), "strictascend")
            error("loadR134aTableTherm:dupP", "Repeated pressures in the %.0f K vapor rows.", Tk(i));
        end
        tbl.D{i} = Di;
    end
    tbl.sortedBy = "P";                              % tag so an older cached struct is never reused
 
    cache = tbl;
    cachedName = fileName;
end
 
function [h_s, T_s] = isentropeR134a(tbl, P, s1, h1, T1, P1)
% Enthalpy and temperature of the isentropic state at pressure P [kPa], reached from
% state 1 (P1, T1, h1, entropy s1) by reversible adiabatic compression.
% On every table isobar above P1, the temperature where s = s1 is found by inverting the
% (monotonic) s(T) column; the isentrope is then interpolated in P (pchip), starting from
% state 1 itself, so the saturation boundary never produces NaNs.
% P must lie in [P1, highest isobar]; outside that range the result is NaN (with a warning).
    Pn = P1;  hn = h1;  Tn = T1;                     % node 1 = state 1 itself
    for i = 1:numel(tbl.P)
        if tbl.P(i) <= P1, continue, end             % isobars at or below P1 can't hold the isentrope
        Di  = tbl.D{i};
        s_i = Di(:,7);
        if ~issorted(s_i, "strictascend") || s1 < s_i(1) || s1 > s_i(end)
            error("isentropeR134a:outOfTable", ...
                  "Isentrope s = %.4f kJ/kg-K leaves the table at %.0f kPa.", s1, tbl.P(i));
        end
        Pn(end+1) = tbl.P(i);                              %#ok<AGROW>
        hn(end+1) = interp1(s_i, Di(:,6), s1, "linear");   %#ok<AGROW>
        Tn(end+1) = interp1(s_i, Di(:,1), s1, "linear");   %#ok<AGROW>
    end
    if numel(Pn) < 2
        error("isentropeR134a:noIsobar", "No table isobar above P1 = %.1f kPa.", P1);
    end
 
    h_s = interp1(Pn, hn, P, "pchip", NaN);          % NaN outside [P1, top isobar]
    T_s = interp1(Pn, Tn, P, "pchip", NaN);
 
    bad = isnan(h_s) & ~isnan(P);
    if any(bad(:))
        warning("isentropeR134a:pressureRange", ...
                "%d point(s) outside [%.1f, %.0f] kPa -> NaN.", nnz(bad), Pn(1), Pn(end));
    end
end
 
function [h_a, P_a, s_a] = actualStateR134a(isoP, isoT, T, s1, h1, T1, P1, eta)
% ACTUAL (non-isentropic) compressor-exit state at each discharge temperature T [K]:
%   h_a [kJ/kg], P_a [kPa], s_a [kJ/kg-K]   (s_a > s1 because of the efficiency loss)
%
% The isentropic efficiency ties the actual enthalpy rise to the isentropic one reached at the
% SAME discharge pressure:
%       eta = (h_2s - h1)/(h_2a - h1)    ->    h_2a(P) = h1 + (h_2s(P) - h1)/eta
% Nodes along the discharge locus (state 1 plus the pressures below):
%   - every isobar of isoP above P1: h_2s from s = s1, then h_2a, then T_2a and s_2 by
%     inverting that isobar's h column;
%   - every isotherm of isoT that crosses s = s1 above the last isobar: P and h_2s there, then
%     T_2a and s_2 by inverting h across the isotherms at that pressure.
% The locus is interpolated at the requested T (pchip in ln P). T above the hottest node
% returns NaN, with a warning.
    Pn = P1;  hn = h1;  Tn = T1;  sn = s1;           % node 1 = state 1 itself
 
    for i = 1:numel(isoP.P)
        if isoP.P(i) <= P1, continue, end
        Di  = isoP.D{i};                             % rows ascending in T
        h_i = Di(:,6);  s_i = Di(:,7);
        if s1 < s_i(1) || s1 > s_i(end), continue, end
        h2s = interp1(s_i, h_i, s1);
        h2a = h1 + (h2s - h1)/eta;
        if h2a > h_i(end), continue, end             % discharge hotter than the table
        Pn(end+1) = isoP.P(i);                       %#ok<AGROW>
        hn(end+1) = h2a;                             %#ok<AGROW>
        Tn(end+1) = interp1(h_i, Di(:,1), h2a);      %#ok<AGROW>
        sn(end+1) = interp1(h_i, s_i, h2a);          %#ok<AGROW>
    end
 
    for j = 1:numel(isoT.T)
        if isoT.T(j) <= T1, continue, end
        Dj  = isoT.D{j};                             % rows ascending in P; s falls as P rises
        s_j = Dj(:,7);
        if s1 > s_j(1) || s1 < s_j(end), continue, end   % isentrope does not cross this isotherm
        if ~issorted(s_j, "strictdescend")
            error("actualStateR134a:notMonotonic", ...
                  "s is not strictly falling with P on the %.0f K isotherm.", isoT.T(j));
        end
        Pk = interp1(flipud(s_j), flipud(Dj(:,2)), s1);
        if Pk <= max(Pn), continue, end              % keep P strictly increasing along the locus
        h2s = interp1(flipud(s_j), flipud(Dj(:,6)), s1);
        h2a = h1 + (h2s - h1)/eta;
        [Tc, hc, sc] = isothermsAtP(isoT, Pk);
        if numel(Tc) < 2 || h2a < hc(1) || h2a > hc(end), continue, end
        Pn(end+1) = Pk;                              %#ok<AGROW>
        hn(end+1) = h2a;                             %#ok<AGROW>
        Tn(end+1) = interp1(hc, Tc, h2a);            %#ok<AGROW>
        sn(end+1) = interp1(hc, sc, h2a);            %#ok<AGROW>
    end
 
    if numel(Pn) < 2 || ~issorted(Tn, "strictascend") || ~issorted(Pn, "strictascend")
        error("actualStateR134a:locus", "Discharge locus is not monotonic; check the tables.");
    end
 
    lnP = log(Pn);
    P_a = exp(interp1(Tn, lnP, T, "pchip", NaN));    % NaN outside [T1, Tn(end)]
    h_a = interp1(lnP, hn, log(P_a), "pchip", NaN);
    s_a = interp1(lnP, sn, log(P_a), "pchip", NaN);
 
    bad = isnan(P_a) & ~isnan(T);
    if any(bad(:))
        warning("actualStateR134a:temperatureRange", ...
                "%d point(s) outside [%.2f, %.1f] K -> NaN (tables reach T_2 = %.1f K at eta = %.2f).", ...
                nnz(bad), Tn(1), Tn(end), Tn(end), eta);
    end
end
 
function [Tc, hc, sc] = isothermsAtP(tbl, P)
% h and s at pressure P [kPa] on every isotherm whose vapor rows cover P (ascending in T).
    Tc = zeros(0,1);  hc = Tc;  sc = Tc;
    for j = 1:numel(tbl.T)
        Dj = tbl.D{j};
        if P < Dj(1,2) || P > Dj(end,2), continue, end
        Tc(end+1,1) = tbl.T(j);                      %#ok<AGROW>
        hc(end+1,1) = interp1(Dj(:,2), Dj(:,6), P);  %#ok<AGROW>
        sc(end+1,1) = interp1(Dj(:,2), Dj(:,7), P);  %#ok<AGROW>
    end
end

function tbl = loadR134aSatLiquidTable(fileName)
% Reads the NIST SATURATED-LIQUID table once (cached).
% Sheet columns (no header row):
%   1 T[K]  2 P[MPa]  3 rho[kg/m3]  4 v[m3/kg]  5 u[kJ/kg]  6 h[kJ/kg]  7 s[kJ/kg-K]  8 cv  9 cp
%   10 sound speed[m/s]  11 JT  12 viscosity[uPa-s]  13 k[W/m-K]  14 surface tension[N/m]
%   15 phase (text)
% Pressure is converted from MPa to kPa. The tbl.cols / tbl.data layout matches
% loadR134aVaporTable, so lookupR134a(tbl, "P", P, "T") works on this table too.
    persistent cache cachedName
    fileName = string(fileName);
    if ~isempty(cache) && cachedName == fileName
        tbl = cache;
        return
    end
 
    C = readcell(fileName);                          % need the phase text, so not readmatrix
    isNumRow = cellfun(@(x) isnumeric(x) && isscalar(x), C(:,1));
    C = C(isNumRow, :);                              % drop any blank / note rows
    data  = cell2mat(C(:, 1:14));
    phase = string(C(:, 15));
 
    data = data(phase == "liquid", :);               % saturated-liquid rows only
    data = sortrows(data, 1);                        % ascending in T
    data(:,2) = data(:,2) * 1e3;                     % MPa -> kPa
    if ~issorted(data(:,1), "strictascend") || ~issorted(data(:,2), "strictascend")
        error("loadR134aSatLiquidTable:notMonotonic", "T and P must both rise strictly down the table.");
    end
 
    tbl.cols = ["T" "P" "rho" "v" "u" "h" "s" "cv" "cp" "w" "jt" "mu" "k" "sigma"];
    tbl.data = data;                                 % P is in kPa from here on
 
    cache = tbl;
    cachedName = fileName;
end
 
function out = lookupR134aSatLiquid(tbl, T, outName)
% Saturated-liquid property at each temperature in T [K] (a scalar or a list), linearly
% interpolated in the table (0.2 K spacing); exact table temperatures return the table value.
%   h_f = lookupR134aSatLiquid(sat_liq, 300:1:320,    "h")      % list of temperatures -> kJ/kg
%   P_f = lookupR134aSatLiquid(sat_liq, [295.5 301.2], "P")     % kPa
% Temperatures outside the table's range return NaN (no extrapolation), with a warning.
    iy = find(tbl.cols == string(outName), 1);
    if isempty(iy)
        error("lookupR134aSatLiquid:badName", "Valid names: %s", strjoin(tbl.cols, ", "));
    end
 
    out = interp1(tbl.data(:,1), tbl.data(:,iy), T, "linear");   % NaN outside the table
 
    bad = isnan(out) & ~isnan(T);
    if any(bad(:))
        warning("lookupR134aSatLiquid:temperatureRange", ...
                "%d temperature(s) outside the saturated-liquid table [%.2f, %.2f] K -> NaN.", ...
                nnz(bad), tbl.data(1,1), tbl.data(end,1));
    end
end