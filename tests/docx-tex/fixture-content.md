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

An explicitly sized symbol ![sized symbol](small.svg){width=12pt height=18pt} must retain its requested size.

A data URI symbol ![data symbol](data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI2cHQiIGhlaWdodD0iOXB0IiB2aWV3Qm94PSIwIDAgNiA5Ij48cGF0aCBmaWxsPSIjYzAwMDAwIiBkPSJNMyAwTDYgNUg0VjlIMlY1SDBaIi8+PC9zdmc+Cg==) must remain a vector too.

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

::: {.tex-render render-method="native"}
```{=latex}
\begin{tikzpicture}
\draw[fill=blue!10,draw=blue] (0,0) rectangle (2,0.8);
\node at (1,0.4) {SVG input};
\draw[->,thick] (2.1,0.4) -- (3,0.4);
\draw[fill=green!10,draw=green!50!black] (3.1,0) rectangle (5.1,0.8);
\node at (4.1,0.4) {Word vector};
\end{tikzpicture}
```
:::

$$
f(x)=\frac{x^2+1}{\sqrt{x+2}}
$$

# References {.unnumbered}

::: {#refs}
:::
