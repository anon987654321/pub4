# frozen_string_literal: true
# Programmatic fix script for DEPLOY shell scripts - no LLM needed
DEPLOY_ROOT = File.expand_path("DEPLOY", __dir__)
SHEBANG_ZSH = "#!/usr/bin/env zsh"

def strip_to_shebang(content)
  idx = content.index("#!")
  return [nil, false] unless idx
  [content[idx..], idx > 0]
end

def fix_file(path)
  content = File.read(path, encoding: "utf-8")
  original = content.dup
  changes = []

  # 1. Strip everything before first shebang
  result, stripped = strip_to_shebang(content)
  if result.nil?
    return "SKIP (no shebang found)"
  end
  if stripped
    content = result
    changes << "stripped leading garbage"
  end

  # 2. Strip trailing backtick fencing
  if content =~ /\n```\s*\z/m
    content = content.sub(/\n```\s*\z/m, "\n")
    changes << "stripped trailing fence"
  end

  # 3. Remove inline backtick fences
  if content =~ /^```/
    before_len = content.length
    content = content.gsub(/^```[a-z]*\n/, "").gsub(/^```\n/, "").gsub(/^```$/, "")
    changes << "stripped inline fences" if content.length != before_len
  end

  # 4. Fix wrong shebangs
  if content =~ /\A#!\/bin\/(bash|sh|ksh)/ || content =~ /\A#!\/usr\/bin\/env (bash|sh|ksh)/
    content = content.sub(/\A#!\/bin\/(bash|sh|ksh)/, SHEBANG_ZSH)
    content = content.sub(/\A#!\/usr\/bin\/env (bash|sh|ksh)/, SHEBANG_ZSH)
    changes << "fixed shebang to zsh"
  end

  # 5. Fix #!/usr/bin/envzsh (missing space)
  if content.include?("#!/usr/bin/envzsh")
    content = content.sub("#!/usr/bin/envzsh", SHEBANG_ZSH)
    changes << "fixed envzsh spacing"
  end

  # 6. Add emulate -L zsh if missing
  unless content.include?("emulate -L zsh")
    content = content.sub(/\A(#!.*\n)/, "\\1emulate -L zsh\n")
    changes << "added emulate -L zsh"
  end

  # 7. Fix set -euo pipefail -> setopt
  if content.include?("set -euo pipefail")
    content = content.gsub("set -euo pipefail", "setopt err_return no_unset pipe_fail")
    changes << "replaced set -euo pipefail"
  end
  content = content.gsub(/^set -e\s*$\n?/, "")
  content = content.gsub(/^set -u\s*$\n?/, "")

  # 8. sudo -> doas
  if content.include?("sudo ")
    content = content.gsub(/\bsudo\b/, "doas")
    changes << "sudo->doas"
  end

  # 9. systemctl -> rcctl
  if content.include?("systemctl")
    content = content.gsub(/\bsystemctl\s+enable\s+(\S+)\s+--now/, 'rcctl enable \1 && rcctl start \1')
    content = content.gsub(/\bsystemctl\s+enable\s+/, "rcctl enable ")
    content = content.gsub(/\bsystemctl\s+start\s+/, "rcctl start ")
    content = content.gsub(/\bsystemctl\s+stop\s+/, "rcctl stop ")
    content = content.gsub(/\bsystemctl\s+restart\s+/, "rcctl restart ")
    content = content.gsub(/\bsystemctl\s+status\s+/, "rcctl check ")
    content = content.gsub(/\bsystemctl\b/, "rcctl")
    changes << "systemctl->rcctl"
  end

  # 10. apt-get -> pkg_add
  if content =~ /\bapt-get\b|\bapt install\b/
    content = content.gsub(/\bapt-get\s+install\s+-y\s+/, "pkg_add ")
    content = content.gsub(/\bapt-get\s+update\s*&&\s*apt-get\s+install\s+-y\s+/, "pkg_add ")
    content = content.gsub(/\bapt-get\s+update\b/, "# pkg update not needed on OpenBSD")
    content = content.gsub(/\bapt\s+install\s+-y\s+/, "pkg_add ")
    changes << "apt->pkg_add"
  end

  # 11. pipe_failed -> pipe_fail
  if content.include?("pipe_failed")
    content = content.gsub("pipe_failed", "pipe_fail")
    changes << "fixed pipe_failed typo"
  end

  # 12. Add setopt if missing
  unless content.include?("setopt")
    content = content.sub(/(emulate -L zsh\n)/, "\\1setopt err_return no_unset pipe_fail extended_glob\n")
    changes << "added setopt"
  end

  return "clean" if changes.empty?
  return "no content change" if content == original

  File.write("#{path}.bak", original)
  File.write(path, content)
  "fixed [#{changes.join(', ')}] (#{original.lines.size} -> #{content.lines.size} lines)"
end

def fix_twitter_features(path)
  content = File.read(path)
  return "clean" unless content.start_with?("```ruby") || content.include?("class Retweet")
  File.write("#{path}.bak", content)
  new_content = <<~'ZSH'
    #!/usr/bin/env zsh
    emulate -L zsh
    setopt err_return no_unset pipe_fail extended_glob

    # Twitter/X features: Retweets, Hashtags, Mentions
    # Sourced by social deploy scripts

    log() { print "[$(date +'%Y-%m-%d %H:%M:%S')] $1" }

    setup_twitter_models() {
      log "Generating Twitter-style models"
      local models=(
        "Retweet user:references retweetable:references{polymorphic} comment:text"
        "Hashtag name:string:uniq"
        "Tagging taggable:references{polymorphic} hashtag:references"
        "Mention mentionable:references{polymorphic} mentioned_user:references{to_table:users}"
      )
      for model in "${models[@]}"; do
        local model_name="${model%% *}"
        [[ -f "app/models/${model_name:l}.rb" ]] && { log "Skipping $model_name (exists)"; continue }
        bundle exec rails generate model $model
      done
      bundle exec rails db:migrate
    }

    setup_twitter_models
  ZSH
  File.write(path, new_content)
  "replaced Ruby-in-sh with proper zsh (#{content.lines.size} -> #{new_content.lines.size} lines)"
end

def fix_features_base(path)
  content = File.read(path)
  return "clean" unless content.start_with?("```bash") || content.include?("BASH_SOURCE")
  File.write("#{path}.bak", content)
  new_content = <<~'ZSH'
    #!/usr/bin/env zsh
    emulate -L zsh
    setopt err_return no_unset pipe_fail extended_glob

    # Base generator functions for Rails apps
    RAILS_ROOT="${RAILS_ROOT:-$(pwd)}"
    STIMULUS_DIR="${STIMULUS_DIR:-app/javascript/controllers}"

    to_snake_case() {
      local name="$1"
      print "${(L)name}"
    }

    generate_model() {
      local model_name="$1"
      print "Generating model: $model_name"
      bundle exec rails generate model "$model_name"
    }

    generate_controller() {
      local name="${1%Controller}"
      print "Generating controller: $name"
      bundle exec rails generate controller "$name"
    }

    generate_stimulus() {
      local name="$1"
      local f="${STIMULUS_DIR}/${name:l}_controller.js"
      mkdir -p "$STIMULUS_DIR"
      [[ -f "$f" ]] && { print "Already exists: $f"; return 0 }
      cat > "$f" <<'EOF'
    import { Controller } from "@hotwired/stimulus"
    export default class extends Controller {
      connect() {}
    }
    EOF
      print "Created: $f"
    }
  ZSH
  File.write(path, new_content)
  "replaced mangled bash features_base with clean zsh (#{content.lines.size} -> #{new_content.lines.size} lines)"
end

def fix_brgen_dating(path)
  content = File.read(path)
  return "clean" if content.start_with?(SHEBANG_ZSH) && !content.include?("```")
  File.write("#{path}.bak", content)
  new_content = <<~'ZSH'
    #!/usr/bin/env zsh
    emulate -L zsh
    setopt err_return no_unset pipe_fail extended_glob

    # Brgen Dating - Location-based dating platform
    # OpenBSD 7.8, Rails 8, port 10002

    APP_NAME="brgen_dating"
    BASE_DIR="${BASE_DIR:-/home/brgen/app}"
    SERVER_IP="${SERVER_IP:-185.52.176.18}"
    APP_PORT=10002
    SCRIPT_DIR="${0:A:h}"

    source "${SCRIPT_DIR}/../@shared_functions.sh"

    check_app_exists "$APP_NAME" "app/models/match.rb" && exit 0

    log "Starting Brgen Dating setup"
    setup_full_app "$APP_NAME"

    command_exists "ruby"
    command_exists "node"
    command_exists "psql"

    install_gem "pagy"
    install_gem "faker"

    psql -c "SELECT postgis_version();" >/dev/null 2>&1 || {
      print "ERROR: PostGIS not installed" >&2
      exit 1
    }

    setup_authentication
    bin/rails generate model Match user:references matched_user:references{to_table:users} status:string score:float 2>/dev/null || true
    bin/rails generate model Profile user:references bio:text latitude:float longitude:float age:integer gender:string 2>/dev/null || true
    migrate_db

    log "Brgen Dating setup complete on port $APP_PORT"
  ZSH
  File.write(path, new_content)
  "reconstructed mangled brgen_dating.sh (#{content.lines.size} -> #{new_content.lines.size} lines)"
end

def fix_check_ports(path)
  content = File.read(path)
  return "clean" if content.start_with?(SHEBANG_ZSH)
  File.write("#{path}.bak", content)
  new_content = <<~'ZSH'
    #!/usr/bin/env zsh
    emulate -L zsh
    setopt err_return no_unset pipe_fail extended_glob

    # Port consistency checker for master.json
    SCRIPT_DIR="${0:A:h}"
    MASTER_JSON="${SCRIPT_DIR}/../master.json"

    [[ -f "$MASTER_JSON" ]] || { print "ERROR: master.json not found" >&2; exit 1 }

    print "=== Port Consistency Check ==="

    ruby -r json -e '
      data = JSON.parse(File.read(ARGV[0]))
      apps = data.fetch("apps", [])
      errors = []
      seen_ports = {}
      seen_names = {}
      apps.each do |app|
        name = app["name"]; port = app["port"]
        next if name.nil?
        errors << "Duplicate name: #{name}" if seen_names[name]
        seen_names[name] = true
        next if port.nil?
        p = port.to_i
        errors << "Invalid port #{p} for #{name}" unless p.between?(1, 65535)
        errors << "Duplicate port #{p}: #{seen_ports[p]} and #{name}" if seen_ports[p]
        seen_ports[p] = name
      end
      if errors.empty?
        puts "All checks passed (#{apps.size} apps)"
      else
        errors.each { |e| puts "ERROR: #{e}" }
        exit 1
      end
    ' "$MASTER_JSON"
  ZSH
  File.write(path, new_content)
  "replaced bash check_ports with clean zsh (#{content.lines.size} -> #{new_content.lines.size} lines)"
end

sh_files = Dir.glob(File.join(DEPLOY_ROOT, "**/*.sh")).sort
puts "Processing #{sh_files.size} .sh files in #{DEPLOY_ROOT}"
puts

sh_files.each do |path|
  rel = path.delete_prefix(DEPLOY_ROOT + "/")
  result = case rel
           when "rails/__shared/@twitter_features.sh" then fix_twitter_features(path)
           when "rails/__shared/@features_base.sh"    then fix_features_base(path)
           when "rails/brgen/brgen_dating.sh"         then fix_brgen_dating(path)
           when "rails/check_ports.sh"               then fix_check_ports(path)
           else fix_file(path)
           end
  puts "#{rel}: #{result}"
end

puts "\nDone. #{sh_files.size} files processed."
