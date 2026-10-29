# Instantiation: observation, action, reward, and sim context {#sec-spaces}

This appendix instantiates the shared spaces of the POMDP of §\ref{sec-problem}. The motion-tracking interface follows the BeyondMimic formulation [@liao2025beyondmimic]; the changes we make are noted inline.

#### Observation.

The proprioceptive observation $\bm{o}_t$ comprises the joint positions relative to the default pose $\bm{q} - \bm{q}^0$, the joint velocities $\dot{\bm{q}}$, the base angular velocity from the inertial measurement unit (IMU), the projected gravity in the base frame, and the previous action $\bm{a}_{t-1}$ (Table \ref{tab-obs-supermimic}); the policy receives the last 10 observations.

```{=latex}
\begin{table}[!htbp]
\centering
\footnotesize
\setlength{\tabcolsep}{3pt}
\begin{tabular}{@{}llll@{}}
\toprule
\textbf{Observation Term} & \textbf{Dim.} & \textbf{Noise $\bm{\eta}_t$} & \textbf{Unit} \\
\midrule
Joint positions $\bm{q} - \bm{q}^0$ & 29 & $\mathcal{U}[-0.01,\,0.01]$ & \unit{\radian} \\
Joint velocities $\dot{\bm{q}}$ & 29 & $\mathcal{U}[-0.5,\,0.5]$ & \unit{\radian\per\second} \\
Base angular velocity (IMU) & 3 & $\mathcal{U}[-0.2,\,0.2]$ & \unit{\radian\per\second} \\
Projected gravity & 3 & $\mathcal{U}[-0.05,\,0.05]$ & -- \\
Previous action $\bm{a}_{t-1}$ & 29 & -- & -- \\
\bottomrule
\end{tabular}
\vspace{0.6em}
\caption{\textbf{Proprioceptive observation $\bm{o}_t$.} The noise column gives the per-dimension sensor noise $\bm{\eta}_t \sim \rho_\eta$.}
\label{tab-obs-supermimic}
\end{table}
```

#### Goal.

For the motion-tracking interface, the goal $\bm{g}_t$ is read from the reference motion. Compared with BeyondMimic [@liao2025beyondmimic], we condition the encoder on a $K=10$ future reference sequence rather than a single-frame target. Other goal interfaces replace $\bm{g}_t$ with their corresponding command representation, such as target velocity commands (Appendix \ref{sec-unified}).

#### Action.

The action $\bm{a}_t$ maps to a joint setpoint $\bm{q}^{\text{sp}} = \bm{\alpha}\,\bm{a}_t + \bm{q}^0$ about the default pose $\bm{q}^0$. Following BeyondMimic, the low PD gains make this setpoint a proxy for joint torque rather than a desired position.

#### Reward.

We use BeyondMimic's motion-tracking reward (Table \ref{tab-reward-supermimic}), removing its self-collision penalty. That penalty guards against reward hacking by a stochastic policy. When the reference brings two bodies close without contact, pressing them together suppresses the action noise and raises the velocity-tracking reward. Our policy is deterministic in imagined rollouts (§\ref{sec-policy}), so the exploit has no payoff and the term is unnecessary. The joint-limit penalty is lowered from $-10$ to $-2$.

#### Termination.

An episode terminates when the root body deviates from the reference beyond a height or tilt threshold ($|\bm{e}_{p,z}| > 0.25\,\mathrm{m}$ or $e_{\mathrm{tilt}} > 0.8$). The tilt error $e_{\mathrm{tilt}}$ is the absolute difference between the $z$-components of the gravity direction expressed in the reference and robot root (pelvis) frames. For an upright reference, $e_{\mathrm{tilt}}$ reaches 0.8 at about $78^\circ$ of tilt. Unlike BeyondMimic, we do not terminate on end-effector deviation.

#### Sim context and domain randomization.

The per-episode sim context $\bm{\xi}$ collects the domain-randomization parameters fed to the world model (§\ref{sec-wm}); Table \ref{tab-domain-rand-supermimic} lists them. We omit BeyondMimic's root-velocity perturbations: such pushes inject state discontinuities that the deterministic world model cannot capture, and we find randomization over the physical parameters alone suffices for transfer to hardware.

