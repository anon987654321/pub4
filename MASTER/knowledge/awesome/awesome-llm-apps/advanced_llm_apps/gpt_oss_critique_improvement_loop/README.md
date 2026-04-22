# 1️⃣ Clone this repository (skip if you already have a local copy)
git clone https://github.com/your-org/awesome-llm-apps.git
cd awesome-llm-apps/advanced_llm_apps/gpt_oss_critique_improvement_loop

# 2️⃣ Create a reproducible environment
python -m venv .venv
source .venv/bin/activate

# 3️⃣ Install exact dependencies
pip install -r requirements.txt

# 4️⃣ Export your OpenRouter key (or set MASTER_MODEL env var to another provider)
export OPENROUTER_API_KEY=your_key_here   # required for the default model
#   or
# export MASTER_MODEL=anthropic::claude-3-5-sonnet-20240620   # any RubyLLM‑compatible model

# 5️⃣ Run the improvement loop
#    The module’s `__main__` launches Master’s pipeline with the gpt_oss_critique_improvement_loop entrypoint.
python -m gpt_oss_critique_improvement_loop
