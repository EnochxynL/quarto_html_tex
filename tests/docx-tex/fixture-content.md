First parent citation [@parent-first].

::: {.callout-note}
This native Quarto block must produce valid singleton paragraph properties.
:::

```{=latex}
\begin{table}
\caption{Nested editable content and a block-only citation}
\label{tab-regression}
\begin{tabular}{ll}
\toprule
Item & Result \\
\midrule
Nested & \begin{tabular}{l}offline diffusion\\finite differences\end{tabular} \\
Block source & \cite{block-only} \\
Unicode code & \texttt{决策} \\
\bottomrule
\end{tabular}
\end{table}
```

Last parent citation [@parent-last]. Table \ref{tab-regression} is editable.

An inline symbol ![small symbol](small.svg) must retain its physical size.

```{=latex}
\begin{algorithm}
\caption{Executable source, editable result}
\begin{algorithmic}[1]
\State Initialize $x \gets 0$
\For{$i=1,2$}
\State $x \gets x+i$
\EndFor
\State \Return $x$
\end{algorithmic}
\end{algorithm}
```

$$
f(x)=\frac{x^2+1}{\sqrt{x+2}}
$$

# References {.unnumbered}

::: {#refs}
:::