```{=latex}
\begin{table}[t]
\centering
\begin{tabular}{llc}
\toprule
\textbf{Reward Term} & \textbf{Equation} & \textbf{Weight} \\
\midrule
\multicolumn{3}{l}{\emph{Task (tracking)}}\\
Body Position
& $\displaystyle
\exp\!\Big(
-\big( \tfrac{1}{|\mathcal{T}|}
\sum_{b\in\mathcal{T}}
\|\mathbf{p}^{\mathrm{des}}_{b}-\mathbf{p}_{b}\|^{2} \big) / 0.3^{2}
\Big)$
& $1.0$\\[2mm]
Body Orientation
& $\displaystyle
\exp\!\Big(
-\big( \tfrac{1}{|\mathcal{T}|}
\sum_{b\in\mathcal{T}}
\|\log(R^{\mathrm{des}}_{b}R_{b}^{\top})\|^{2} \big) / 0.4^{2}
\Big)$
& $1.0$\\[2mm]
Body Linear velocity
& $\displaystyle
\exp\!\Big(
-\big( \tfrac{1}{|\mathcal{T}|}
\sum_{b\in\mathcal{T}}
\|\mathbf{v}^{\mathrm{des}}_{b}-\mathbf{v}_{b}\|^{2} \big) / 1.0^{2}
\Big)$
& $1.0$\\[2mm]
Body Angular velocity
& $\displaystyle
\exp\!\Big(
-\big( \tfrac{1}{|\mathcal{T}|}
\sum_{b\in\mathcal{T}}
\|\boldsymbol{\omega}^{\mathrm{des}}_{b}-\boldsymbol{\omega}_{b}\|^{2} \big) / 3.14^{2}
\Big)$
& $1.0$\\[2mm]
Root Position
& $\displaystyle
\exp\!\Big(
-\|\mathbf{p}^{\mathrm{des}}_{\text{root}}-\mathbf{p}_{\text{root}}\|^{2} / 0.3^{2}
\Big)$
& $0.5$\\[2mm]
Root Orientation
& $\displaystyle
\exp\!\Big(
-\|\log(R^{\mathrm{des}}_{\text{root}}R_{\text{root}}^{\top})\|^{2} / 0.4^{2}
\Big)$
& $0.5$\\[2mm]
\midrule
\multicolumn{3}{l}{\emph{Regularization}}\\
Action smoothness
& $\|\mathbf{a}_{t}-\mathbf{a}_{t-1}\|^{2}$
& $-0.1$\\[2mm]
Joint limit
& $\sum_{j}\big[\max(0,\,q_{j}-q_{j}^{\max}) + \max(0,\,q_{j}^{\min}-q_{j})\big]$
& $-2$\\
\bottomrule
\end{tabular}
\vspace{0.6em}
\caption{\textbf{Motion-tracking interface reward, following BeyondMimic~\citep{liao2025beyondmimic} with the self-collision penalty removed and the joint-limit weight lowered from $-10$ to $-2$ (\S\ref{sec-policy}).} $\mathcal{T}$ is the set of tracked bodies.}
\label{tab-reward-supermimic}
\end{table}
```

```{=latex}
\begin{table}[t]
\centering
\begin{tabular}{ll}
\toprule
\textbf{Domain Randomization} & \textbf{Sampling Distribution} \\
\midrule
Friction coefficients & $\mu \sim \mathcal{U}[0.3,\,1.2]$ \\
Joint calibration offsets [rad] & $ \Delta q^0_j \!\sim  \mathcal{U}[-0.01,\,0.01] $\\
Torso's center-of-mass offset [m]& $\Delta x\!\sim\!\mathcal{U}[-0.025,0.025]$,  $\ \Delta y\!\sim\!\mathcal{U}[-0.05,0.05]$, \\ &$ \Delta z\!\sim\!\mathcal{U}[-0.05,0.05]$ \\
\bottomrule
\end{tabular}
\vspace{0.6em}
\caption{\textbf{Domain-randomization parameters that make up the sim context $\bm{\xi}$, following BeyondMimic~\citep{liao2025beyondmimic} with the root-velocity perturbations removed.} ($\mathcal{U}[\cdot]$: uniform distribution.)}
\label{tab-domain-rand-supermimic}
\end{table}
```

# Joint training across goal interfaces {#sec-unified}

