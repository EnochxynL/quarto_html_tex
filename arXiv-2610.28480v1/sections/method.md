# Method {#sec-method}

![**SuperMimic training loop.** (1) The current policy $\pi_\theta$ collects transitions in simulation into a fixed-size replay buffer $\mathcal{B}$, where new transitions replace the oldest. (2) The differentiable world model is fit to $k$-step windows sampled from $\mathcal{B}$ (§\ref{sec-wm}). (3) The policy is improved by backpropagation-through-time through the frozen world model over $H$ imagined steps; a critic $V_\psi$, trained in the same phase, bootstraps the return beyond $H$ (§\ref{sec-policy}). Dashed arrows are gradients;  = frozen,  = trained. Symbols: goal $\bm{g}_t$ (e.g., reference motion), action $\bm{a}_t$, action noise $\bm{\epsilon}_t$, observation $\bm{o}_t$, state $\bm{s}$ and predicted state $\hat{\bm{s}}$, and sim context $\bm{\xi}$ (domain-randomization parameters). $\mathcal{L}_{\text{WM}}$ is the world-model loss, $\hat{\bar{\bm{o}}}_t$ the predicted noise-free observation, $\bm{\eta}_t$ the sensor noise, $\hat{r}_{t+1}$ the predicted reward, and $\hat{J}(\theta)$ the policy objective.](figures/quarto/fig-pipeline.pdf){#fig-pipeline width="100%" fig-pos="H"}

## SuperMimic training loop {#sec-problem}

SuperMimic trains one goal-conditioned whole-body controller across a multi-skill motion library and supports multiple goal interfaces. It captures the shared humanoid dynamics in a differentiable world model and improves the policy through short imagined rollouts. Training alternates between three phases in one loop (Figure \ref{fig-pipeline}). First, the current policy collects simulator transitions into a replay buffer. Second, we fit the differentiable world model to short replay windows. Third, the policy is improved by backpropagating an imagined return through the frozen world model, with each rollout seeded from a replay-buffer state in the Dyna style [@sutton1991dyna; @janner2019trust]. The buffer, model, and policy are updated throughout training, so dynamics learning and control improve together rather than in separate stages (Algorithm \ref{alg-train}, Appendix \ref{sec-algorithm}). Transitions from earlier policies remain valid for fitting the world model, because the dynamics do not depend on the policy that collected them.

We denote the goal-conditioned partially observable Markov decision process (POMDP) by $\mathcal{M}$ and use compact notation with state $\bm{s}_t$, goal $\bm{g}_t$, and action $\bm{a}_t$. State $\bm{s}_t$ gives the proprioceptive observation $\bm{o}_t$ and the termination $d_t$, which is 1 if $\bm{s}_t$ is terminal. Action $\bm{a}_t$ in state $\bm{s}_t$ yields the reward $r_{t+1}$ and the next state $\bm{s}_{t+1}$. The policy is deterministic, $\bm{a}_t=\pi_\theta(\bm{o}_t,\bm{g}_t)$, and $\bm{a}_t$ parameterizes a normalized joint setpoint; for motion tracking, $\bm{g}_t$ is read from a reference motion. During data collection, the simulator executes the noisy action $\bm{a}_t+\bm{\epsilon}_t$ with action noise $\bm{\epsilon}_t\sim\rho_\epsilon$, and the replay buffer stores this executed noisy action. The noise widens the range of actions on which the world model is fit; it serves only the model fit and is optional. Returns use a soft survival weight, $c_0=1$ and $c_{t+1}=c_t(1-d_{t+1})$, giving $J(\theta)=\mathbb{E}[\sum_{t\ge0}\gamma^t c_t r_{t+1}]$ with discount $\gamma\in[0,1)$. The simulator logs hard terminations, while the learned model predicts a termination probability $\hat{d}_t\in[0,1]$, which keeps the survival weight differentiable in imagined rollouts. Throughout, a hat marks the world-model counterpart of a simulator quantity. We also factor the observation as $\bm{o}_t=\bar{\bm{o}}_t+\bm{\eta}_t$, with $\bar{\bm{o}}_t$ the noise-free observation and known observation noise $\bm{\eta}_t\sim\rho_\eta$ sampled outside the world model. Appendix \ref{sec-spaces} gives the full spaces and reward.

The default interface is full-reference motion tracking. Other goal interfaces, such as velocity, share the same learned dynamics and train jointly with motion tracking (Appendix \ref{sec-unified}).

## Learning a differentiable world model {#sec-wm}

The simulator's articulated multi-rigid-body dynamics are known, but the simulator need not provide gradients, so SuperMimic learns a differentiable surrogate to obtain policy gradients: it supplies the predictions and Jacobians for the BPTT update in §\ref{sec-policy}. The resulting analytic policy gradient is the gradient of a surrogate for the expected return in simulation. Since the simulator's randomness has known sources, the world model stays deterministic: it conditions on the per-episode sim context $\bm{\xi}$ (friction, calibration offsets, and torso center-of-mass) and predicts the noise-free observation $\bar{\bm{o}}_t$.

The world model contains a learned dynamics model and reward, observation, and termination heads; each head is either learned or computed analytically, $$\hat{\bm{s}}_{t+1}=f_\omega(\hat{\bm{s}}_t,\bm{a}_t,\bm{\xi}),\qquad
  \hat{r}_{t+1}=r_\omega(\hat{\bm{s}}_t,\bm{a}_t,\bm{g}_t),\qquad
  \hat{\bar{\bm{o}}}_t=g_\omega(\hat{\bm{s}}_t,\bm{\xi}),\qquad
  \hat{d}_t=d_\omega(\hat{\bm{s}}_t,\bm{g}_t).$$ We fit the network weights $\omega$ on $k$-step autoregressive replay windows ($k{=}8$), seeded at the logged state $\hat{\bm{s}}_0=\bm{s}_0$ and rolled forward on logged actions, by minimizing

$$
\mathcal{L}_{\text{WM}}(\omega) = \mathbb{E}_{\mathcal{B}} \sum_{j=1}^{k} \Big[ \lVert \hat{\bm{s}}_{j} - \bm{s}_{j} \rVert^2 + (\hat{r}_{j} - r_{j})^2 + \lVert \hat{\bar{\bm{o}}}_{j} - \bar{\bm{o}}_{j} \rVert^2 + \mathrm{BCE}(\hat{d}_{j}, d_{j}) \Big],
$$ {#eq-wm-loss}

where an analytic head has no loss term. Here $r_j$ is the simulator reward, $d_j\in\{0,1\}$ is the simulator termination label, and BCE is the binary cross-entropy.

## Learning the policy through the world model {#sec-policy}

During each policy update, we hold the world-model weights $\omega$ fixed and optimize $\pi_\theta$ and $V_\psi$ on imagined rollouts of $H{=}32$ steps. The critic $V_\psi$ estimates the return beyond step $H$, so the model must be accurate only within these $H$ steps. This imagination horizon exceeds the $k$-step replay windows on which we fit the model (§\ref{sec-wm}). In practice, the learned model remains stable over indefinitely long rollouts, because the $k$-step autoregressive fit trains it to correct its own prediction errors.

Each imagined rollout starts from a replay-buffer state $\bm{s}_0\sim\rho_0$ with its recorded sim context $\bm{\xi}$. At step $t$, the model emits $\hat{\bar{\bm{o}}}_t$, we re-add sensor noise, and the policy acts: $\bm{a}_t=\pi_\theta(\hat{\bar{\bm{o}}}_t+\bm{\eta}_t,\bm{g}_t)$, $\bm{\eta}_t\sim\rho_\eta$. The policy objective over imagined rollouts is

$$
\hat{J}(\theta) = \mathbb{E}_{\bm{s}_0 \sim \rho_0,\, \pi_\theta} \Big[ \sum_{t=0}^{H-1} \gamma^t \hat{c}_t\, \hat{r}_{t+1} ~~+~~ \gamma^H \hat{c}_H\, V_\psi(\hat{\bm{s}}_H, \bm{g}_H, \bm{\xi}) \Big].
$$ {#eq-policy-obj}

For motion tracking, the reward $r_{t+1}$ is the BeyondMimic motion-tracking reward [@liao2025beyondmimic] without its self-collision penalty (Appendix \ref{sec-spaces}).

The world model is differentiable, so BPTT computes a first-order gradient $\nabla_\theta\hat{J}$ through the $H$ imagined steps via the world model's Jacobians with respect to $\hat{\bm{s}}_t$ and $\bm{a}_t$. In contrast, PPO treats the dynamics as a black box: it weights the score $\nabla_\theta\log\pi_\theta$ of a stochastic policy by the advantages of sampled actions, a likelihood-ratio estimate. BPTT instead differentiates the return with respect to each action, so over short horizons its gradient has much lower variance.

The critic $V_\psi$ is fit to generalized advantage estimation returns [@schulman2015high] computed backward in time over the imagined transitions only,

$$
\mathcal{L}_V(\psi) = \mathbb{E} \sum_{t=0}^{H-1} \big( V_t - \hat{R}_t \big)^2, \qquad
  \hat{R}_t = \hat{r}_{t+1} + \gamma (1-\hat{d}_{t+1}) \big[ (1-\lambda) V_{t+1} + \lambda \hat{R}_{t+1} \big],
$$ {#eq-critic}

with $V_t = V_\psi(\hat{\bm{s}}_t, \bm{g}_t, \bm{\xi})$. The recursion starts from $\hat{R}_H = V_H$, the critic's estimate of the return beyond the horizon. The targets $\hat{R}_t$ are computed once per rollout and remain fixed while $\psi$ is fit.

The policy and critic updates together form a short-horizon actor--critic in the spirit of SHAC [@xu2022accelerated], which backpropagates through a differentiable simulator. SuperMimic replaces SHAC's hard episode termination with the survival weight $\hat{c}_t$, and its critic has no exponential-moving-average target network. Prior motion-tracking controllers trained with analytic gradients often omit a critic and optimize only the $H$-step reward sum [@fussell2021supertrack; @yao2022controlvae]. Without a critic, training can reach a similar nominal tracking return, but this unbootstrapped objective is more myopic. The critic matters after perturbations, where recovery or balance rewards can lie beyond the imagination window (§\ref{sec-critic}).
