# Clone the repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/llm_apps_with_memory_tutorials/ai_arxiv_agent_memory

# Install Ruby gems
bundle install --jobs=$(nproc) --quiet

# (Optional) Install the Ferrum‑based web UI bridge
# Required only if you want to run the demo UI.
yarn install --cwd web --silent