In §\ref{sec-method}, the goal $\bm{g}_t$ is read from a full reference motion. Downstream goal interfaces specify the motion only in part or in another form. The same dynamics model can train several goal interfaces because the body physics is shared. We instantiate one POMDP $\mathcal{M}_i$ per goal interface (for example, a full-reference motion target, a velocity command, end-effector poses, or an SMPL body-pose target), each with its own goal space $\mathcal{G}_i$, reward $r_i$, and termination $d_i$, and train each with its own critic $V_{\psi_i}$. A single policy network uses per-interface goal encoders $\mathrm{enc}_{\theta,i}$ and a shared decoder $\mathrm{dec}_\theta$,

$$
\bm{z} = \mathrm{enc}_{\theta,i}(\bm{g}) \in \mathcal{Z}, \qquad \bm{a} = \mathrm{dec}_\theta(\bm{z}, \bm{o}), \qquad \bm{g} \in \mathcal{G}_i,
$$ {#eq-supermimic-4}

and training optimizes the lifted objective $\max_\theta \mathbb{E}_{i\sim p(\mathcal{I})}[\hat{J}_i(\theta)]$, where $p(\mathcal{I})$ is a distribution over the set $\mathcal{I}$ of goal interfaces. Each interface $i$ thus has its own policy $\bm{a} = \pi_i(\bm{o}, \bm{g}) := \mathrm{dec}_\theta(\mathrm{enc}_{\theta,i}(\bm{g}), \bm{o})$; the velocity encoder also receives a feature of the observation history (Table \ref{tab-policy-nets}). Each $\hat{J}_i$ is the objective of Eq. \ref{eq-policy-obj} with $\pi_i$ in place of $\pi_\theta$, the reward and termination of $\mathcal{M}_i$, and the critic $V_{\psi_i}$. Every interface trains through the same dynamics model $f_\omega$, which is not retrained per interface.

A downstream interface is trained by distillation or by RL, depending on its reward. Distillation uses the motion-tracking reward (§\ref{sec-policy}), with the command read from the reference motion. The reward gradient then trains that interface to reproduce the reference motion from this command. RL optimizes the interface's own task reward, such as velocity tracking, directly through the world model. On a downstream interface's rollouts, the return gradient passes through the shared decoder to that interface's encoder, with a stop-gradient on the decoder's weights; the decoder is still trained by the motion-tracking objective. The RL-trained velocity encoder of §\ref{sec-downstream} also has a latent-alignment loss toward the motion encoder's latent on rollouts with reference commands (Appendix \ref{sec-velocity}).

# Network architectures

Table \ref{tab-policy-nets} lists the world-model dynamics network of §\ref{sec-wm} and the policy and critic networks of Appendix \ref{sec-unified}.

```{=latex}
\begin{table}[t]
\centering
\footnotesize
\setlength{\tabcolsep}{3pt}
\begin{tabular}{@{}>{\raggedright\arraybackslash}p{0.24\linewidth}>{\raggedright\arraybackslash}p{0.28\linewidth}>{\raggedright\arraybackslash}p{0.08\linewidth}>{\raggedright\arraybackslash}p{0.32\linewidth}@{}}
\toprule
\textbf{Network} & \textbf{Input} & \textbf{Output} & \textbf{Architecture} \\
\midrule
Dynamics $f_\omega$ & $\hat{\bm{s}}_t,\ \bm{a}_t,\ \bm{\xi}$ & $\hat{\bm{s}}_{t+1}$ & MLP (2048, 2048, 2048) \\
\midrule
Motion encoder $\mathrm{enc}_{\theta,\text{motion}}$ & $K{=}10$ future reference frames & $\bm{z}$ & MLP (2048, 1024, 512, 256) \\
Velocity encoder $\mathrm{enc}_{\theta,\text{vel}}$ (Appendix~\ref{sec-velocity}) & normalized command $(v_x, v_y, \omega_z)$, feature of the last 10 frames of $\bm{o}$ & $\bm{z}$ & MLP (256, 256) \\
Shared decoder $\mathrm{dec}_\theta$ & $\bm{z}$, last 10 frames of $\bm{o}$ & $\bm{a}_t$ & MLP (2048, 1024, 512, 256) \\
Critic $V_{\psi_i}$ & $\hat{\bm{s}}_t,\ \bm{g}_t,\ \bm{\xi}$ & scalar & MLP (256, 128); one critic per interface \\
\bottomrule
\end{tabular}
\vspace{0.6em}
\caption{\textbf{World-model, policy, and critic networks.} MLP: multilayer perceptron, listed by hidden widths. The latent $\bm{z}$ is 32-dimensional and bounded by $\tanh$.}
\label{tab-policy-nets}
\end{table}
```

# Training loop and hyperparameters {#sec-algorithm}

## Algorithm

Algorithm \ref{alg-train} summarizes the SuperMimic training loop of §\ref{sec-problem}; its three steps correspond one-to-one to the panels of Figure \ref{fig-pipeline}.

```{=latex}
\begin{algorithm}[t]
\caption{\textbf{SuperMimic training.} Both $\omega$ and $\theta$ update every iteration; $\omega$ is held fixed (stop-gradient) only inside the policy's backward pass. For a downstream interface, $\hat{J}_i$ updates only its encoder $\mathrm{enc}_{\theta,i}$.}
\label{alg-train}
\begin{algorithmic}[1]\small
\Require world model $f_\omega$; policy $\pi_\theta$ shared across interfaces $\{\mathcal{M}_i\}_{i\in\mathcal{I}}$; replay buffer $\mathcal{B}$
\For{each iteration}
    \State \(\triangleright\)~\textbf{Collect.}\ \ Roll out $\pi_\theta$ with action noise in simulation; push transitions to $\mathcal{B}$, replacing the oldest
    \State \quad Draw reset start points by return-based sampling \Comment{Appendix~\ref{sec-reset}}
    \State \(\triangleright\)~\textbf{Fit world model.}\ \ Sample a logged $k$-step window from $\mathcal{B}$, roll $f_\omega$ out autoregressively on the logged actions, and step $\omega \gets \omega - \alpha_\omega \nabla_\omega \mathcal{L}_{\text{WM}}$ \Comment{Eq.~\ref{eq-wm-loss}}
    \State \(\triangleright\)~\textbf{Improve policy.}\ \ Sample an interface $i \sim p(\mathcal{I})$ and a start state from $\mathcal{B}$
    \State \quad Imagine $H$ steps on-policy through the fixed $f_\omega$:\ \ $\hat{\bm{s}}_{t+1} = f_\omega\big(\hat{\bm{s}}_t,\, \pi_i(\hat{\bar{\bm{o}}}_t+\bm{\eta}_t, \bm{g}_t),\, \bm{\xi}\big)$
    \State \quad Step $\theta \gets \theta + \alpha_\theta \nabla_\theta \hat{J}_i$ \Comment{Eq.~\ref{eq-policy-obj}; analytic gradients through $f_\omega$; critic $V_{\psi_i}$}
    \State \quad Fit the critic $V_{\psi_i}$ to the GAE targets of the imagined rollout \Comment{Eq.~\ref{eq-critic}}
\EndFor
\end{algorithmic}
\end{algorithm}
```

#### Return-based reset sampling. {#sec-reset}

Simulator episodes reset to points of the motion library, favoring those where the policy currently earns low return. The motion timeline is divided into 1 s bins, and each bin $b$ keeps a running estimate $G_b$ of the discounted return from it, updated on the policy's own rollouts. Resets mix three distributions: 50% uniform over bins, 40% from $\mathrm{softmax}_b(-25\,G_b/G_{\max})$, where $G_{\max}$ is the largest attainable discounted return, and 10% in proportion to each bin's past softmax weight, so a hard motion keeps some practice after it is learned.

## Hyperparameters

Table \ref{tab-hyperparams} lists the hyperparameters. Where they differ, values are given for the one-GPU and the two-GPU run of Table \ref{tab-failed-motion-stats}.

```{=latex}
\begin{table}[!tbp]
\small
\centering
\begin{tabular}{@{}ll>{\raggedright\arraybackslash}p{0.42\linewidth}@{}}
\toprule
\textbf{Hyperparameter} & \textbf{Symbol} & \textbf{Value} \\
\midrule
\multicolumn{3}{l}{\emph{World model}}\\
Window length & $k$ & 8 \\
Optimizer & & Adam \\
Learning rate & $\alpha_\omega$ & 1 GPU: $2\times10^{-4}$; 2 GPUs: $\sqrt{2}\times2\times10^{-4}$ \\
Batch size & & 10 batches of 2048 windows per update \\
Gradient clipping & & global norm 1.0 \\
\midrule
\multicolumn{3}{l}{\emph{Imagination and policy}}\\
Imagination horizon & $H$ & 32 \\
Optimizer & & Adam, $\beta = (0.9,\,0.95)$ \\
Learning rate & $\alpha_\theta$ & same as $\alpha_\omega$ \\
Batch size & & 4096 imagined rollouts per update \\
Gradient clipping & & global norm 1.0, then element-wise 0.1 \\
Discount & $\gamma$ & 0.99 \\
Sensor noise & $\bm{\eta}_t\sim\rho_\eta$ & Table~\ref{tab-obs-supermimic} \\
\midrule
\multicolumn{3}{l}{\emph{Critic}}\\
GAE parameter & $\lambda$ & 0.95 \\
Optimizer & & Adam \\
Learning rate & & same as $\alpha_\omega$ \\
Gradient clipping & & global norm 1.0 \\
Critic epochs per update & & 5, each over 4 shuffled minibatches \\
\midrule
\multicolumn{3}{l}{\emph{Data collection}}\\
Simulator environments per GPU & & \num{4096} \\
Action noise & $\bm{\epsilon}_t\sim\rho_\epsilon$ & $\mathcal{N}(0,\,0.1^2)$ per action dimension \\
Replay-buffer size & & 1000 steps per environment \\
\midrule
\multicolumn{3}{l}{\emph{Schedule}}\\
Update-to-data ratio & & 0.4 \\
Policy updates per world-model update & & 1 \\
Learning-rate schedule & & cosine decay to $0.03\times$ over \num{250000} iterations, then constant \\
Training length & & \num{320000} iterations \\
Multi-GPU & & data parallel; gradients averaged across GPUs \\
\bottomrule
\end{tabular}
\vspace{0.6em}
\caption{\textbf{SuperMimic hyperparameters.}}
\label{tab-hyperparams}

\end{table}
```

```{=latex}
\begin{table}[!tbp]
\vspace{1.2em}
\centering
\begin{tabular}{llc}
\toprule
\textbf{Reward Term} & \textbf{Equation} & \textbf{Weight} \\
\midrule
\multicolumn{3}{l}{\emph{Task (velocity tracking)}}\\
Linear velocity
& $\displaystyle \exp\!\Big( -\|\mathbf{v}_{xy}-\mathbf{v}^{\mathrm{cmd}}_{xy}\|^{2} / 0.5^{2} \Big)$
& $2.0$\\[1mm]
Yaw rate
& $\displaystyle \exp\!\Big( -(\omega_{z}-\omega^{\mathrm{cmd}}_{z})^{2} / 0.5 \Big)$
& $2.0$\\[1mm]
\midrule
\multicolumn{3}{l}{\emph{Regularization}}\\
Action smoothness
& $\|\mathbf{a}_{t}-\mathbf{a}_{t-1}\|^{2}$
& $-0.3$\\[1mm]
Joint limit
& $\sum_{j}\big[\max(0,\,q_{j}-q_{j}^{\max}) + \max(0,\,q_{j}^{\min}-q_{j})\big]$
& $-2$\\[1mm]
Torso sideways lean
& $\sin^{2}\phi_{\mathrm{torso}}$
& $-4$\\[1mm]
Torso roll and pitch rate
& $\omega_{\mathrm{roll}}^{2}+\omega_{\mathrm{pitch}}^{2}$
& $-0.05$\\
\midrule
\multicolumn{3}{l}{\emph{Termination (fall)}}\\
\multicolumn{3}{l}{$h_{\mathrm{root}} < 0.35\,\mathrm{m}$ \;or\; $1 + u_{z} > 0.7$}\\
\bottomrule
\end{tabular}
\vspace{0.6em}
\caption{\textbf{Velocity-tracking reward and termination used to train the RL encoder.} $\mathbf{v}_{xy}$ is the planar root velocity in the heading frame, $\omega_z$ the world yaw rate, and $(\mathbf{v}^{\mathrm{cmd}}_{xy}, \omega^{\mathrm{cmd}}_{z})$ the command. $\phi_{\mathrm{torso}}$ is the sideways lean of the torso $z$-axis (forward lean is not penalized) and $\omega_{\mathrm{roll}}, \omega_{\mathrm{pitch}}$ the torso roll and pitch rates, all in the heading frame. $h_{\mathrm{root}}$ is the root height and $u_z$ the $z$-component of the unit gravity direction in the root frame, so $1+u_z$ is 0 upright and 2 upside down, and the tilt condition triggers at about $73^\circ$. Every term, here and in Table~\ref{tab-reward-supermimic}, is multiplied by the control period $\Delta t=0.02\,\mathrm{s}$.}
\label{tab-reward-velocity}
\end{table}
```

# Motion data filtering {#sec-data-filter}

We train on the publicly available G1-retargeted BONES-SEED motion set [@bones2026seed]. The raw release contains 142220 clips, but many interact with terrain or objects the robot cannot use (stairs, boxes, ladders, chairs) or carry retargeting artifacts that make them infeasible for a free-standing humanoid on flat ground. We remove these in two passes and keep 129514 clips (Table \ref{tab-data-filter}).

#### Name filter.

Each clip is named by its action. We drop any clip whose name contains a term denoting contact with terrain or an object the robot cannot use---e.g. `stair`, `ladder`, `box`, `chair`, `sit`, `climb`, `jump_off_50cm`, `look_over_fence`. This pass (adapted from the keyword list in SONIC's released data-processing code [@luo2025sonic], plus a few terms it misses) removes 12553 clips.

#### Feasibility filter.

The name filter misses clips whose names do not reveal the problem (e.g. a routine that walks onto a box). We run each motion through MuJoCo forward kinematics and flag it from the resulting body-link and foot-geometry trajectories, writing $z_{\min}(t)=\min_b z_b(t)$ for the height of the lowest body link at time $t$ with the floor at $z=0$:

- **Elevated support.** $z_{\min}$ holds above 0.20 m for at least 0.6 s (standing or climbing on a box).

- **Ground penetration.** $z_{\min}$ falls below −0.12 m, or below −0.08 m for over 80% of the clip (legs driven through the floor by a faulty retarget).

- **Floating feet.** For at least 0.5 s *both* feet stay more than 0.02 m above the floor---measured as MuJoCo's exact geom-to-plane distance (`mj_geomDistance`) from the foot collision geometry, not a link-origin proxy---while the pelvis is upright and at standing height and the body is nearly stationary. A free-standing humanoid cannot hold both feet off the floor while standing still, so this is infeasible on flat ground whatever the cause (a low platform, a retarget float, or a slow rise; a ballistic jump is excluded by the stationary gate). The clean ground stance sits at −0.004 ± 0.004 m, so the 0.02 m gate is several $\sigma$ clear of the floor.

This pass removes a further 153 clips. All thresholds are tuned for the G1 retarget at $50\,\mathrm{Hz}$.

```{=latex}
\begin{table}[t]
\centering
\begin{tabular}{lr}
\toprule
\textbf{Stage} & \textbf{Clips} \\
\midrule
Raw BONES-SEED (G1 retarget) & \num{142220} \\
After name filter & \num{129667} \\
After feasibility filter & \num{129514} \\
\bottomrule
\end{tabular}
\vspace{0.6em}
\caption{\textbf{Number of BONES-SEED clips before filtering and after each filter.}}
\label{tab-data-filter}
\end{table}
```

# Evaluation {#sec-eval}

## Benchmark metrics

We evaluate SONIC and SuperMimic on the same filtered BONES-SEED training-set benchmark, containing 129514 evaluated motions. For SONIC we evaluate its released checkpoint and its v1.1 checkpoint [@luo2025sonic]. Each motion plays once from its first frame, with the same simulation for every policy: foot friction 1.0, no domain randomization or observation noise, and deterministic physics. Each policy uses its own actuator gains and action scale, and receives its observations as its training environment builds them. A motion is marked as failed if the rollout triggers SuperMimic's training termination (Appendix \ref{sec-spaces}). SONIC's own success criterion fails a motion on root and end-effector height deviations above 0.25 m, without an orientation term [@luo2025sonic].

## Failed motions

Table \ref{tab-failed-motion-stats} counts failed motions per motion group. SONIC fails whole groups (all 44 flips, all 22 side rolls, and all 8 motions of one dance routine) and 15 of the 24 broad jumps. Its v1.1 checkpoint fails 239 motions, among them the same flips and dance motions and 19 of the 22 side rolls. After 3 h on one GPU, SuperMimic's failures concentrate in a few small groups of hard motions: the first five groups of Table \ref{tab-failed-motion-stats}, 195 motions, hold 14 of its 25 failures. In no group does it fail more motions than SONIC. After 9.8 h on two GPUs, SuperMimic fails on none. Figure \ref{fig-failed-motions} shows the count over training. The benchmark motions are training motions for both methods, so the counts measure how fully each policy covers these training motions, not generalization to new motions.

```{=latex}
\begin{table}[H]
\centering
\footnotesize
\begin{tabular}{@{}lrrr@{}}
\toprule
 & & \multicolumn{2}{c}{\textbf{SuperMimic}} \\
\cmidrule(l){3-4}
\textbf{Motion group (motions)} & \textbf{SONIC} & \textbf{1 GPU $\times$ \qty{3}{\hour}} & \textbf{2 GPUs $\times$ \qty{9.8}{\hour}} \\
\midrule
side rolls (22) & \textbf{22} & 2 & 0 \\
flips: $360^\circ$, $180^\circ$, $90^\circ$ (44) & \textbf{44} & 1 & 0 \\
fire-in-the-hole turns (20) & 3 & 3 & 0 \\
crossed legs (10) & 9 & 0 & 0 \\
lying, resting and standing up (99) & 28 & 8 & 0 \\
\midrule
broad jumps (24) & 15 & 0 & 0 \\
dance routine (8) & \textbf{8} & 0 & 0 \\
all other motions (\num{129287}) & 50 & 11 & 0 \\
\midrule
total (\num{129514}) & 179 & 25 & 0 \\
\bottomrule
\end{tabular}
\vspace{0.6em}
\caption{\textbf{Failed motions per motion group on the filtered BONES-SEED training-set benchmark.} SONIC: released checkpoint. Bold: the policy fails every motion in the group.}
\label{tab-failed-motion-stats}
\end{table}
```

::: {#fig-failed-motions width="100%" fig-pos="H"}

:::: {.tex-render render-method="native"}

```{=latex}
\resizebox{\linewidth}{!}{%
\begin{tikzpicture}[font=\scriptsize]
\begin{axis}[
    smplot, width=\plotfull, height=\plottall,
    title={Failed motions},
    xlabel={Wall-clock time (h)},
    xmin=0, xmax=10, ymin=0, ymax=500,
    legend pos=north east,
]
\addplot[theirs, densely dashed, forget plot] coordinates {(0,179) (10,179)} node[pos=1, left, fill=white, inner sep=2pt] {SONIC checkpoint, 179};
\addplot[ours, very thick] coordinates {
      (0.12,1554) (0.24,646) (0.36,455) (0.47,393) (0.59,216) (0.71,172) (0.82,159) (0.94,148) (1.06,105)
      (1.18,88) (1.29,103) (1.41,83) (1.53,61) (1.64,89) (1.76,75) (1.88,49) (2.00,49) (2.11,48) (2.23,47)
      (2.35,68) (2.46,30) (2.58,37) (2.70,28) (2.81,28) (2.93,27) (3.05,31) (3.16,30) (3.28,24) (3.40,24)
      (3.51,16) (3.63,18) (3.75,28) (3.87,21) (3.98,23) (4.10,18) (4.22,14) (4.33,14) (4.45,12) (4.57,15)
      (4.68,22) (4.80,14) (4.92,9) (5.04,13) (5.15,10) (5.27,7) (5.39,8) (5.50,6) (5.62,13) (5.74,7)
      (5.85,9) (5.97,8) (6.09,5) (6.21,9) (6.32,9) (6.44,9) (6.56,9) (6.67,9) (6.79,11) (6.91,6)
      (7.02,9) (7.14,7) (7.26,8) (7.38,7) (7.49,2) (7.61,5) (7.73,8) (7.84,7) (7.96,8) (8.08,4)
      (8.20,4) (8.31,8) (8.43,4) (8.55,4) (8.66,5) (8.78,5) (8.90,5) (9.02,3) (9.13,7) (9.25,3)
      (9.37,6)
    };
\addlegendentry{SuperMimic, 1 H100 GPU}
\addplot[ours!50, very thick] coordinates {
      (0.13,899) (0.25,273) (0.37,143) (0.49,162) (0.61,93) (0.74,84) (0.86,55) (0.98,74) (1.10,46)
      (1.23,55) (1.35,45) (1.47,48) (1.59,59) (1.72,51) (1.84,42) (1.96,42) (2.08,25) (2.21,28) (2.33,25)
      (2.45,26) (2.57,33) (2.69,29) (2.82,28) (2.94,21) (3.06,18) (3.18,16) (3.31,14) (3.43,11) (3.55,14)
      (3.67,14) (3.79,8) (3.92,8) (4.04,8) (4.16,5) (4.28,6) (4.41,8) (4.53,5) (4.65,2) (4.77,4)
      (4.90,3) (5.02,6) (5.14,2) (5.26,4) (5.39,1) (5.51,2) (5.63,2) (5.75,1) (5.87,4) (6.00,1)
      (6.12,0) (6.24,0) (6.36,1) (6.49,0) (6.61,0) (6.73,0) (6.85,0) (6.98,0) (7.10,0) (7.22,0)
      (7.34,0) (7.47,0) (7.59,1) (7.71,0) (7.83,0) (7.96,0) (8.08,1) (8.20,0) (8.32,0) (8.45,0)
      (8.57,0) (8.69,0) (8.81,0) (8.93,0) (9.06,0) (9.18,0) (9.30,0) (9.42,0) (9.55,0) (9.67,0)
      (9.79,0)
    };
\addlegendentry{SuperMimic, 2 H100 GPUs}
\end{axis}
\end{tikzpicture}
}
```

::::

**Failed motions during training on the filtered BONES-SEED training-set benchmark.** Checkpoints are scored every 4000 iterations, for the runs of Figure \ref{fig-compute}(a). SONIC: released checkpoint.

:::
## Experiment protocols

#### Figure \ref{fig-compute}.

SuperMimic trains on the filtered BONES-SEED set (Appendix \ref{sec-data-filter}). The dataset-length sweep in (b, c) uses subsets of 1, 7, 40, and 264 h.

# Velocity-command task {#sec-velocity}

## Training setup

The velocity encoder of §\ref{sec-downstream} maps the command $(v_x, v_y, \omega_z)$ and a feature of the last 10 frames of $\bm{o}$ to the shared latent.

Each encoder is trained from scratch in its own run, jointly with the motion-tracking interface, for 100000 iterations. Both runs use a walking and running library filtered from LAFAN1 and BONES-SEED. Half of the 4096 simulator environments and half of each imagined batch use the velocity interface, so $p(\mathcal{I})$ is uniform; unlike Algorithm \ref{alg-train}, which samples one interface per update, each imagined batch mixes both.

**Commands.** The command $\bm{g}_t = (v_x, v_y, \omega_z)$ stacks the target planar root velocity in the heading (yaw-only) frame and the target world-frame yaw rate. A reference command is the centered 25-frame mean of the reference root velocity in the reference's heading frame. For the RL encoder, each environment resamples its command source at every reset and every 250 control steps (5 s): with probability 0.5 it reads the command from the reference clip at every step, and otherwise it holds a command drawn uniformly from $v_x \in [-1.5, 2]$ m s^−1^, $v_y \in [-1.32, 1.32]$ m s^−1^ and $\omega_z \in [-3.35, 3.35]$ rad s^−1^, zeroed (standing) with probability 0.1.

**Encoder.** On rollouts with reference commands, a mean-squared loss of weight 0.1 pulls the velocity latent toward the motion encoder's latent at the same step, with a stop-gradient on the motion latent.

**Rollouts, reward, and termination.** Each interface's imagined rollouts start from states logged by its own simulator environments. Velocity rollouts of the RL encoder use the velocity-tracking reward and a fall-only termination (Table \ref{tab-reward-velocity}); those of the distillation baseline use the motion-tracking reward and termination of Appendix \ref{sec-spaces}.

## Step test

**Protocol.** From standing, the policy receives a fixed command for 5 s; each command is tested in four trials. The relative steady-state error is the norm of the mean velocity error over the last 2 s, divided by the norm of the command, with the root velocity measured in the heading frame. The per-command value is the median over the trials that did not fall. The 672 step responses form a $15\times15$ grid on each of three planes, spanning the uniform command range above, with the standing command left out. In Figure \ref{fig-downstream}, errors above 0.9 are drawn at 0.9, and a policy that fell in all four trials is drawn at the cap.

**Results.** The RL encoder has the lower error on 650 of the 672 step responses, and the distillation encoder on 15. Their median relative errors are 0.16 and 0.49. Distillation falls in every trial on seven commands, all combining translation with a turn of at least 2.8 rad s^−1^, where the motion library has almost no data. Each policy has one training seed.
