function [Model,MoistureRate_g_s,Output] = controlLCGStep(StartModel,Environment,ActivityRatio,Step_s,StoredHeat_J,Advance)
% CONTROLLCGSTEP Increase flow before lowering inlet temperature.
% Inputs: starting state/environment, activity, seconds, stored J, coupled step.
% Outputs: accepted physical state and controller diagnostics. No file writes.
% All trials start from the same state; only the accepted trial advances history.
Mass_kg = StartModel.Parameters.Body.Weight_kg;
HasControl = isfield(Environment.LCG,'Controller');
TrialEnvironment = Environment;
Evaluations = 1;
UpperTemperature_C = Environment.LCG.InletTemperature_C;
if ~HasControl || ~Environment.LCG.Controller.Enabled || ~Environment.LCG.Enabled
    [Model,MoistureRate_g_s,Output] = Advance(StartModel,TrialEnvironment,ActivityRatio,Step_s);
else
    Control = Environment.LCG.Controller;
    Target_J = Control.TargetStoredHeat_kJ_kg*1000*Mass_kg;
    UpperTemperature_C = Control.TemperatureBounds_C(2);
    BaselineFlow = Environment.LCG.MassFlow_kg_s;
    MaximumFlow = BaselineFlow;
    if Control.FlowControlEnabled
        MaximumFlow = Control.MaximumFlow_kg_h/3600;
        % Retain accepted flow near the target; release gradually below its
        % deadband. Increases remain unrestricted to protect against heat peaks.
        if isfield(StartModel,'LCGControlFlow_kg_s')
            PreviousFlow = min(MaximumFlow,max(BaselineFlow,StartModel.LCGControlFlow_kg_s));
            Release = 0;
            if StoredHeat_J < Target_J-Control.StorageDeadband_kJ_kg*1000*Mass_kg
                Release = Control.FlowReleaseRate_kg_h_min*(Step_s/60)/3600;
            end
            TrialEnvironment.LCG.MassFlow_kg_s = max(BaselineFlow,PreviousFlow-Release);
        end
    end
    TrialEnvironment.LCG.InletTemperature_C = UpperTemperature_C;
    [Model,MoistureRate_g_s,Output] = Advance(StartModel,TrialEnvironment,ActivityRatio,Step_s);
    Energy_J = StoredHeat_J+Output.BodyStorage_W*Step_s;
    WeakValues = [TrialEnvironment.LCG.MassFlow_kg_s,UpperTemperature_C];
    StrongValues = [MaximumFlow,Control.TemperatureBounds_C(1)];
    Tolerances = [Control.FlowTolerance_kg_h/3600,Control.TemperatureTolerance_C];
    Fields = {'MassFlow_kg_s','InletTemperature_C'};
    for Stage = 1:2
        if Energy_J <= Target_J, break; end
        Weak = WeakValues(Stage); Strong = StrongValues(Stage);
        if Weak == Strong, continue; end
        WeakEnergy_J = Energy_J;
        TrialEnvironment.LCG.(Fields{Stage}) = Strong;
        [Model,MoistureRate_g_s,Output] = Advance(StartModel,TrialEnvironment,ActivityRatio,Step_s);
        Energy_J = StoredHeat_J+Output.BodyStorage_W*Step_s;
        Evaluations = Evaluations+1;
        if Energy_J <= Target_J
            StrongEnergy_J = Energy_J;
            AcceptedEnvironment = TrialEnvironment;
            for Iteration = 1:Control.MaximumSearchIterations
                if abs(Strong-Weak) <= Tolerances(Stage), break; end
                Fraction = (WeakEnergy_J-Target_J)/(WeakEnergy_J-StrongEnergy_J);
                Fraction = min(.9,max(.1,Fraction));
                Trial = Weak+Fraction*(Strong-Weak);
                TrialEnvironment.LCG.(Fields{Stage}) = Trial;
                [TrialModel,TrialMoisture,TrialOutput] = Advance(StartModel,TrialEnvironment,ActivityRatio,Step_s);
                TrialEnergy_J = StoredHeat_J+TrialOutput.BodyStorage_W*Step_s;
                Evaluations = Evaluations+1;
                if TrialEnergy_J <= Target_J
                    Strong = Trial; StrongEnergy_J = TrialEnergy_J;
                    Model = TrialModel; MoistureRate_g_s = TrialMoisture; Output = TrialOutput;
                    AcceptedEnvironment = TrialEnvironment;
                else
                    Weak = Trial; WeakEnergy_J = TrialEnergy_J;
                end
            end
            TrialEnvironment = AcceptedEnvironment;
            break;
        end
    end
end
% Store controller memory only after accepting a physical coupled step.
Model.LCGControlFlow_kg_s = TrialEnvironment.LCG.MassFlow_kg_s;
Output.LCGInletUpperBound_C = UpperTemperature_C;
Output.LCGInletTemperature_C = TrialEnvironment.LCG.InletTemperature_C;
Output.LCGMassFlow_kg_s = TrialEnvironment.LCG.MassFlow_kg_s;
Output.BodyStoredHeat_kJ_kg = (StoredHeat_J+Output.BodyStorage_W*Step_s)/(1000*Mass_kg);
Output.LCGControllerEvaluations = Evaluations;
Output.LCGFlowAtMaximum = false;
Output.HeatStorageBelowZero = Output.BodyStoredHeat_kJ_kg < -1e-9;
Output.LCGControlTargetMet = true;
Output.HeatStorageLimitExceeded = false;
Output.LCGControlAtMinimum = false;
Output.RemainingCoolingShortfall_W = 0;
if HasControl
    Control = Environment.LCG.Controller;
    Output.RemainingCoolingShortfall_W = max(0,(StoredHeat_J ...
        +Output.BodyStorage_W*Step_s-Control.TargetStoredHeat_kJ_kg*1000*Mass_kg)/Step_s);
    Output.LCGControlTargetMet = Output.BodyStoredHeat_kJ_kg <= Control.TargetStoredHeat_kJ_kg+1e-9;
    Output.HeatStorageLimitExceeded = Output.BodyStoredHeat_kJ_kg > Control.LimitStoredHeat_kJ_kg+1e-9;
    Output.LCGFlowAtMaximum = Control.Enabled && Environment.LCG.Enabled && Control.FlowControlEnabled ...
        && Output.LCGMassFlow_kg_s*3600 >= Control.MaximumFlow_kg_h-Control.FlowTolerance_kg_h;
    Output.LCGControlAtMinimum = Control.Enabled && Environment.LCG.Enabled ...
        && Output.LCGInletTemperature_C <= Control.TemperatureBounds_C(1)+Control.TemperatureTolerance_C;
end
end
