# AI DataVisualization Agent

## Tutorial
[Build an AI data visualization agent](https://www.theunwindai.com/p/build-an-ai-data-visualization-agent) with a complete step‑by‑step guide, code walkthroughs, and best practices.

A Streamlit app that visualizes uploaded datasets on request. Users upload a dataset, ask a question, and receive a chart, statistics, and explanation.

## Features
- Analyze data with natural language questions.
- Generate appropriate visualizations automatically.
- Provide explanations of findings.
- Support multi‑model inference with DeepSeek V3, Llama 3.1 405B, Qwen 2.5 7B, and Llama 3.3 70B.

## Requirements
- Together AI API key: https://api.together.ai/signin
- E2B API key: https://e2b.dev/docs/legacy/getting-started/api-key

## Setup
```bashgit clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd ai_agent_tutorials/ai_data_visualisation_agent
pip install -r requirements.txt
streamlit run ai_data_visualisation_agent.py
```