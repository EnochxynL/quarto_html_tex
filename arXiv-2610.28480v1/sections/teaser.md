::: {#fig-teaser width="100%" fig-pos="H"}

```{=latex}
\centering
\begin{minipage}[c]{0.65\textwidth}
  \centering
  \begin{tikzpicture}
    \node[inner sep=0pt] (timg)
      {\includegraphics[width=\linewidth, trim={150 75 120 125}, clip]{teaser.png}};
    \node[font=\large\bfseries, inner sep=3pt, fill=BerkeleyBlue,
          path fading=wmrfade, rounded corners=2pt, text=white]
      at (timg.center) {World-Model Rollout};
  \end{tikzpicture}
\end{minipage}
\tikz[baseline=0pt]\draw[separator] (0,-1.8) -- (0,1.8);
\begin{minipage}[c]{0.3\textwidth}
  \begin{tikzpicture}[font=\small]
    \pgfmathsetlengthmacro{\cellsz}{1.3*\linewidth/8}
    \pgfmathsetlengthmacro{\cellp}{(\linewidth-\cellsz-4pt)/31}
    \pgfmathsetlengthmacro{\cellpY}{1.12*\cellsz}
    \foreach \r in {0,...,3}
      \foreach \c in {31,30,...,0}
        \node[inner sep=0pt] (s-\r-\c) at (\c*\cellp,\r*\cellpY) {\includegraphics[width=\cellsz]{gpu_icon.pdf}};
    \node[draw=gray!70, thick, rounded corners=2pt, inner sep=1pt,
          fit=(s-0-0)(s-3-31)] (sonicbox) {};
    \node[above=1mm of sonicbox, font=\large\bfseries, inner sep=0pt] {$>1000\times$ fewer GPU-h};
    \node[font=\footnotesize, inner sep=3pt, fill=white, fill opacity=0.8,
          rounded corners=2pt] at (sonicbox.center)
      {128 L40 GPUs, \qty{168}{\hour}~\cite{luo2025sonic}};
    \matrix[below=2pt of sonicbox.south east, anchor=north east, inner sep=0pt, column sep=.3333em] {
      \node[anchor=center] (sm) {\includegraphics[width=\cellsz]{gpu_icon.pdf}}; &
      \node[anchor=center, font=\footnotesize, retcol] {1 H100 GPU, \qty{3}{\hour}}; \\
    };
    \draw[-{Latex[length=2.5mm]}, thick, gray!70, rounded corners=2pt]
      (s-0-0 |- sonicbox.south) |- (sm.west);
  \end{tikzpicture}
\end{minipage}
```

**A learned differentiable world model trains a humanoid whole-body controller and reduces GPU-hours by more than $1000\times$ versus cluster-scale model-free reinforcement learning (§\ref{sec-scaling}).** Left: the policy improves through imagined rollouts of the world model. Right: 128 L40 GPUs train for 168 h in SONIC [@luo2025sonic], against one H100 for 3 h in this work.

:::