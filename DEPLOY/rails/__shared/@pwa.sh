cd "$BASE_DIR"

# Run the PWA generator
bin/rails generate pwa:install

# Stage changes and commit them
commit_to_git "Configured Rails to run as a Progressive Web App (PWA)"

