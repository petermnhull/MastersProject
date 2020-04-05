function [X, Y, THETA] = initial_positions(X_IN, Y_IN, THETA_IN, N_w, N_sw, filament_separation, N_pairs, L)

% --- INITIAL POSITIONING ---

% X positions of left filament of each pair
% x_left = [0, -10, -L/8, -L/1.5, -L/3];
% y_left = [5, 5, -L/7, -L/2, -10];
x_right = zeros(N_pairs);
y_right = zeros(N_pairs);

% Angles
displacement_theta = pi/2;
% alpha = [pi - 0.05, pi/2 + 0.01, 3*pi/4, 3*pi/5, 3*pi/5.5];

% SINGLE EXAMPLE
x_left = [0];
y_left = [0];
alpha = [0];
% ---------------------------


X = X_IN;
Y = Y_IN;
THETA = THETA_IN;

for i_pairs=1:N_pairs
    for i=1:N_w
        seg_a = (((2 * i_pairs) - 2) * N_w) + i;
        seg_b = (((2 * i_pairs) - 2) * N_w) + N_w + i;

        THETA(seg_a) = displacement_theta + alpha(i_pairs);
        THETA(seg_b) = displacement_theta + alpha(i_pairs);
    end
end

for i_pairs=1:N_pairs
    seg_a = (((2 * i_pairs) - 2) * N_w) + 1;
    seg_b = (((2 * i_pairs) - 2) * N_w) + N_w + 1;
    
    x_right(i_pairs) = x_left(i_pairs) + (filament_separation * cos(alpha(i_pairs)));
    y_right(i_pairs) = y_left(i_pairs) + (filament_separation * sin(alpha(i_pairs)));
    
    X(seg_a) = x_left(i_pairs);
    X(seg_b) = x_right(i_pairs);
    Y(seg_a) = y_left(i_pairs);
    Y(seg_b) = y_right(i_pairs);
end