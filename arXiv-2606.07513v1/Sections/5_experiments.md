# 实验 {#sec-experiments}

## 实验设置 {#sec-exp-setup}

#### 世界数据

我们设计了三个具有不同社会设定的世界，以研究智能体在不同社会环境中的行为。每个世界包含 100 个独立设计的智能体，其背景、人格和初始社会关系各不相同。世界设计和角色创建的详细信息见 § \ref{sec-creation}。三个世界概述如下：

- **The Apartment（公寓）**：纽约市一栋共同居住的住宅楼，住着年轻职场人士、学生和艺术家。该场景强调陌生人如何在共享的居住空间中自然形成社区联系和人际关系。

- **Arcane Academy（奥术学院）**：一所魔法学院，学生和教职员工面对学业与人际交往方面的双重挑战。该场景强调复杂关系如何在结构化的学术机构中发展。

- **The Campus（校园）**：以中国高中为背景，聚焦现代教育环境中的师生互动，强调学校社交网络的形成与个人成长轨迹。该世界的模拟以中文运行。

#### 模拟

我们在三个世界中分别进行了持续 10 个模拟年的实验。每个模拟年由 $n_w$ 周组成，每周包含 $n_c$ 轮联系和 $n_d$ 个活动日。

#### 模型

我们使用 Qwen3.5-397B-A17B [@qwen35] 作为智能体及环境模型的主要模型。当模型无法生成有效输出时，我们退回使用 Gemini 3 Flash[^5_experiments-1] 重新生成。生成参数详见 § \ref{sec-config}。

#### 指标

我们追踪一组用于描述智能体行为和社会动态的分析指标，涵盖奖励、满足感、活动行为、联系行为、个人成长和计算成本。完整的指标定义见 § \ref{sec-appendix-metrics}。

## 长期社会模拟分析 {#sec-long-term-analysis}

#### 奖励分析

我们分析三个为期 10 年的模拟中三类奖励的分布及时间趋势（100 个智能体 $\times$ 10 年 $\times$ 3 个世界 = 3,000 个观测值）。图 \ref{fig-reward-distribution} 展示合并后的分布，颜色深浅代表智能体密度，三角形标记年度均值。各世界的详细结果见 § \ref{sec-appendix-reward-per-world}。

