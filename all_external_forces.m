function [FX, FY] = all_external_forces(FX_IN, FY_IN, X_S, Y_S, N_w, DL, filament_separation, Np, weight_per_unit_length, L, nt, TOTAL_STEPS, N_pairs)

FX = FX_IN;
FY = FY_IN;

% Forces to include
gravity = false;
cross_links_hanpeskin = true;
cross_links_trig = false;
cross_links_linear = false;
passive_links_partial = false;
passive_links_full = true;
basal_coupling = false;
external_pinch = false;

% -- PARAMETERS (NOT FOR HAN PESKIN)--

% Cross link equilibrium length
cl_el = sqrt(filament_separation^2 + DL^2);

% Constants for cross links (linear and trig)
k_a = 1;
k_b = 1;
gamma = 1;

% Constants for partial or full passive links
k_p = 1;
k_f = 10;

% Constants for basal coupling
k_b = 50;

% Constants for external pinch
k_e = 1;
%seg_a =  N_w + 3;
%seg_b =  N_w + 8;









% ---- Add Forces ----

if gravity
    FY = -weight_per_unit_length*L/N_w*ones(Np,1);
end
   
% Cross linked forces using han peskin
if cross_links_hanpeskin
    [FX, FY] = cl_forces_hanpeskin(FX, FY, X_S, Y_S, N_w, nt, TOTAL_STEPS, N_pairs);
end
    
% Cross linked forces with variable arc length, trig
if cross_links_trig
    [FX, FY] = cl_forces_variable_al(FX, FY, X_S, Y_S, N_w, k_a, k_b, cl_el, cl_el, gamma);
end
    
% Cross linked forces with variable arc length, linear
if cross_links_linear
    [FX, FY] = cl_forces_variable_al_linear(FX, FY, X_S, Y_S, N_w, k_a, k_b, cl_el, cl_el, gamma);
end
    
% Passive Links (every other set of segments)
if passive_links_partial
    for j=1:((N_w/2)-1)
        [FX, FY] = add_spring_force_between_segments(FX, FY, X_S, Y_S, 2*j - 1, N_w + 2*j - 1, k_p, filament_separation);
    end
end
    
% Passive Links (every set of segments)
% - for use with pairs of filaments
if passive_links_full
    for i_pairs=1:N_pairs
        for j=1:N_w
            seg_a = (((2 * i_pairs) - 2) * N_w) + j;
            seg_b = (((2 * i_pairs) - 1) * N_w) + j;
            
            [FX, FY] = add_spring_force_between_segments(FX, FY, X_S, Y_S, seg_a, seg_b, k_f, filament_separation);
        end
    end
end

% Basal coupling
if basal_coupling
    [FX, FY] = add_spring_force_between_segments(FX, FY, X_S, Y_S, 1, N_w + 1, k_b, filament_separation);
end
   
% External pinch
if external_pinch
    [FX, FY] = add_spring_force_between_segments(FX, FY, X_S, Y_S, seg_a, seg_b, k_e, filament_separation);
end