cd "$BASE_DIR"

if ! command_exists redis-server; then
  echo "Redis is not installed. Installing..."
  doas pkg_add -U redis
  doas rcctl enable redis
  doas rcctl start redis
fi

commit_to_git "Configured Redis"

