#!/usr/bin/env zsh
set -euo pipefail
# Route helpers - from @route_helpers.sh and @common.sh
# Pure zsh route manipulation per master.yml v70.0.0
add_routes_block() {
    local routes_block="$1"
    local routes_file="config/routes.rb"
    # Read all lines, remove last 'end', append routes, add 'end'
    local routes_lines=("${(@f)$(<$routes_file)}")
    {
        print -l "${routes_lines[1,-2]}"
        print -r -- "$routes_block"
        print "end"
    } > "$routes_file"
}
commit() {
    local message="${1:-Update application setup}"
    log "Committing changes: $message"
    # Only commit if in git repository
    if [ -d ".git" ]; then
        git add -A
        git commit -m "$message" || log "Nothing to commit"
    else
        log "Not a git repository, skipping commit"
    fi
}
migrate_db() {
    log "Migrating database"
    bin/rails db:create db:migrate
}
setup_seeds() {
    log "Setting up database seeds"
    if [ ! -f "db/seeds.rb" ] || [ ! -s "db/seeds.rb" ]; then
        cat > db/seeds.rb << EOF
# Seeds for ${APP_NAME}
# Create sample data for development
if Rails.env.development?
  # Add sample data creation here
  puts "Created sample data for #{Rails.env} environment"
end
EOF
    fi
}
