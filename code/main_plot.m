function main_plot(p)
%   Supplementary code to 'Methods for suspensions of passive and
%   active filaments', https://arxiv.org/abs/1903.12609 ,
%   by SF Schoeller, AK Townsend, TA Westwood & EE Keaveny.
%
%   It uses the 'EJBb' version of Broyden's method (Algorithm 2 in the
%   paper) with a reduced 'robot arm' system of nonlinear equations.
%
%   To use, just run main().


% Setup
[save_to_file, graphics, video, plot_step, save_step, plot_centreline, plot_walls, plot_initial, wdth_centreline, wdth_wall, plot_links, wdth_links, plot_links_psv, save_plot_to_file] = set_up_graphics();

N_input = 51;

% filament and fluids data
[a, N_sw, N_w, Np, N_lam, B, weight_per_unit_length, DL, L, mu, KB, KBdivDL, N_pairs, tethered, gravity, base_case] = data(N_input);

% iteration process data
[max_broyden_steps, steps_per_unit_time, num_settling_times, concheck_tol] = parameters(Np);

% filename
%filename = strcat(datestr(now, 'yyyymmdd-HHMMSS'), '.txt');     
filename = strcat('tail_amp=', num2str(p), '.txt');

% Set up segment position vectors.
%   X_S is x^(j+1), i.e. at next timestep (which we are solving for)
%   X   is x^(j),   i.e. at current timestep
%   X_T is x^(j-1), i.e. at previous timestep

X = zeros(Np,1);         % x-coordinate at current timestep
Y = zeros(Np,1);         % y-coordinate
THETA = zeros(Np,1);     % rotation
TX = cos(THETA);         % tangent vector \hat{t}_x
TY = sin(THETA);         % tangent vector \hat{t}_y

X_T = zeros(Np,1);       % previous timestep
Y_T = zeros(Np,1);
THETA_T = zeros(Np,1);

X_S = zeros(Np,1);       % next timestep
Y_S = zeros(Np,1);
THETA_S = zeros(Np,1);

% Arrays storing which filament each segment belongs to
SW_IND = reshape([1:Np],N_w,N_sw)';

% Distances between segments (all separations set to DL)
DL_SW = ones(N_sw, N_w - 1)*DL;

% Which filament does segment belong to?
% PtoS(n) returns the index of the filament that segment n belongs to.
PtoS = zeros(Np, 1);
PtoS = floor([0:Np-1]./N_w)+1;

% Set up position and orientation of first segment in every filament
% (We are happy with the default positon of [X,Y]=[0,0] and default
%  orientation of THETA=0 but you can change this here.)
filament_separation = 5;
[X, Y, THETA] = initial_positions(X, Y, THETA, N_w, N_sw, filament_separation, N_pairs, L);

% Having placed the first segment of each filament and set their
% orientation, use robot_arm to construct the position of the remaining
% segments. For more, type 'help robot_arm'.
[X,Y] = robot_arm(X,Y,THETA,SW_IND,DL);

% Zero the velocities and angular velocities of the segments
VX = zeros(Np,1);        % velocity of segment in x-direction
VY = zeros(Np,1);        % velocity of segment in y-direction
OMEGZ = zeros(Np,1);     % angular velocity of segment (in z-direction)

% Zero the forces and torques on the segments
FX = zeros(Np,1);        % force on each segment in x-direction
FY = zeros(Np,1);        % force on each segment in y-direction
TAUZ = zeros(Np,1);      % torque on each segment (in z-direction)

% Tensions from Han-Peskin on segments
T = zeros(Np, 1);
T_S = T;

% Steric force setup.
% For explanation, type 'help collision_barrier'.
map = [1 1 1 1]';
list = [0:Np-1]';
head = Np;
Lx_collision = 1000;
Ly_collision = 1000;

% Initial guesses
X_T = X;
Y_T = Y;
THETA_T = THETA;
X_S = X;
Y_S = Y;
LAMBDA1 = zeros(N_lam,1);
LAMBDA2 = zeros(N_lam,1);
LAMBDA1_0 = zeros(N_lam,1);
LAMBDA2_0 = zeros(N_lam,1);

% Segment size-related stuff
drag_coeff = (6*pi*a);
vis_tor_coeff = 8*pi*a^3;
RAD = a*ones(Np,1);         % Segment size vector (a = filament thickness)

% Newton step Delta X where at iteration k, X_(k+1) = X_k + Delta X
DeltaX = zeros(3*Np,1);

