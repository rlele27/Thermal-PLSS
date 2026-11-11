function Data = buildEVAData(FileName)
% BUILDEVADATA Build the MAT database and store immutable source lookup data.
% Inputs: FileName - destination MAT-file path.
% Outputs: Data - existing database or newly initialized source database.
% Units: Original source units are explicit in field names.
% Side effects: Initializes source data; adds missing LCG data without clearing results.
% Exception to the shared-function rule: source-data initialization lives here.
% METMAN: BVAD Rev.2 Table 3-26; original Metabolic.xlsx Sheet1 A4:E36.
% NASA LCG: NTRS 20150004602, Tables 5 and 7 (four calibration/three held-out rows).
if isfile(FileName)
    Loaded = load(FileName,'Data');
    Data = Loaded.Data;
    if isfield(Data.Source.LCGReference,'DynamicRawTable10')
        return;
    end
else
    Data = struct();
    Data.Source.MetMan.StartTime_hr = [0; 0.25; 0.5; 0.75; 1; 1.25; 1.5; 1.75; 2; 2.25; 2.5; 2.75; 3; 3.25; 3.5; 3.75; 4; 4.25; 4.5; 4.75; 5; 5.25; 5.5; 5.75; 6; 6.25; 6.5; 6.75; 7; 7.25; 7.5; 7.75; 8];
    Data.Source.MetMan.EndTime_hr = [0.25; 0.5; 0.75; 1; 1.25; 1.5; 1.75; 2; 2.25; 2.5; 2.75; 3; 3.25; 3.5; 3.75; 4; 4.25; 4.5; 4.75; 5; 5.25; 5.5; 5.75; 6; 6.25; 6.5; 6.75; 7; 7.25; 7.5; 7.75; 8; 16];
    Data.Source.MetMan.MetabolicRate_kJ_hr = [580; 5197; 5197; 5197; 1452; 1452; 1452; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580; 580];
    Data.Source.MetMan.Activity = {'Nominal'; 'Exercise - Aerobic'; 'Exercise - Aerobic'; 'Exercise - Aerobic'; 'Exercise - Resistance'; 'Exercise - Resistance'; 'Exercise - Resistance'; 'Recovery 0-15'; 'Recovery 15-30'; 'Recovery 30-45'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'; 'Nominal'};
    Data.Source.Nominal.Time_min = [0; 40; 40; 60; 60; 90; 90; 100; 100; 140; 140; 240; 240; 270; 270; 330; 330; 360; 360; 440; 440; 450; 450; 480];
    Data.Source.Nominal.MetabolicRate_Btu_hr = [675; 675; 1100; 1100; 850; 850; 2000; 2000; 900; 900; 520; 520; 850; 850; 350; 350; 1250; 1250; 1000; 1000; 2000; 2000; 1100; 1100];
    Data.Source.Nominal.Activity = {'Nominal'; 'Nominal'; 'Exercise - Resistance'; 'Exercise - Resistance'; 'Nominal'; 'Nominal'; 'Exercise - Aerobic'; 'Exercise - Aerobic'; 'Above Nominal'; 'Above Nominal'; 'Nominal'; 'Nominal'; 'Exercise - Resistance'; 'Exercise - Resistance'; 'Nominal'; 'Nominal'; 'Exercise - Resistance'; 'Exercise - Resistance'; 'Above Nominal'; 'Above Nominal'; 'Exercise - Aerobic'; 'Exercise - Aerobic'; 'Nominal'; 'Nominal'};
    Data.Source.LCGReference.Raw = [ ...
    2 186.05 53.27 59.25 77.84 52.10 1112 1263; 
        4 184.74 52.94 58.87 78.75 48.26 1241 1325; 
        3 185.73 53.20 59.00 79.20 47.02 1077 1258; 
        5 132.23 54.52 62.09 78.13 48.85 957 1173; 
        6 189.57 51.44 57.81 76.55 52.65 1217 1253; 
        7 200.44 48.89 54.15 75.29 44.46 1069 1166; 
        8 178.29 49.28 55.78 76.42 45.17 1073 1144
    ];
    Data.Simulation = struct();
    Data.Hardware = struct();
end
% Bue et al. (2015), Table 10, p.17: EMU low-profile paired measurements.
% Columns: test day, UA Btu/(hr F), metabolic Btu/hr, water flow lbm/hr.
Data.Source.LCGReference.DynamicRawTable10 = [ ...
    9 59.25 1718 108; 9 33.62 1001 39; 9 59.82 1283 159; 9 28.43 862 60; ...
    10 48.66 1616 199; 10 44.14 1045 157; 10 53.95 1235 154; 10 42.99 873 120; ...
    11 44.14 1582 200; 11 35.69 842 107; 11 43.66 1423 116; 11 36.82 809 121; ...
    12 54.43 1885 199; 12 36.39 967 154; 12 38.03 1350 51; 12 35.36 874 80];
save(FileName,'Data','-v7');
end
