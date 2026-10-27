# Experimental Results

We show that SuperMimic scales favorably relative to PPO pipelines, identify the world-model properties behind this scaling, demonstrate transfer on a real Unitree G1, and report a preliminary study of downstream goal interfaces. The simulator is MuJoCo Warp, a GPU implementation of MuJoCo [@todorov2012mujoco]. All our reported costs are measured on NVIDIA H100 (80   SXM5) GPUs of Lambda on-demand instances. We ran several random seeds and found training very stable, which we attribute to the dense reward that motion tracking gives at every step. The figures therefore do not report seed variation. Normalized return, return for short, is the undiscounted sum of the per-step reward over the full episode, divided by the largest value this sum can take. A policy that terminates early therefore scores low.

## SuperMimic reaches SONIC-level tracking with far fewer GPU-hours {#sec-scaling}

We compare against SONIC, a published PPO pipeline trained on a 128-GPU cluster. Both methods build on the BeyondMimic motion-tracking formulation [@liao2025beyondmimic], making SONIC the closest available published comparison. Within 3 h on one GPU, SuperMimic surpasses the normalized return of the released SONIC checkpoint (Figure \ref{fig-compute}(a)). On a shared benchmark of 129514 motions, it also fails on fewer motions than SONIC: 25 after 3 h on one GPU and 0 after 9.8 h on two GPUs, against 179 for SONIC's released checkpoint (Appendix \ref{sec-eval}). We state the 3 h conservatively: from then on, every checkpoint is ahead of SONIC by at least half of the gap between SONIC and SuperMimic's best result, in both return and failed motions. SuperMimic thus uses more than $50\times$ less wall-clock time and more than $1000\times$ fewer GPU-hours than SONIC.

