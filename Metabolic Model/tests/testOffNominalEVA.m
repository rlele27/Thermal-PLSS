function testOffNominalEVA
% Event at an existing duplicate knot, inside an interval, and over the full EVA.
Time = [0; 100; 100; 300; 480];
Activity = ["Nominal"; "Nominal"; "Manual"; "Nominal"; "Nominal"];
Rate = [160; 160; 400; 160; 160];
for Duration = [120, 180, 380, 480]
    S = makeOffNominalEVA(Time, Activity, Rate, Duration, 1300);
    dt = diff(S.Time_min);
    Aerobic = S.Activity(1:end-1) == "Exercise - Aerobic";
    assert(abs(sum(dt(Aerobic)) - Duration) < 1e-10);
    assert(sum(dt) == 480 && all(dt >= 0));
    assert(all(S.MetabolicRate_W(S.Time_min >= 480 - Duration) == 1300));
    Before = Time < 480 - Duration;
    assert(isequal(S.Time_min(1:sum(Before)), Time(Before)));
    assert(isequal(S.MetabolicRate_W(1:sum(Before)), Rate(Before)));
end
fprintf('Off-nominal boundary and duration checks passed.\n');
end
