| Id | Agentic AI pattern | Description | Where to use | Agentforce support | 
| --- | ------ | ---------------- | ------ | --------- |
| C1 | Prompt Chaining | Breaks down complex tasks into a sequence of smaller, focused steps, with the output of each step serving the input as the next step | For complex tasks, which can be broken down in steps under strict rules and orders | Natively support through deterministic agentic workflow and the usage of variables |
| C2 | Routing | Help achieve dynamic decision-making and govern the flow of control to different specialized functions, tools | For use cases that an agent must decide between multiple sub-agents, tools and workflow based on the user input  | Natively support through agent Router and Single Org Multiple Agents support (SOMA) |
| C3 | Parallelization | Executing multiple components, e.g. LLM calls, tool usages or even entire sub-agents, concurrently | To execute complex workflow contains multiple independent operations | Not support | | 
| C4 | Reflection | Agent evaluating its own work, output, or internal state and using that evaluation to improve its performance or refine its response| For solutions when quality accuracy are more important than speed & costs |  Custom built generator agent and critic agent collaborate under the guidance of an orchestrator agent | |
| C5 | Tool Use | Pattern that allows the LLM to decide when and how to use a specfic external function | For use cases that an agent need to interact with the outside world and deliver beyond the native capabilities of an LLM | Natively support through flow, Apex and prompt template |
| C6 | Planning | The ability for an agent or agents to formulate a sequence of actions to move from an initial state towards a target state | Use when the user request is too complex to be handled by a single step | Not natively supported |
| C7 | Multi-agent Collaboration | Systems where multiple independent or semi-independent agents work together to achieve a common goal | Use when agent needed for the e2e solutions exist either inside the same agentic AI platform or outside in a different AI platform | Natively support with caveat |
| C8.1 | Memory - short term memory | For agent to retain recent messages, agent reply, tool usages from current interaction, all within one LLM context window | Use when multi-turn conversation is expected between human users and the AI agents | Native support | Variables |
| C8.2 | Memory - long term memory | For agent to retain information across multiple interactions | Use when an agent is expected to learn or adapt based on past successes, failtures, or newly acquired information | Custom build |
| C9 | Learning and Adoption | Agents adapt by changing strategy, understanding, or goals based on learning | Use this pattern for solutions require personalisation, continous performance improvement, and the ability to handle novel situations antonomously| Custom build |
| C10 | Model Context Protocol | Standard protocol for LLM to interface with exteranl environments | | Natively support | MCP registry | |
| C11 | Goal Setting and Monitoring | | | | | |
| C12 | Exception Handling and Recovering | | | | | |
| C13 | Human in the Loop | | | Natively support | | |
| C14 | Knowledge Retrieval (RAG) | | | Natively support (with Caveat) | | |
| C15 | Inter-agent communication (A2A) | | | | Not support | |
| C16 | Resource Aware Optimization | Agents dynamically monitors and
manages computational, temporal, and financial resources during operation. | | | Not supported | |