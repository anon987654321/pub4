# Install system packages
pkg_add ruby py311-pip git

# Clone the repository
git clone https://github.com/awesome-llm-apps/mcp_ai_agents.git
cd mcp_ai_agents/notion_mcp_agent

# Install Ruby dependencies (isolated with bundler)
gem install bundler
bundle install --deployment

# Optional: install Python helpers for knowledge extraction
pip3 install -r requirements.txt
