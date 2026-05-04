# Ensure this script is run by ksh
[ -z "$KSH_VERSION" ] && return

# Initialize PATH with common directories
PATH=$HOME/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/X11R6/bin:/usr/local/bin:/usr/local/sbin
export PATH

# Function to add a directory to PATH if it's not already included
add_to_path() {
  if ! echo "$PATH" | /usr/bin/grep -qE "(^|:)$1($|:)"; then
    PATH="$1:$PATH"
  fi
}

# Add custom paths
add_to_path "/home/dev/.local/share/gem/ruby/3.3/bin"
add_to_path "/home/dev/.gem/ruby/3.3/bin"
add_to_path "/usr/local/lib/ruby/gems/3.3/bin"

# Export PATH and other environment variables
export PATH

# API keys and credentials
export OPENAI_API_KEY=""
export NLPCLOUD_API_KEY=""
export REPLICATE_API_KEY=""
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export WEAVIATE_API_KEY=""
export WEAVIATE_URL="awsv1gydqwegeotsyoo8g.c0.europe-west2.gcp.weaviate.cloud"

# Custom aliases
alias rs="bin/rails server -b 46.23.95.45 -p 6969"
alias zap="zap -f"
