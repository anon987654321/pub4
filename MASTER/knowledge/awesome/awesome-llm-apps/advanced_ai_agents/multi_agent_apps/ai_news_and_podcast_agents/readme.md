# Clone the repository containing the multi‑agent example
git clone https://github.com/arun477/beifong.git
cd beifong

# Install Ruby dependencies (use OpenBSD's ruby‑bundler)
bundle config set --local path vendor/bundle
bundle install

# Run the pipeline (defaults to deepseek‑v3 on OpenRouter)
bundle exec ruby lib/master/cli.rb run \
  --agent=ai_news_and_podcast \
  --output=episodes/latest_episode.wav
