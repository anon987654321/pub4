git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git && \
cd awesome-llm-apps/chat_with_X_tutorials/chat_with_substack && \
bundle config set --local path .bundle && \
bundle install --quiet && \
export OPENROUTER_API_KEY=your_key_here && \
bin/rails server -e development -p 3000
