# Conclusion {#sec-conclusion}

This paper studies long-term life simulation and LLM learning in agent societies. We present Agentopia, a multi-agent society where agents live their own lives. We define life reward to model agents' well-being, and propose life reward training, a rejection-sampling-based method that selects high-advantage agent trajectories to optimize LLMs.

We conduct simulations across three diverse worlds, each with 100 agents running for 10 simulated years. Agents exhibit diverse emergent behaviors, including personal growth, relationship formation, and life choices. Life reward training leads to improved well-being in simulation, including broader social recognition, higher subjective fulfillment, and better economic gains. Through evaluation on downstream role-playing benchmarks, we validate that life reward training improves LLMs' anthropomorphism and role-playing ability, yielding a 15.6% overall improvement on CoSER Test, with the largest increases in anthropomorphism (+23.7%) and character fidelity (+16.4%).

# Limitations {#limitations .unnumbered}

In this paper, we present Agentopia, a comprehensive framework for agent social life simulation that models a wide range of human social behaviors. As an agent environment, its complexity goes beyond existing simulation systems. However, building a agent system that comprehensively simulates human social life is extremely challenging, and our system has room for improvement in several aspects.

#### Turn-based design

Our system is built on turn-based LLM generation, which fundamentally differs from real-time human perception and reaction. As discussed in § \ref{sec-appendix-design-philosophy}, real-time perception would consume prohibitive computation on low-level operations, drastically reducing the density of social interactions and making long-term simulation infeasible.

#### Hallucination

Human behaviors are naturally grounded by the physical world, but LLM-powered agents operate through text generation with few constraints, making them susceptible to hallucination, such as fabricating non-existent characters or locations. Agentopia mitigate this through the context management and the location system (§ \ref{sec-appendix-location}), and employ principle verification to filter hallucinated outputs (§ \ref{sec-appendix-principles}), but fully eliminating hallucination remains an open challenge.

#### Environment and numeric systems

Agentopia's environment includes predefined numeric systems and a generative environment engine, but fully aligning them with real-world societies is extremely difficult. It is challenging for the environment model to produce responses that perfectly mirror real-world outcomes, and the numeric mechanisms governing agent states are difficult to align with human behavioral and physiological patterns.

#### Optimization and alignment

While training with life reward yields notable improvements, two alignment gaps remain. First, we cannot ensure that the life reward objective fully aligns with human well-being. The simulated environment cannot fully reproduce the complexity of real-world societies. Moreover, the reward signals themselves (*e.g.*, subjective fulfillment) are difficult to fully align with human physiological and cognitive mechanisms. Second, Agentopia is fundamentally a society of agents rather than a human society: all feedback an agent receives comes from other AI models, not from humans, leaving it an open question whether the trained LLMs can align with human cognitive and psychological patterns.

#### Computational constraints

Life simulation in Agentopia is computationally expensive, and our limited resources prevent us from conducting more comprehensive experiments. For example, we did not conduct simulations with more worlds, more agents, or longer time horizons, nor trained on different model families. Also, for trajectory selection, we selected all generations from the chosen year and agent, without exploring fine-grained credit assignment strategies that attribute reward to specific responses. We hope to address these with more computational resources in future work.

# Impact Statement {#impact-statement .unnumbered}

Agentopia aims to advance research in agent society simulation and LLM-based role-playing. All characters and worlds in our simulations are fictional and do not represent real individuals or groups. Our methods could potentially be applied to simulate real-world individuals, and such applications must strictly respect privacy regulations and obtain necessary consent.