[]{#par-accounting}

**Compute accounting.** The ratios compare SONIC's reported 128 NVIDIA L40 GPUs for 7 days (about 21000 GPU-hours) with 3 h on one NVIDIA H100, within which SuperMimic surpasses the return of SONIC's released checkpoint. They are about $56\times$ ($>50\times$) in wall-clock time and about $7200\times$ ($>1000\times$) in GPU-hours. The 3 h cover the full training loop; checkpoint evaluations run after training and are not counted. SuperMimic trains on 264.56 h of motion from BONES-SEED [@bones2026seed], the public subset of SONIC's data, about $2.3\times$ less than SONIC's 611 h. The GPU models also differ: in peak throughput, an H100 delivers $0.74\times$ the fp32 and $5.5\times$ the tensor-core performance of an L40; how much of that peak either run used is unknown. Nonetheless, $2.3\times$ in data and at most $5.5\times$ in peak GPU throughput cannot account for a $1000\times$ gap in GPU-hours.

Figure \ref{fig-controlled}(a) gives a controlled comparison on LAFAN1 [@harvey2020robust]. The baseline, PPO-Sim, is PPO trained in the simulator. PPO-Sim shares SuperMimic's motions, observations, reward, termination, domain randomization, actor and critic network sizes, and evaluation protocol. It uses BeyondMimic's PPO hyperparameters [@liao2025beyondmimic] and 8192 parallel environments per GPU, twice SuperMimic's. PPO-Sim estimates its policy gradient from sampled simulator rollouts; SuperMimic backpropagates its imagined return through world-model rollouts. SuperMimic reaches a return of 0.82 in evaluation within 1.2 h on one GPU. Within the 18 h budget, PPO-Sim does not reach it. Its final return is 0.60 on one GPU, 0.70 on four, and 0.72 on eight, so going from four to eight GPUs barely helps.

Figure \ref{fig-compute}(b, c) shows that, for SuperMimic, GPU-hours to the target return grow slowly as dataset length increases, while on the same sweep the world model's prediction error stays stable; §\ref{sec-wm-properties} traces both trends to one world model amortizing the dynamics shared across motions.

::: {#fig-compute width="100%" fig-pos="H"}

```{=latex}
\centering
\def\budgetrows{10.5mm}
\begin{tikzpicture}[font=\scriptsize]
\begin{axis}[
    name=curve, smplot, width=\plotequal, height=\plottall,
    title={\textbf{(a)} Normalized return},
    xlabel={GPU-hours (wall-clock on one GPU)},
    xmode=log, xmin=0.05, xmax=4e4,
    xtick={0.1,1,10,100,1000,10000,100000}, xticklabels={0.1,1,10,100,1000,10000,},
    ymin=0.6, ymax=0.98, ytick={0.6,0.68,0.76,0.84,0.92}, yticklabel style={/pgf/number format/fixed, /pgf/number format/fixed zerofill, /pgf/number format/precision=2},
    legend style={at={(axis cs:4e4,0.88)}, anchor=north east, inner sep=0pt, nodes={inner ysep=1pt}},
]
\addplot[theirs, densely dashed, forget plot] coordinates {(0.05,0.9012) (4e4,0.9012)} node[pos=1, left, fill=white, inner sep=2pt] {SONIC checkpoint, 128 L40 GPUs, 0.90};
\addplot[ours, very thick] coordinates {
      (0.061,0.7034) (0.091,0.7573) (0.120,0.8042) (0.149,0.8269) (0.208,0.8495) (0.237,0.8572) (0.326,0.8665) (0.384,0.8821)
      (0.502,0.8970) (0.619,0.9074) (0.795,0.9152) (1.001,0.9246) (1.264,0.9308) (1.586,0.9319) (1.995,0.9344) (2.521,0.9426)
      (3.164,0.9363) (3.982,0.9502) (5.006,0.9499) (6.322,0.9598) (7.932,0.9616) (9.368,0.9600)
    };
\addlegendentry{SuperMimic, 1 H100 GPU}
\addplot[ours!50, very thick] coordinates {
      (0.066,0.6344) (0.128,0.7401) (0.189,0.8191) (0.250,0.8443) (0.372,0.8616) (0.495,0.8821) (0.617,0.8933) (0.740,0.9063)
      (0.985,0.9123) (1.230,0.9223) (1.598,0.9287) (1.965,0.9349) (2.454,0.9359) (3.188,0.9436) (3.921,0.9457) (5.022,0.9447)
      (6.367,0.9492) (7.956,0.9564) (10.036,0.9602) (12.606,0.9612) (15.788,0.9636) (19.584,0.9641)
    };
\addlegendentry{SuperMimic, 2 H100 GPUs}
\end{axis}
\begin{axis}[
    smplot, hide axis, width=\plotequal, height=\budgetrows,
    at={(curve.south west)}, anchor=south west,
    xmode=log, xmin=0.05, xmax=4e4,
    ymin=0, ymax=2.3,
]
\addplot[track, ultra thick] coordinates {(3,2) (168,2)} node[midway, fill=white, text=black] {$>$50$\times$};
\addplot[track, ultra thick] coordinates {(3,1) (21000,1)} node[midway, fill=white, text=black] {$>$1000$\times$};
\addplot[ours, only marks, mark=*] coordinates {(3,2) (3,1)};
\addplot[theirs, only marks, mark=diamond*] coordinates {(168,2) (21000,1)};
\node[ours, below] at (axis cs:3,2) {3 h};
\node[theirs, below] at (axis cs:168,2) {168 h};
\node[ours, below] at (axis cs:3,1) {3 GPU-h};
\node[theirs, below left] at (axis cs:4e4,1) {21k GPU-h};
\end{axis}
\begin{axis}[
    name=cost, smplot, width=\plotequal, height=\plothalf,
    at={(curve.north east)}, anchor=north west, xshift=\plotgap,
    title={\textbf{(b)} Compute to target (GPU-h)},
    xmode=log, xmin=0.7, xmax=400, axis x line=none,
    ymin=0, ymax=2, ytick={0,1,2},
    legend pos=south east,
]
\addplot[context, densely dashed, domain=1:7] {0.539*x};
\addlegendentry{proportional to data}
\addplot[ours, very thick, mark=*] coordinates {(1,0.539) (7,1.350) (40,1.908) (264,1.892)};
\end{axis}
\begin{axis}[
    smplot, width=\plotequal, height=\plothalf,
    at={(cost.south west)}, anchor=north west, yshift=-\plotsep,
    title={\textbf{(c)} 8-step prediction error ($\times$10\textsuperscript{\textminus3})},
    xlabel={Dataset length (h)},
    xmode=log, xmin=0.7, xmax=400, xtick={0.1,1,10,100,1000}, xticklabels={,1,10,100,},
    ymin=0, ymax=0.012, ytick={0,0.005,0.01}, scaled y ticks=base 10:3, ytick scale label code/.code={},
]
\addplot[ours, very thick, mark=*] coordinates {(1,0.00679) (7,0.00738) (40,0.01096) (264,0.00993)};
\end{axis}
\end{tikzpicture}
```

**SuperMimic surpasses SONIC's tracking return with far fewer GPU-hours.** (a) SuperMimic on one and two H100 GPUs surpasses the return of the released SONIC checkpoint (dashed), all three scored on the same benchmark of 129514 motions (264 h). Two budget rows compare SuperMimic (dot) with SONIC (diamond): SuperMimic reduces wall-clock time by more than $50\times$ and GPU-hours by more than $1000\times$. (b, c) On a shared dataset-length sweep, GPU-hours to target return (b) grow slowly while the world model's 8-step prediction error (c) stays within 0.007--0.011 as the dataset grows from 1 to 264 h, consistent with one world model amortizing shared body and contact dynamics across motions. The prediction error counts the state only, is normalized by a predefined nominal error, and is measured online on policy rollouts.

:::
::: {#fig-controlled width="100%" fig-pos="H"}

```{=latex}
\centering
\begin{tikzpicture}[font=\scriptsize]
\begin{axis}[
    name=race, smplot, width=\plotequal, height=\plottall,
    title={\textbf{(a)} Normalized return},
    xlabel={Wall-clock time (h)},
    xmin=0, xmax=18,
    return axis,
    legend pos=south east, reverse legend,
]
\addplot[context, densely dashed, forget plot] coordinates {(0,0.82) (18,0.82)};
\addplot[theirslight, thick] coordinates {(0.00236111,0.001764) (0.24,0.025203) (0.479583,0.21044) (0.720972,0.2256) (0.960417,0.2352) (1.19861,0.2651) (1.43987,0.3023) (1.67875,0.3301) (1.91973,0.3662) (2.16125,0.3731) (2.40778,0.4068) (2.65042,0.4044) (2.88959,0.3948) (3.1318,0.43) (3.37181,0.4195) (3.61264,0.449) (3.85361,0.4474) (4.09305,0.4878) (4.32972,0.4612) (4.57042,0.4728) (4.81069,0.4795) (5.0457,0.4707) (5.28334,0.534) (5.52069,0.5233) (5.75889,0.4984) (5.99695,0.5348) (7.18611,0.5412) (8.38444,0.5449) (9.62625,0.5499) (11.9934,0.5881) (14.0222,0.6166) (18.6919,0.602)};
\addlegendentry{PPO-Sim, 1 GPU}
\addplot[theirs, thick] coordinates {(0.00180555,0.00181) (0.184722,0.3262) (0.365278,0.3488) (0.542777,0.3788) (0.721389,0.4025) (0.900417,0.4404) (1.08069,0.4702) (1.25958,0.4685) (1.43903,0.4776) (1.61959,0.5071) (1.7975,0.5015) (1.97611,0.5406) (2.15487,0.5471) (2.33319,0.5577) (2.51125,0.5544) (2.68931,0.5685) (2.86806,0.5803) (3.04625,0.5556) (3.22445,0.6101) (3.40278,0.5919) (3.58125,0.5994) (3.75931,0.619) (3.93736,0.599) (4.11569,0.6122) (4.29402,0.6056) (4.47208,0.6221) (5.35902,0.6353) (6.24459,0.64) (7.12736,0.64) (8.89098,0.6677) (10.646,0.6828) (14.1303,0.6865) (17.7414,0.7028)};
\addlegendentry{PPO-Sim, 4 GPUs}
\addplot[theirsdark, thick] coordinates {(0.00138889,0.001772) (0.19125,0.3744) (0.377223,0.3994) (0.563195,0.388) (0.748611,0.4448) (0.934584,0.4885) (1.12069,0.5124) (1.30653,0.5082) (1.49194,0.5438) (1.67639,0.554) (1.86055,0.5414) (2.04486,0.5543) (2.22903,0.5772) (2.41305,0.5883) (2.59667,0.5909) (2.78097,0.603) (2.96445,0.6032) (3.14792,0.605) (3.33125,0.6189) (3.51472,0.6225) (3.69819,0.6107) (3.88138,0.6108) (4.06458,0.621) (4.24833,0.6094) (4.43153,0.6318) (4.61486,0.6354) (5.53014,0.6449) (6.445,0.6744) (7.36055,0.6688) (9.19111,0.6944) (11.0203,0.7018) (14.4397,0.7188) (18.0328,0.7218)};
\addlegendentry{PPO-Sim, 8 GPUs}
\addplot[ours, very thick, forget plot] coordinates {(0.0021125,0.001519) (0.077808,0.524) (0.151899,0.6166) (0.225991,0.6672) (0.299996,0.67) (0.373919,0.696) (0.44801,0.7656) (0.522101,0.7565) (0.596276,0.777) (0.670791,0.779) (0.745049,0.7909) (0.894413,0.7894) (1.04353,0.8102) (1.19272,0.8331) (1.342,0.8309) (1.49103,0.8483) (1.79009,0.8282) (2.08984,0.8519) (2.38983,0.8509) (2.69008,0.8616) (2.98771,0.8661)};
\node[ours, below right, inner sep=2pt] at (axis cs:2,0.82) {SuperMimic, 1 GPU};
\end{axis}
\begin{axis}[
    name=return, smplot, width=\plotequal, height=\plothalf,
    at={(race.north east)}, anchor=north west, xshift=\plotgap,
    title={\textbf{(b)} Final return},
    xmode=log, xmin=6, xmax=170, axis x line=none,
    return axis,
]
\draw[highlight, line width=1em] (axis cs:32,0) -- (axis cs:32,0.9);
\addplot[context, densely dashed] coordinates {(6,0.82) (170,0.82)};
\addplot[ours, mark=*, mark options={fill=white}] coordinates {(8,0.087) (16,0.25) (32,0.84) (64,0.862) (128,0.835)};
\addplot[ours, very thick, mark=*] coordinates {(8,0.392) (16,0.843) (32,0.866) (64,0.863) (128,0.823)};
\end{axis}
\begin{axis}[
    smplot, axis on top, width=\plotequal, height=\plothalf,
    at={(return.south west)}, anchor=north west, yshift=-\plotsep,
    title={\textbf{(c)} Hours to return 0.82},
    xlabel={Imagination horizon $H$},
    xmode=log, xmin=6, xmax=170,
    xtick={8,16,32,64,128}, xticklabels={8,16,\textbf{32},64,128},
    minor xtick={7,10,12,14,20,24,28,40,48,56,80,96,112,160},
    ymin=0, ymax=5, ytick={0,2,4},
    legend style={at={(1,1)}, anchor=south east}, reverse legend,
]
\draw[highlight, line width=1em] (axis cs:32,0) -- (axis cs:32,5);
\addplot[ours, mark=*, mark options={fill=white}] coordinates {(32,1.37) (64,1.34) (128,3.80)};
\addlegendentry{no critic}
\addplot[ours, very thick, mark=*] coordinates {(16,1.19) (32,0.88) (64,1.70) (128,4.62)};
\addlegendentry{critic}
\addplot[ours, very thick, only marks, mark=x, mark size=1.8pt, forget plot] coordinates {(8,5)};
\addplot[ours, only marks, mark=x, mark size=1.8pt, forget plot] coordinates {(8,4.4)};
\addplot[ours, only marks, mark=x, mark size=1.8pt, forget plot] coordinates {(16,5)};
\node[context, anchor=north] at (axis cs:11.5,4.75) {not reached};
\end{axis}
\end{tikzpicture}
```

**In controlled comparisons, SuperMimic reaches a higher return sooner than PPO-Sim, and the critic enables shorter imagination horizons.** All runs use LAFAN1 (40 clips, 2.45 h). (a) SuperMimic backpropagates its imagined return through its world model on one GPU; PPO-Sim runs PPO in the simulator on 1, 4, or 8 GPUs (§\ref{sec-scaling}). Each point on a curve is a saved checkpoint scored on all 40 clips. (b, c) Final training return (b) and wall-clock hours until the training return reaches 0.82 (c) for each imagination horizon $H$, with and without the critic. The dashed line in (a) and (b) marks this target return of 0.82. Training return is the return of training episodes. Their initial states follow return-based reset sampling (Appendix \ref{sec-reset}) and shift during training, so training return differs from the checkpoint scores in (a). In (c), a cross marks a horizon at which return 0.82 is not reached: both variants at $H{=}8$, no critic at $H{=}16$. The shaded band marks the default $H{=}32$.

:::
## Properties of the learned world model {#sec-wm-properties}

These results rest on three properties of the learned world model $f_\omega$: its accuracy holds as the motion library grows, and its rollouts are fast and differentiable.

**One model amortizes the motion library.** In Figure \ref{fig-compute}(c), the world model's 8-step prediction error stays between 0.007 and 0.011 as the dataset grows from 1 to 264 h. Every motion is executed by the same humanoid, so added clips supply more evidence about the shared body and contact dynamics rather than demanding new capacity. This is consistent with the slow growth of the compute needed to reach the target return (§\ref{sec-scaling}).

::: {#fig-wm-efficiency width="100%" fig-pos="H"}

```{=latex}
\centering
\begin{tikzpicture}[font=\scriptsize, speedup/.style={context, |-|, shorten <=1ex, shorten >=1ex}]
\begin{axis}[
    name=speed, smplot, width=\plotequal, height=\plotshort,
    title={\textbf{(a)} Steps per second},
    xlabel={Parallel environments},
    xmode=log, xmin=400, xmax=84000,
    xtick={512,2048,8192,32768}, xticklabels={512,2k,8k,32k},
    minor xtick={1024,4096,16384,65536},
    ymode=log, ymin=1e4, ymax=3e7,
    ytick={1e4,1e5,1e6,1e7}, yticklabels={10\textsuperscript{4},10\textsuperscript{5},10\textsuperscript{6},10\textsuperscript{7}},
]
\fill[gray!12] (axis cs:2048,1e4) rectangle (axis cs:16384,3e7);
\node[font=\scriptsize, gray] at (axis cs:5793,1.1e7) {used in practice};
\draw[speedup] (axis cs:2048,7.84e4) -- node[left, black] {11$\times$} (axis cs:2048,8.43e5);
\draw[speedup] (axis cs:16384,2.61e5) -- node[right, black] {26$\times$} (axis cs:16384,6.71e6);
\draw[speedup] (axis cs:65536,3.22e5) -- node[left, black] {62$\times$} (axis cs:65536,2.00e7);
\addplot[ours, very thick, mark=*] coordinates {(512,2.16e5) (1024,4.22e5) (2048,8.43e5) (4096,1.68e6) (8192,3.35e6) (16384,6.71e6) (32768,1.34e7) (65536,2.00e7)} node[pos=0.25, above left] {World model};
\addplot[theirs, thick, mark=*, mark options={fill=white}] coordinates {(512,2.33e4) (1024,4.40e4) (2048,7.84e4) (4096,1.32e5) (8192,1.97e5) (16384,2.61e5) (32768,3.05e5) (65536,3.22e5)} node[pos=0.75, below right] {MuJoCo Warp};
\end{axis}
\begin{axis}[
    smplot, width=\plotequal, height=\plotshort,
    at={(speed.south east)}, anchor=south west, xshift=\plotgap,
    title={\textbf{(b)} Training return},
    xlabel={Imagined steps},
    xmode=log, xmin=1e7, xmax=8e10,
    table/x=plot_step, table/y=mean_reward_smooth,
    return axis,
    legend pos=south east, reverse legend, legend style={row sep=-3pt, name=ppolegend},
    legend image code/.code={\draw[#1] (0cm,0cm) -- (0.4cm,0cm);},
]
\draw[context, |-|] (axis cs:9.317e8,0.841) -- node[pos=0.2, below, inner sep=1pt, black] {64$\times$} (axis cs:5.956e10,0.841);
\addplot[theirslight!55!white, thick] table {figures/data/fig5b/walk_run_sprint_ppo.csv};
\addlegendentry{4k$\times$32}
\addplot[theirslight, thick] table {figures/data/fig5b/walk_run_sprint_ppo_b8192_n24.csv};
\addlegendentry{8k$\times$24}
\addplot[theirs, thick] table {figures/data/fig5b/walk_run_sprint_ppo_b8192.csv};
\addlegendentry{8k$\times$32}
\addplot[theirsdark, thick] table {figures/data/fig5b/walk_run_sprint_ppo_b16384.csv};
\addlegendentry{16k$\times$32}
\addplot[ours, very thick, forget plot] table {figures/data/fig5b/walk_run_sprint_supermimic.csv};
\node[anchor=east] at (axis cs:1.1e8,0.68) {SuperMimic};
\end{axis}
\node[anchor=south east, inner xsep=2pt] at (ppolegend.south west) {PPO-WM};
\end{tikzpicture}
```

**Imagined rollouts are fast and differentiable.** (a) On an H100, over the batch sizes used in practice (shaded, 2k--16k parallel environments), the world model runs more than $10\times$ faster than MuJoCo Warp; the gap widens to $62\times$ at 64k, where MuJoCo Warp has flattened. One step is one 50 Hz control step, which MuJoCo Warp computes as four 5 ms substeps; the world model runs at the TF32 precision used in SuperMimic's training. (b) On walk/run/sprint motions from LAFAN1 [@harvey2020robust], SuperMimic, trained with its actor--critic update, reaches the best training return of PPO trained on world-model rollouts (PPO-WM) with about $64\times$ fewer imagined steps. PPO-WM runs at four batch sizes (parallel rollouts $\times$ steps per rollout); 16k$\times$`<!-- -->`{=html}32 is the best. Each curve is a centered moving average over $\pm0.05$ decade of imagined steps.

:::
**Imagination accelerates rollouts.** During policy optimization, rollout speed sets the update cost. Figure \ref{fig-wm-efficiency}(a) shows that the world model runs more than $10\times$ faster than MuJoCo Warp at the batch sizes used in practice, and up to $62\times$ at 64k parallel environments.

**First-order gradients need fewer imagined steps.** As a mechanism ablation, Figure \ref{fig-wm-efficiency}(b) isolates the benefit of first-order policy updates: SuperMimic reaches the best PPO-WM return with about $64\times$ fewer imagined steps, so the gain is not just rollout speed.

## A critic enables shorter horizons and push recovery {#sec-critic}

Figure \ref{fig-controlled}(b, c) sweeps $H$ with and without the critic. Without the critic, training fails at $H\le16$. With it, $H{=}16$ matches the critic-free $H{=}32$, and $H{=}32$ reaches a return of 0.82 fastest. Raising $H$ from 64 to 128 nearly triples the time to that return and lowers the final return; $H{=}128$ is the longest horizon that fits on an H100. At matched return, the critic still changes behavior. Under 0.5 m s^−1^--4 m s^−1^ velocity pushes while holding a static T-pose in simulation, the critic policy settles within 0.5 s--2.4 s. The critic-free policy never settles: it keeps stumbling even at 0.5 m s^−1^ and falls at 4 m s^−1^.

## Real-robot transfer {#sec-real-robot}

One general motion tracker deploys on a real Unitree G1 without per-motion tuning (Figure \ref{fig-acrobatics}). The four motions cover locomotion (a skipping jump), contact-rich whole-body motion with the torso and limbs on the floor (a side roll), and acrobatics (a $90^\circ$ flip and an in-place $360^\circ$ flip).

::: {#fig-acrobatics width="100%" fig-pos="H"}

```{=latex}
\centering
\newcommand{\snaprow}[3]{\begin{tikzpicture}[snaptag/.style={font=\footnotesize, text=white, fill=black, fill opacity=0.6, text opacity=1, inner sep=1.5pt, rounded corners=1pt}]
  \node[inner sep=0pt] (s) {\includegraphics[width=\linewidth]{#1}};
  \node[snaptag, anchor=north west, font=\footnotesize\bfseries] at ([shift={(1.5pt,-1.5pt)}]s.north west) {#2};
  \node[snaptag, anchor=north east] at ([shift={(-1.5pt,-1.5pt)}]s.north east) {$\Delta t=\qty{#3}{\second}$};
\end{tikzpicture}}
\snaprow{snapshot_skip.jpg}{(a)}{0.2}\\[0.5mm]
\snaprow{snapshot_roll.jpg}{(b)}{0.3}\\[0.5mm]
\snaprow{snapshot_flip90.jpg}{(c)}{0.2}\\[0.5mm]
\snaprow{snapshot_flip360.jpg}{(d)}{0.2}
```

**One general motion tracker, trained through the learned world model, transfers to a real Unitree G1.** (a) Skipping jump, (b) side roll, (c) $90^\circ$ flip, and (d) in-place $360^\circ$ flip.

:::
## Downstream tasks: RL encoder vs. distillation baseline {#sec-downstream}

SuperMimic trains downstream goal encoders jointly with the motion-tracking interface, sharing one decoder and world model (Appendix \ref{sec-unified}). Our study of downstream interfaces is preliminary. We train one velocity encoder on a velocity-tracking reward through the world model. We compare it with a distillation baseline: a velocity encoder trained on the motion-tracking reward, with commands read from the reference motions. Figure \ref{fig-downstream} evaluates both on 672 step responses spanning the velocity space (Appendix \ref{sec-velocity}). The RL encoder has the lower steady-state error on 650 of them, and the distillation encoder on 15. Only the distillation encoder falls, on seven fast turns with almost no motion-library data.

::: {#fig-downstream width="100%" fig-pos="H"}

```{=latex}
\centering
\input{figures/data/stepgrid_grid.tex}
\pgfdeclareplotmark{ring}{
  \pgfpathcircle{\pgfpointorigin}{\pgfplotmarksize}
  \pgfpathcircle{\pgfpointorigin}{\stepgridhole}
  \pgfseteorule\pgfusepath{fill}
  \pgfpathcircle{\pgfpointorigin}{\pgfplotmarksize}
  \pgfusepath{stroke}
}
\newlength{\stepgridcell}\setlength{\stepgridcell}{\dimexpr\plotthird/\pgfkeysvalueof{/pgfplots/stepgrid cells}\relax}
\newcommand{\stepgridradius}[1]{0.48*\stepgridcell*sqrt(#1)}
\pgfplotsset{
  stepgrid/.style={
    smplot, axis on top, width=\plotthird, height=\plotthird,
    colormap={stepgrid}{color(0cm)=(white) color(0.1cm)=(shade!15) color(1cm)=(shade)}, point meta min=-2, point meta max=3,
  },
  stepgrid field/.style={matrix plot*, point meta={log10(max(\thisrow{sec},0.01))}, mesh/cols=\pgfkeysvalueof{/pgfplots/stepgrid cells}},
  stepgrid outer/.style={visualization depends on={\thisrow{outer} \as \outer}, scatter/@pre marker code/.append style={/tikz/mark size={\stepgridradius{\outer}}}},
  stepgrid rings/.style={
    scatter, only marks, mark=ring, thin, scatter src=explicit symbolic, scatter/classes={rl={ours}, ds={theirs}},
    stepgrid outer, visualization depends on={\thisrow{inner} \as \inner},
    scatter/@pre marker code/.append code={\pgfmathsetlengthmacro{\stepgridhole}{\stepgridradius{\inner}}},
  },
  stepgrid fell/.style={scatter, only marks, mark=o, thick, scatter/use mapped color={draw=black}, stepgrid outer, restrict expr to domain={\thisrow{fell}}{1:1}},
}
\newcommand{\stepgridplots}[1]{
  \addplot[stepgrid field] table[x=x, y=y, meta=sec] {figures/data/stepgrid_field_#1.csv};
  \addplot[stepgrid rings] table[x=x, y=y, meta=win] {figures/data/stepgrid_rings_#1.csv};
  \pgfplotstableread{figures/data/stepgrid_rings_#1.csv}\stepgridtable
  \def\stepgridfalls{0}
  \pgfplotstableforeachcolumnelement{fell}\of\stepgridtable\as\stepgridfell{\pgfmathtruncatemacro{\stepgridfalls}{\stepgridfalls+\stepgridfell}}
  \ifnum\stepgridfalls>0 \addplot[stepgrid fell] table[x=x, y=y] {\stepgridtable};\fi
}
\begin{tikzpicture}[font=\scriptsize]
\begin{axis}[name=a, stepgrid, stepgrid axis vx=x, stepgrid axis vy=y, title={\textbf{(a)} $v_y$ vs.\ $v_x$ (m/s)}]
\stepgridplots{vx_vy}
\end{axis}
\begin{axis}[name=b, stepgrid, stepgrid axis vx=x, stepgrid axis wz=y, at={(a.north east)}, anchor=north west, xshift=\plotthirdgap, title={\textbf{(b)} $\omega_z$ (rad/s) vs.\ $v_x$ (m/s)}]
\stepgridplots{vx_wz}
\end{axis}
\begin{axis}[
    name=c, stepgrid, stepgrid axis vy=x, stepgrid axis wz=y, at={(b.north east)}, anchor=north west, xshift=\plotthirdgap, title={\textbf{(c)} $\omega_z$ (rad/s) vs.\ $v_y$ (m/s)},
    legend style={at={(1,1)}, anchor=north west, xshift=1.5mm, font=\scriptsize},
    legend image code/.code={\draw[#1, mark size=1.6pt] plot coordinates {(0.12cm,0)};},
    colorbar horizontal, colorbar shift/.style={xshift=1.5mm},
    colorbar style={
      at={(parent axis.south east)}, anchor=south west, width=\dimexpr\plotlegendcol-3mm\relax, height=2mm,
      axis line style=context, tick style=context, tick label style={font=\scriptsize},
      xtick={-1,1,3}, xticklabels={0.1,10,1000},
      title={Reference-motion data\\per cell (s)}, title style={font=\scriptsize, at={(0,1)}, anchor=south west, inner xsep=0pt, align=left}, every axis title shift=2pt,
    },
]
\addlegendimage{ours, only marks, mark=o, thick}
\addlegendimage{theirs, only marks, mark=o, thick}
\addlegendimage{black, only marks, mark=o, thick}
\stepgridplots{vy_wz}
\legend{RL better, Distillation better, Distillation fell}
\end{axis}
\end{tikzpicture}
```

**The policy with the RL-trained velocity encoder tracks step commands more accurately than the distillation baseline.** Each panel is a plane of the command space with the third component at zero, and each ring is one command. The outer disc's area is proportional to the larger of the two policies' relative steady-state errors in the step response to that command, and the hole's area to the smaller one; the color marks the better policy. Details in Appendix \ref{sec-velocity}.

:::