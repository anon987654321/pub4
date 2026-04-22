# Clone the repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/advanced_llm_apps/chat_with_X_tutorials/chat_with_gmail

# Install Ruby dependencies
bundle install

# Create a Google Cloud project and enable the Gmail API
# https://console.cloud.google.com/apis/library/gmail.googleapis.com
# Generate OAuth client credentials (client_id & client_secret)

# Save credentials in a .env file (dotenv gem is used by the app)
cat > .env <<EOF
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_client_secret
GOOGLE_REDIRECT_URI=http://localhost:4567/oauth2callback
MASTER_LLM_PROVIDER=deepseek
MASTER_LLM_MODEL=deepseek-ai/deepseek-v3
MASTER_LLM_API_KEY=your_openrouter_key
EOF