% Time
unit_time = L*mu/weight_per_unit_length;   % 1 settling time, T
TOTAL_STEPS = num_settling_times*steps_per_unit_time;
dt = unit_time/steps_per_unit_time;
t = 0;
plot_now = plot_step - 1;
save_now = save_step - 1;

% Time and iteration counts
frame_time = zeros(TOTAL_STEPS,1);
iters = zeros(TOTAL_STEPS,1);       % Number of Broyden's iterations
running_total_count = 0;            % For average number of Broyden's iters

if video
    Filament_movie = VideoWriter(['video.avi']); % Name it.
    Filament_movie.FrameRate = 10;  % How many frames per second.
    open(Filament_movie);
    framecount = 1;
end

idx = reshape(reshape([1:3*Np],Np,3)',3*Np,1);   % For filament indexing

J0invERROR_VECk = zeros(3*Np,1);   % J_0^{-1} f(X_k)      in Algorithm 2
J0invERROR_VECk1 = zeros(3*Np,1);  % J_0^{-1} f(X_(k+1))  in Algorithm 2

% Step in time

for nt = 1:TOTAL_STEPS
    iter = 0;

    p_broy = max_broyden_steps + 1;
    Cmat = zeros(3*Np,p_broy); % c and d vectors from Alg 2, Line 7. Their
    Dmat = zeros(3*Np,p_broy); % value at each iteration is stored.

    % Stop if broken
    if isnan(X(1))
        keyboard
        continue
    end

    % Screen output
    fprintf('\n')
    if mod(nt,20) == 0 && false
        fprintf(['[' filename ': rEJBb, B=' num2str(B) ', RPY, Nsw=' ...
                 num2str(N_sw) ', Nw=' num2str(N_w) ']\n' ])
    end
    length_of_TOTAL_STEPS = max(ceil(log10(abs(TOTAL_STEPS))),1);
    fprintf([ 'B=' num2str(B) '   ' ...
              'timestep: ' ...
              sprintf(['%' num2str(length_of_TOTAL_STEPS) '.f'],nt) ...
              '/' num2str(TOTAL_STEPS) ' ' ])
    frame_start = tic;

    % X_S is x^(j+1)
    % X   is x^(j)
    % X_T is x^(j-1)

    % Aim of this is to update X_S
    if(nt == 1)
        X_S = X;
        Y_S = Y;
        THETA_S = THETA;
        TX_S = cos(THETA_S);
        TY_S = sin(THETA_S);
        
        % Initialise lagrange multiplier for tethering
        gam = zeros(2,1);
    else
        % Rearranged linear interpolation as guess for x^(j+1), i.e.
        % x^j = 0.5*( x^(j-1) + x^(j+1) )
        THETA_S = 2.0*THETA - THETA_T;
        TX_S = cos(THETA_S);
        TY_S = sin(THETA_S);
        for j_sw = 1:N_sw
            first_bead = SW_IND(j_sw,1);
            X_S(first_bead) = 2*X(first_bead) - X_T(first_bead);
            Y_S(first_bead) = 2*Y(first_bead) - Y_T(first_bead);
        end
        % Having guessed first segment in filament, use robot_arm to
        % guess rest
        [X_S,Y_S] = robot_arm(X_S,Y_S,THETA_S,SW_IND,DL);

    end

    % Find f(X_k) and place into ERROR_VECk.
    % If ||ERROR_VECk|| < concheck_tol (= epsilon in Alg 2, Line 4),
    % then concheck = 0. Else, 1.
    [concheck,ERROR_VECk,VY] = F(X_S,Y_S,TX_S,TY_S,THETA_S, LAMBDA1,LAMBDA2,concheck_tol, gam, nt, TOTAL_STEPS, dt, L);
    % (VY only being outputted here for calculating effective drag later.)

    % Find approximate Jacobian J_0
    J0 = approximate_jacobian(THETA, LAMBDA1, LAMBDA2, ...
                              drag_coeff, vis_tor_coeff, dt, ...
                              DL, KBdivDL, SW_IND, mu, a);

    % Find J_0^{-1} f(X_k)  (from Alg 2, Line 5)
    J0invERROR_VECk(idx,:) = blockwise_backslash(J0, ...
                                                 ERROR_VECk(idx,:),SW_IND);
    
    num_broydens_steps_required = 0;   
    
    while(concheck == 1) % Alg 2, Line 4
        % Alg 2, Line 5. DeltaX is Delta X in paper.
        DeltaX = -apply_inverse_jacobian(J0invERROR_VECk, Cmat, Dmat, ...
                                                       ERROR_VECk, iter+1);
       
        % Update the positions and lambdas
        THETA_S = THETA_S + DeltaX(2*Np + 1:3*Np);
        TX_S = cos(THETA_S);
        TY_S = sin(THETA_S);
        
        % Update information for first segment
        if tethered
            % Update lagrange multiplier for tethering
            gam(1) = gam(1) + DeltaX(1);
            gam(2) = gam(2) + DeltaX(Np + 1);
        else 
            % Update position of first beads
            for j_sw = 1:N_sw
                first_bead = SW_IND(j_sw,1);
                X_S(first_bead) = X_S(first_bead) + DeltaX(first_bead);
                Y_S(first_bead) = Y_S(first_bead) + DeltaX(Np + first_bead);
            end
        end
        
        [X_S,Y_S] = robot_arm(X_S,Y_S,THETA_S,SW_IND,DL);
        lambda_locations = 1:2*Np;
        lambda_locations([1:N_w:end]) = [];
        DeltaX_lambdas = DeltaX(lambda_locations);
        LAMBDA1 = LAMBDA1 + DeltaX_lambdas(1:Np-N_sw);
        LAMBDA2 = LAMBDA2 + DeltaX_lambdas(Np-N_sw+1:2*Np-2*N_sw);

        % Check to see if the new state is an acceptable solution:
        % ERROR_VECk1 = f(X_(k+1))
        [concheck, ERROR_VECk1,VY] = F(X_S,Y_S,TX_S,TY_S,THETA_S, ...
                                             LAMBDA1,LAMBDA2,concheck_tol, gam, nt, TOTAL_STEPS, dt);

        iter = iter + 1;

        % (remaining lines are Alg 2, Line 7)
        y_vec = ERROR_VECk1 - ERROR_VECk;

        J0invERROR_VECk1(idx,:) = blockwise_backslash(J0, ...
                                                ERROR_VECk1(idx,:),SW_IND);

        y_vec_sq = y_vec'*y_vec;
        Cmat(:,iter) = -apply_inverse_jacobian(J0invERROR_VECk1, ...
                                            Cmat, Dmat, ERROR_VECk1, iter);
        Dmat(:,iter) = y_vec/y_vec_sq;
        ERROR_VECk = ERROR_VECk1;
        J0invERROR_VECk = J0invERROR_VECk1;
        
        % Shout if the iteration count has got a bit high
        if iter == 100
            keyboard
            continue
        end

        % If the number of iterations maxes out, proceed to next timestep
        % anyway and see what happens (but flag it with a *)
        if (iter > max_broyden_steps)
            fprintf(' *');
            concheck = 0;
        end

        num_broydens_steps_required = num_broydens_steps_required + 1;
        running_total_count = running_total_count + 1;
    end

    % Step in time
    t = t + dt;
    X_T = X;
    Y_T = Y;
    THETA_T = THETA;
    X = X_S;
    Y = Y_S;
    
    THETA = THETA_S;
    TX = cos(THETA);
    TY = sin(THETA);

    % At later time steps, you can use a higher order approximation
    % for the initial guess of the Lagrange multipliers, while storing
    % the required past ones.
    if(nt > 10)
        if(nt == 11)
            LAMBDA1_0 = LAMBDA1;
            LAMBDA2_0 = LAMBDA2;
        elseif(nt == 12)
            LAMBDA1_T = 2.0*LAMBDA1 - LAMBDA1_0;
            LAMBDA2_T = 2.0*LAMBDA2 - LAMBDA2_0;

            LAMBDA1_m1 = LAMBDA1_0;
            LAMBDA2_m1 = LAMBDA2_0;

            LAMBDA1_0 = LAMBDA1;
            LAMBDA2_0 = LAMBDA2;

            LAMBDA1 = LAMBDA1_T;
            LAMBDA2 = LAMBDA2_T;
        else
            LAMBDA1_T = 3.0*LAMBDA1 - 3.0*LAMBDA1_0 + LAMBDA1_m1;
            LAMBDA2_T = 3.0*LAMBDA2 - 3.0*LAMBDA2_0 + LAMBDA2_m1;

            LAMBDA1_m1 = LAMBDA1_0;
            LAMBDA2_m1 = LAMBDA2_0;

            LAMBDA1_0 = LAMBDA1;
            LAMBDA2_0 = LAMBDA2;

            LAMBDA1 = LAMBDA1_T;
            LAMBDA2 = LAMBDA2_T;
        end
    end
    
    
    % ------------------ PLOTTING AND SAVING ----------------------

    % Plot and save
    plot_now = plot_now + 1;
    save_now = save_now + 1;
    
    % ---- SAVE TO FILE ----

    if(save_now == save_step && save_to_file)
        fid = fopen(filename, 'a');
        
        for j = 1:Np 
            if mod(j,N_w) ~= 0 % i.e. if not the last segment in filament
                filament_id = floor(j/N_w); %0 to N_sw-1
                L1 = LAMBDA1(j-filament_id);
                L2 = LAMBDA2(j-filament_id);
            else
                L1 = 0;
                L2 = 0;
            end
            
            % Print torques, etc. to file
            fprintf(fid, ['%.2f %.6f %.6f %.6f %.6f %.6f %.6f '...
                          '%.6f %.6f %.6f %.6f %.6f %.6f\n'], ...
                         t, X(j), Y(j), TX(j), TY(j), VX(j), VY(j), ...
                         OMEGZ(j), FX(j), FY(j), TAUZ(j), L1, L2);
            
            
        end
        fprintf(fid,'\n');
        fclose(fid);
        
        %clf;
    end
    

    % ---- PLOTTING ----
    
    if(plot_now == plot_step && graphics)
        
        com_X = mean(X_S);
        com_Y = mean(Y_S);
        
        
        if plot_links_psv
            for i_pairs=1:N_pairs
                for i=1:N_w
                    seg_c1 = (((2 * i_pairs) - 2) * N_w) + i;
                    seg_c2 = (((2 * i_pairs) - 1) * N_w) + i;
                    plot([X_S(seg_c1)/L X_S(seg_c2)/L], [Y_S(seg_c1)/L Y_S(seg_c2)/L], 'y-', 'LineWidth', wdth_links);
                    hold on;
                end
            end
        end
        
        
        if plot_links
            for i_pairs=1:N_pairs
                for i=1:(N_w - 1)
                    seg_a1 = (((2 * i_pairs) - 2) * N_w) + i;
                    seg_a2 = (((2 * i_pairs) - 2) * N_w) + N_w + 1 + i;
                    seg_b1 = (((2 * i_pairs) - 2) * N_w) + i + 1;
                    seg_b2 = (((2 * i_pairs) - 2) * N_w) + N_w + i;
                    plot([X_S(seg_a1)/L X_S(seg_a2)/L], [Y_S(seg_a1)/L Y_S(seg_a2)/L], 'r-', 'LineWidth', wdth_links);
                    plot([X_S(seg_b1)/L X_S(seg_b2)/L], [Y_S(seg_b1)/L Y_S(seg_b2)/L], 'b-', 'LineWidth', wdth_links);
                    hold on;
                end
            end
        end
        
        
        if plot_walls
            % for each filament do the following loop
            for i_sw = 1:N_sw
                % scaled by length of filament / nondimensionalising
                plot((X_S(SW_IND(i_sw,:)))/L, (Y_S(SW_IND(i_sw,:)))/L, ...
                    'k-', 'LineWidth', wdth_wall);

                % added hold on to try and fix problem
                % this is done so that the axes isn't being cleared
                hold on;
            end
        end
        
        if plot_centreline
            for i_pairs = 1:N_pairs
                plot(((X_S(SW_IND((2*i_pairs) - 1, :)) + X_S(SW_IND(2*i_pairs, :))) / (2 * L)), ((Y_S(SW_IND((2*i_pairs) - 1, :)) + Y_S(SW_IND(2*i_pairs, :))) / (2 * L)), ...
                            'm:', 'LineWidth', wdth_centreline);
                hold on;
            end
        end
               
        set(gcf,'defaulttextinterpreter','latex');
        

        % Calculate quantifiers for the filament
        %A_over_L = (max(Y_S) - min(Y_S))/L;
        %body_velocity_Y = mean(VY);
        %eff_drag_coeff = -weight_per_unit_length*L/body_velocity_Y;
        
        %title(['nt='  num2str(nt)  ', dt='  num2str(dt) ...
        %       ', B='  num2str(B)  ', N_{sw}='  num2str(N_sw) ...
        %       ', A/L=' num2str(A_over_L) ...
        %       ', \gamma=' num2str(eff_drag_coeff) ''])
        
        
        %title(['Filament bending using cross-linked forces. nt=' num2str(nt)''])

        hold off
        
        % Aspect ratios
        pbaspect([1 1 1])
        limit = 0.5; % originally 0.5, 1.2 for multiple swimmers
        xlim([com_X/L - limit, com_X/L + limit]);
        ylim([com_Y/L - limit, com_Y/L + limit]);
        
        % Labelling
        xlabel('$x / L$');
        ylabel('$y / L$');
        axis equal
        
        % Video recording
        if video == true
            frame = getframe(gcf);
            writeVideo(Filament_movie,frame);
            framecount=framecount+1;
        end
                
        if save_plot_to_file
            axis off
            saveas(gcf, strcat('frame_', num2str(nt)), 'png')
            axis on
        end
        
        % Pause on first step
        if nt == 1 && plot_initial
            pause
        end
        
        pause(0.01);
    end
    
    % Plot
    if plot_now == plot_step
        plot_now = 0;
    end
    if save_now == save_step
        save_now = 0;
    end
    
    % Iteration tracking
    frame_time(nt) = toc(frame_start);
    iters(nt) = iter;

    % Print data to file
    fprintf(['[' format_time(frame_time(nt)) '|' ...
            format_time(mean(frame_time(1:nt))*(TOTAL_STEPS-nt)) ...
            '-][#Broy steps: '  num2str(num_broydens_steps_required) ...
            '|Avg: '  num2str(round(running_total_count/nt))  ']'])

end

% Final printed info
disp('')
disp('Run finished')
disp(['Total time:' format_time(sum(frame_time))])

% Close video
if video
    close(Filament_movie);
end






% ---------------------------------

% Forces
function [concheck_local,ERROR_VECk1_local,VY] = F(X_S, Y_S, TX_S, TY_S,...
                                                   THETA_S, LAMBDA1,...
                                                   LAMBDA2, tol, gam, nt, TOTAL_STEPS, dt, Lf)
                                               
% F  places forces and torques on the segments, calculates the resultant
%    velocities and angular velocities, and forms the error vector f(X*).
%    Then checks convergence. For details, see docstrings of functions
%    within.

    % Initialisation
    FX = zeros(Np,1);
    FY = zeros(Np,1);
    TAUZ = zeros(Np,1);
    
    if gravity
        FY = -weight_per_unit_length*L/N_w*ones(Np,1);
    end
    
    if base_case
        % Forces for finding base case, hydrodynamic efficiency
        f_epsilon = 0.5;
        FY(1) = FY(1) - f_epsilon;
        FY(N_w + 1) = FY(N_w + 1) - f_epsilon;
    end
    
    % Cross-Links, Passive Links
    [FX, FY] = all_external_forces(FX, FY, X_S, Y_S, N_w, DL, filament_separation, N_pairs, nt, steps_per_unit_time, dt, T_S, L, p);
      
    % Elastic forces
    [TAUZ] = elastic_torques(TAUZ, TX_S, TY_S, KB, SW_IND, DL_SW);

    % Collision barrier forces
    % - stop them colliding, prevents overlapping because the physics is
    %   completely different, applies a small repelling force between segments when
    %   they get really close to eachother
    [FX, FY] = collision_barrier(X_S, Y_S, FX, FY, ...
                                 Lx_collision, Ly_collision, PtoS, ...
                                 map, head, list, RAD);

    % Constraint forces
    % - No stretching
    [FX, FY, TAUZ] = constraint_forces_torques(FX, FY, TAUZ, TX_S, TY_S,...
                                         LAMBDA1, LAMBDA2, SW_IND, DL_SW);
    
    % Tethering
    if tethered
        for j_sw = 1:N_sw
           first_bead = SW_IND(j_sw,1);
           FX(first_bead) = FX(first_bead) + gam(1);
           FY(first_bead) = FY(first_bead) + gam(2);
        end
    end    
    
    % ---------
                                        
    FZ = zeros(Np,1);
    TAUX = zeros(Np,1);
    TAUY = zeros(Np,1);
    Z_S = zeros(Np,1);
    [VX,VY,~,~,~,OMEGZ] = RPY(FX,FY,FZ,TAUX,TAUY,TAUZ,X_S,Y_S,Z_S,a,1);


    % Check convergence between x_(n+1) and x_n, and also check the
    % constraint. concheck = 0 if all fine, 1 otherwise. The error vectors
    % are all compiled into ERROR_VECk1_local.
    [concheck_local, ERROR_VECk1_local] = constraint_check_robot_arm(...
                                              X_S, Y_S, THETA_S, ...
                                              X, Y, THETA, ...
                                              X_T, Y_T, THETA_T, ...
                                              VX, VY, OMEGZ, ...
                                              DL, dt, nt, SW_IND, tol);
end

end