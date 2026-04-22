# Clone the tutorial repo
git clone https://github.com/yourname/ai_blog_search.git
cd ai_blog_search

# Install dependencies (Ruby 3.3+, bundler)
bundle install

# Set your OpenRouter API key
export OPENROUTER_API_KEY=sk_...

# Run the interactive CLI
bin/ai_blog_search ask "What are the latest trends in LLM security?"
