# 相关工作 {#sec-related}

#### 基于智能体的社会模拟

近年来，研究者探索了使用 LLM 驱动的智能体进行社会模拟。Generative Agents [@park2023generative] 开创了这一方向：它模拟了一个由 25 个智能体组成、持续两天的社会，并观察到组织聚会等涌现性社会行为。Humanoid Agents [@wang2023humanoid] 在此基础上引入受马斯洛需求层次理论 [@maslow1943theory] 启发的人类需求。Project Sid [@altera2024projectsid] 将智能体置于成熟的数字游戏环境 *Minecraft* 中，展现了涌现的专业分工、集体规则形成和文化传承。BookWorld [@ran-etal-2025-bookworld] 基于虚构文学作品构建多智能体系统，通过角色互动生成故事。Aivilization [@fan2026aivilization] 设计了游戏环境，模拟智能体的生产和经济行为。CAMEL [@li2024camel] 研究角色扮演多智能体系统在数学和编程任务中的协作式问题求解。然而，Aivilization 等现有系统在支持长期生活模拟方面存在局限：大多数 LLM 调用被用于*底层操作*，即虚拟环境中的“物理”互动（*例如*捡起瓶子、在不同地点之间移动），而不是智能体之间的长期社会互动。表 \ref{tab-simulation-comparison} 从关键维度对这些系统进行了系统比较。

```{=latex}
\begin{table*}[h]
\centering
\small
\setlength{\tabcolsep}{4pt}
\caption{\method 与现有智能体社会系统的比较。
“时间尺度”指单次模拟运行所涵盖的时间范围。
“环境反馈”表示环境反馈是基于规则还是由 LLM 生成。
“经济系统”表示系统是否包含物品和经济机制。
“职业系统”表示智能体能否随时间选择或更换职业。
“群体互动”表示系统是否支持超过两个智能体之间的互动。
Project Sid 的数据来自其论文第 4.2 节。
}
\label{tab-simulation-comparison}
\resizebox{\textwidth}{!}{
\begin{tabular}{lcccccc}
\toprule
& \textbf{Gen.\ Agents} & \textbf{Humanoid} & \textbf{Project Sid} & \textbf{BookWorld} & \textbf{Aivilization} & \textbf{Agentopia} \\
& \citep{park2023generative} & \citep{wang2023humanoid} & \citep{altera2024projectsid} & \citep{ran-etal-2025-bookworld} & \citep{fan2026aivilization} & （本文） \\
\midrule
时间尺度      & 天   & 天   & 天  & --- & 周  & 年  \\
智能体数量       & 25     & ---    & 50 & ---   & ${\sim}$10,000     & 100    \\
动作空间    & 预定义 & 预定义 & 预定义 & 自由形式 & 预定义 & 自由形式 \\
环境反馈        & 规则 & 规则 & 规则 & LLM & 规则 & LLM \\
记忆          & 检索式     & 检索式 & 检索式 & 检索式  & 固定草稿区 & 基于文件 \\
技能成长    & \xmark & \xmark & \xmark & \xmark & \cmark & \cmark \\
经济系统     & \xmark & \xmark & \cmark & \xmark & \cmark & \cmark \\
职业系统     & \xmark & \xmark & \cmark & \xmark & \cmark & \cmark \\
群体互动  & \cmark & \xmark & \cmark & \cmark & \xmark & \cmark \\
奖励  & \xmark & \xmark & \xmark & \xmark & \cmark & \cmark \\
训练       & \xmark & \xmark & \xmark & \xmark & \xmark & \cmark \\
\bottomrule
\end{tabular}
}
\end{table*}
```

#### 人格模拟与 LLM 角色扮演

这一研究方向旨在提高 LLM 的拟人化能力和角色扮演能力 [@chen2024from]。@shanahan2023role 认为，LLM 本质上就在进行角色扮演，无论是充当通用助手还是扮演特定角色。@wang2025coser 提出，通过多样化角色进行训练，LLM 能够泛化其拟人化能力，从而将人格模拟与角色扮演研究联系起来。既有研究主要关注数据、评估和优化三个方面。在数据方面，Character-LLM [@shao2023character] 和 RoleLLM [@wang2023rolellm] 使用 LLM 合成针对特定角色的问答数据。CoSER [@wang2025coser] 从文学语料中提取真实的角色数据，形成大规模、高质量的角色扮演数据集。在评估方面，既有研究主要使用 LLM 评判器 [@wang2023rolellm; @tu2024charactereval]，并引入符合人类偏好的评分标准 [@wang2025coser; @du2026her]。此外，RoleEval [@shen2023roleeval]、InCharacter [@wang2024incharacter] 和 LifeChoice [@xu2024character] 分别从知识、人格和决策角度对 LLM 进行客观评估。在优化方面，先前研究使用人类数据 [@wang2025coser; @zhou2023characterglm] 或合成数据 [@chan2024personahub; @lu2024large] 进行监督微调。CogDual [@liu-etal-2025-cogdual]、CPO [@ye-etal-2025-cpo] 和 HER [@du2026her] 探索将强化学习用于角色扮演，其中的关键挑战仍是获取高质量且与人类价值对齐的奖励信号。此外，Persona Vector [@chen2025persona]、Assistant Axis [@lu2026assistant] 和 Emotion Concepts [@sofroniew2026emotion] 探索了 LLM 内部人格与情感的机制，并提出检测和操控这些机制的方法。