![三个世界合并后，10 个模拟年中三个奖励维度的分布。三角形标记年度均值。](Figures/reward_distribution_combined.png){#fig-reward-distribution width="100%"}

主观奖励和经济奖励平均而言都呈上升趋势，而社会奖励总体保持稳定，因为它基于智能体之间的相对排名，而非绝对表现。

#### 奖励—行为相关性

为了理解各个奖励维度受到哪些因素驱动，我们分别计算每个世界中行为指标与三类奖励之间的 Pearson 相关系数，再对各世界的系数取平均，得到合并值。图 \ref{fig-reward-behavior-correlation} 给出了完整的相关矩阵。

我们着重指出四项发现：(1) 总奖励与满足感维度、社会评价指标和 token 消耗的相关性最强，而惩罚表现出最强的负相关信号（$r = -0.50$）；(2) 社会奖励几乎只与声誉指标（受到尊重和受到喜爱，$r = 0.68$）相关，这符合其设计；它也与主动和被动联系次数（$r = 0.09$、$r = 0.15$）以及提出和参与的联合活动次数（$r = 0.15$、$r = 0.19$）相关，表明更多参与社会互动的智能体获得更高社会奖励；(3) 主观奖励按设计由四个满足感维度驱动——情绪（$r = 0.54$）、物质（$r = 0.73$）、社交（$r = 0.52$）和尊重（$r = 0.30$）——未得到满足的需求会触发惩罚（$r = -0.64$），大幅降低主观奖励；它也与联系、联合活动和消费等指标相关；(4) 经济奖励主要由存款积累（$r = 0.56$）和额外收入次数决定，技能则是间接的积极因素。详细分析见 § \ref{sec-appendix-reward-correlation}。附录还给出了朋友数量分布（§ \ref{sec-appendix-friend-distribution}）、社会网络可视化（§ \ref{sec-appendix-social-network}）、奖励间相关性（§ \ref{sec-appendix-reward-correlation-inter}）、财富不平等（§ \ref{sec-appendix-matthew-effect}）、奖励四分位群体画像（§ \ref{sec-appendix-reward-success-profile}）、进取型与悠闲型智能体画像（§ \ref{sec-appendix-ambition-profile}）、跨世界差异（§ \ref{sec-appendix-cross-world}）和模型比较（§ \ref{sec-appendix-model-comparison}）等分析。

![24 个指标与奖励维度之间的 Pearson 相关性热图。*合并（Combined）*列表示各世界数值的平均值。](Figures/reward_behavior_correlation.png){#fig-reward-behavior-correlation width="100%"}

## 通过生活奖励进行训练 {#sec-sft}

#### 训练

我们应用生活奖励训练（§ \ref{sec-training-data}），使用三个世界前四个模拟年的数据对 Qwen3.5-397B-A17B 进行微调。训练使用 30 个节点，每节点配备 8$\times$H100 80GB GPU，训练 1 个 epoch，学习率为 $1 \times 10^{-5}$。完整训练细节见 § \ref{sec-appendix-sft}。我们将微调后的模型称为 Qwen3.5-397B-Agentopia。

随后，我们在 **The Campus** 和 **The Apartment** 中分别进行 4 年模拟，对 Qwen3.5-397B-Agentopia 进行评估，并在相同世界配置下与原始 Qwen3.5-397B 基线进行比较。

#### 通过生活奖励学习可改善智能体在社会模拟中的表现

```{=latex}
\begin{table}[t]
\caption{
Qwen3.5-397B-Agentopia 与 Qwen3.5-397B 对比：在 \campus{} 和 \apartment{} 两个世界中，四个模拟年的跨世界平均指标。
Delta 表示四年平均值从 Qwen3.5-397B 到 Qwen3.5-397B-Agentopia 的百分比变化。}
\label{tab-sft-cross-world}
\centering
\small
\setlength{\tabcolsep}{3pt}
\begin{tabular}{l rrrr rrrr rrr}
\toprule
& \multicolumn{2}{c}{第1年} & \multicolumn{2}{c}{第2年} & \multicolumn{2}{c}{第3年} & \multicolumn{2}{c}{第4年} & \multicolumn{3}{c}{平均} \\
\cmidrule(lr){2-3} \cmidrule(lr){4-5} \cmidrule(lr){6-7} \cmidrule(lr){8-9} \cmidrule(lr){10-12}
指标 & 基线 & 微调 & 基线 & 微调 & 基线 & 微调 & 基线 & 微调 & 基线 & 微调 & 变化幅度 \\
\midrule
\multicolumn{12}{l}{\textit{奖励分量}} \\
经济奖励 & 1108 & 1271 & 1092 & 1130 & 1038 & 1006 & 1069 & 1008 & 1077 & 1104 & $\uparrow$\,2.5\% \\
主观奖励 & 46.0 & 46.7 & 50.1 & 48.4 & 51.5 & 52.6 & 51.9 & 55.3 & 49.9 & 50.8 & $\uparrow$\,1.8\% \\
\midrule
\multicolumn{12}{l}{\textit{社会评价}} \\
受到尊重 & 7.1 & 6.9 & 9.4 & 11.0 & 10.4 & 14.1 & 11.2 & 15.2 & 9.5 & 11.8 & $\uparrow$\,24.2\% \\
受到喜爱 & 5.2 & 5.1 & 6.9 & 7.5 & 7.4 & 9.3 & 8.1 & 9.9 & 6.9 & 8.0 & $\uparrow$\,15.9\% \\
相互尊重 & 5.2 & 5.1 & 7.3 & 7.9 & 8.1 & 9.9 & 8.3 & 10.1 & 7.2 & 8.3 & $\uparrow$\,15.3\% \\
相互喜爱 & 4.1 & 3.9 & 5.2 & 5.3 & 5.5 & 6.4 & 5.6 & 6.0 & 5.1 & 5.4 & $\uparrow$\,5.9\% \\
\midrule
\multicolumn{12}{l}{\textit{满足感}} \\
物质满足感 & 43.7 & 35.6 & 41.4 & 32.4 & 41.8 & 37.2 & 46.0 & 41.8 & 43.2 & 36.8 & $\downarrow$\,$-$14.8\% \\
情绪满足感 & 76.9 & 78.3 & 88.3 & 86.9 & 89.1 & 91.4 & 88.7 & 92.8 & 85.8 & 87.4 & $\uparrow$\,1.9\% \\
社交满足感 & 59.3 & 60.9 & 66.9 & 69.9 & 63.9 & 73.4 & 64.8 & 75.2 & 63.7 & 69.9 & $\uparrow$\,9.7\% \\
尊重满足感 & 42.3 & 44.1 & 44.0 & 44.4 & 43.8 & 46.4 & 43.6 & 47.2 & 43.4 & 45.5 & $\uparrow$\,4.8\% \\
\midrule
\multicolumn{12}{l}{\textit{活动模式}} \\
提出联合活动 & 6.1 & 6.0 & 6.6 & 5.8 & 6.3 & 6.1 & 6.8 & 6.9 & 6.5 & 6.2 & $\downarrow$\,$-$3.9\% \\
参与联合活动 & 12.3 & 12.2 & 13.3 & 11.7 & 12.7 & 12.3 & 13.8 & 14.0 & 13.0 & 12.6 & $\downarrow$\,$-$3.6\% \\
公共活动 & 12.1 & 11.2 & 9.1 & 9.5 & 8.2 & 8.7 & 5.4 & 7.9 & 8.7 & 9.3 & $\uparrow$\,7.1\% \\
单人活动 & 17.4 & 22.4 & 17.9 & 14.5 & 20.3 & 12.6 & 21.5 & 12.4 & 19.3 & 15.5 & $\downarrow$\,$-$19.8\% \\
技能进步次数 & 11.9 & 11.3 & 11.3 & 9.2 & 14.7 & 8.2 & 15.1 & 8.6 & 13.3 & 9.3 & $\downarrow$\,$-$29.6\% \\
\bottomrule
\end{tabular}
\end{table}
```

表 \ref{tab-sft-cross-world} 总结了跨世界平均指标，我们观察到：

1.  **奖励。** 经济奖励（+2.5%）和主观奖励（+1.8%）平均而言均得到提高，说明生活奖励训练有效改善了智能体在社会模拟中的整体福祉；

2.  **社会认可。** 由于社会奖励基于排名，当所有智能体均匀改善时，社会奖励不会发生变化。因此，我们改为考察社会评价指标（§ \ref{sec-appendix-metrics}），它们通过超过一定喜爱或尊重阈值的同伴数量来衡量绝对社会认可。结果显示，Qwen3.5-397B-Agentopia 智能体平均多获得 24.2% 的同伴尊重和 15.9% 的同伴喜爱，赢得更广泛的认可与更多友谊；

3.  **满足感。** 情绪、社交和尊重满足感均有提升，说明训练后的智能体更善于模拟人类需求及满足需求的行为。另一方面，物质满足感下降（$-$`<!-- -->`{=html}14.8%），因为经济奖励鼓励储蓄而非消费，反映了现实生活中消费与储蓄的权衡；

4.  **活动模式。** 公共活动参与增加（+7.1%），单人活动减少（$-$`<!-- -->`{=html}19.8%），技能进步次数明显下降（$-$`<!-- -->`{=html}29.6%）。这说明生活奖励会塑造智能体行为，引导其倾向于有奖励的行为模式，而没有奖励的行动可能被降低优先级。

每年趋势和各世界细分结果见 § \ref{sec-appendix-sft-trends}。

#### 生活奖励训练能够泛化至角色扮演能力

我们还在角色扮演基准 CoSER Test [@wang2025coser] 上评估 Qwen3.5-397B-Agentopia。该基准以经典文学情境为基础，评估 LLM 在给定情境下的表演能力，涵盖故事情节一致性、拟人化、角色忠实度和故事质量四个维度。我们使用 Qwen3-235B [@qwen3] 作为评判模型，将其与多种先进的开源和闭源模型进行比较（细节见 § \ref{sec-appendix-coser}）。如表 \ref{tab-coser-results} 所示，Qwen3.5-397B-Agentopia 相较于基线 Qwen3.5-397B 有显著提升，并超过 Claude-4.5-Sonnet，其中拟人化（+23.7%）和角色忠实度（+16.4%）提升尤为明显。这说明生活奖励训练不仅优化了 Agentopia 内部的智能体，也增强了通用的拟人化和角色扮演能力。

```{=latex}
\begin{table}[t]
\caption{
不同 LLM 在 CoSER Test 上的表现，由 Qwen3-235B 评判。
}
\label{tab-coser-results}
\centering
\small
\setlength{\tabcolsep}{3pt}
\begin{tabular}{l ccccccc}
\toprule
& \makecell{Claude\\4.5-Opus} & \makecell{Gemini\\3-Pro} & \makecell{Qwen3.5\\397B-Agentopia} & \makecell{Claude\\4.5-Sonnet} & \makecell{Qwen3.5\\397B} & \makecell{CoSER\\70B} & \makecell{GPT-5\\Mini} \\
\midrule
故事情节一致性 & 63.74 & 65.95 & 41.02 & 47.18 & 39.60 & 35.05 & 38.10 \\
拟人化             & 64.28 & 60.42 & 49.67 & 36.02 & 40.16 & 31.16 & 24.60 \\
角色忠实度    & 58.45 & 58.34 & 46.93 & 47.55 & 40.32 & 32.28 & 27.20 \\
故事质量     & 63.24 & 62.49 & 59.01 & 50.09 & 49.97 & 45.33 & 42.00 \\
\midrule
平均值               & 62.43 & 61.80 & 49.16 & 45.21 & 42.51 & 35.95 & 32.97 \\
\bottomrule
\end{tabular}
\end{table}
```

## 计算成本 {#sec-cost}

```{=latex}
\begin{table}[t]
\centering
\caption{三个模拟世界的总体开销。
每个世界的 100 个智能体运行 10 个模拟年。
M = 百万 token，K = 千次调用，h = 实际经过的小时数。}
\label{tab-cost-overall}
\small
\begin{tabular}{l rrrrr}
\toprule
\textbf{世界} & 输入（M） & 输出（M） & Token（M） & 调用（K） & 时间（h） \\
\midrule
\campus{}       & 19,041 & 425 & 19,466 & 544 & 201.3 \\
\academy{}      & 11,302 & 315 & 11,617 & 572 & 174.2 \\
\apartment{}    &  9,699 & 317 & 10,016 & 584 & 183.2 \\
\midrule
\textbf{平均值} & 13,347 & 352 & 13,700 & 567 & 186.2 \\
\bottomrule
\end{tabular}
\end{table}
```

![三个世界平均后的 10 个模拟年中每周计算开销趋势。虚线表示线性趋势拟合。](Figures/cost_trend.pdf){#fig-cost-trend width="100%"}

我们在每次模拟运行中部署三个 Qwen3.5-397B FP8 实例。表 \ref{tab-cost-overall} 总结了每个世界中模拟 100 个智能体、持续 10 年的总体成本，图 \ref{fig-cost-trend} 展示三个世界平均后的每周开销趋势。

平均而言，一次 10 年模拟消耗 137 亿 token、执行 56.7 万次 LLM 调用，实际运行时间约 186 小时。输入 token 占主要成本，平均每周 1.33 亿，而输出 token 仅约 350 万，反映出每个智能体的人格设定和记忆需要庞大的上下文。随着智能体累积记忆、上下文不断增长，输入 token 数量与运行时间都稳步增加；在 10 年期间，每周运行时间从约 80 分钟上升到 140 分钟。这表明记忆增长是长时域社会模拟的主要计算瓶颈，有效的上下文与记忆管理策略至关重要。各世界的详细结果见 § \ref{sec-appendix-cost}。

[^5_experiments-1]: <https://ai.google.dev/gemini-api/docs/models/gemini-3-flash-preview>
