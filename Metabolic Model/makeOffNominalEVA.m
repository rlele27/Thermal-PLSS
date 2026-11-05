function Scenario = makeOffNominalEVA(Time_min, Activity, Rate_W, Duration_min, AerobicRate_W)
% Preserve the nominal piecewise-constant history until the final aerobic block.
Time_min = Time_min(:); Activity = string(Activity(:)); Rate_W = Rate_W(:);
validateattributes(Duration_min, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(AerobicRate_W, {'numeric'}, {'scalar', 'finite', 'positive'});
assert(numel(Time_min) == numel(Activity) && numel(Time_min) == numel(Rate_W) ...
    && numel(Time_min) >= 2 && all(isfinite(Time_min)) && all(diff(Time_min) >= 0), ...
    'EVA:ScenarioInputs', 'Use matching arrays and nondecreasing finite times.');
Boundary = Time_min(end) - Duration_min;
assert(Boundary >= Time_min(1), 'EVA:ScenarioDuration', 'Aerobic duration exceeds the EVA.');
% Retain duplicate transition knots. Add the exact boundary even inside an interval.
Keep = Time_min < Boundary;
ScenarioTime = [Time_min(Keep); Boundary; Time_min(end)];
ScenarioActivity = [Activity(Keep); "Exercise - Aerobic"; "Exercise - Aerobic"];
ScenarioRate = [Rate_W(Keep); AerobicRate_W; AerobicRate_W];
Scenario = table(ScenarioTime, ScenarioActivity, ScenarioRate, ...
    'VariableNames', {'Time_min', 'Activity', 'MetabolicRate_W'});
end
