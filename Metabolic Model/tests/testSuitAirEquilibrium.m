function testSuitAirEquilibrium
% Closed-form equilibrium, evaporation limits and mass/enthalpy checks.
addpath(fileparts(fileparts(mfilename('fullpath'))));
Sat = [1e-4, 2e-4, 3e-4];
T = [20, 25, 30];
CpL = 4180; Hv = 2500900 + 1860 * T; Latent = Hv - CpL * T;
V0 = 0.5 * Sat; L0 = zeros(1, 3);
[V, L, Phase, Q] = equilibrateSuitAir(V0, L0, Sat, Latent);
assert(isequal(V, V0) && all(L == 0) && all(Phase == 0) && all(Q == 0));
V0 = 1.5 * Sat;
[V, L, Phase, Q] = equilibrateSuitAir(V0, L0, Sat, Latent);
assert(max(abs(V-Sat)) < 1e-15 && max(abs(L - 0.5*Sat)) < 1e-15);
assert(max(abs(V+L-V0-L0)) < 1e-15);
assert(abs(sum(Q + (L-L0).*CpL.*T - Phase.*Hv)) < 1e-9);
assert(all(Q > 0));
% Dry gas cannot evaporate more water than available.
L0 = 0.1 * Sat; V0 = zeros(1, 3);
[V, L, ~, Q] = equilibrateSuitAir(V0, L0, Sat, Latent);
assert(max(abs(V-L0)) < 1e-15 && all(L == 0) && all(Q < 0));
assert(max(abs(V+L-V0-L0)) < 1e-15);
% Adequate retained liquid fills the vapor phase to saturation and leaves storage.
L0 = 2 * Sat;
[V, L, Phase, Q] = equilibrateSuitAir(V0, L0, Sat, Latent);
assert(max(abs(V-Sat)) < 1e-15 && max(abs(L-Sat)) < 1e-15);
assert(abs(sum(Q + (L-L0).*CpL.*T - Phase.*Hv)) < 1e-9);
% A negative net vapor source can draw on available liquid, while conserving water.
[V, L] = equilibrateSuitAir(-0.1*Sat, 0.3*Sat, Sat, Latent);
assert(max(abs(V-0.2*Sat)) < 1e-15 && all(L == 0));
fprintf('Suit-air equilibrium closed-form tests PASSED.\n');
end
