# frozen_string_literal: true

BASE = "/home/dev/pub4/MASTER"

# --- 1. Delete dead files ---
dead_files = %w[
  chrome.core
  governance.yml
  data/features.yml
  lib/master/cognitive_monitor.rb
  lib/master/introspection/friction.rb
  lib/master/quality/auto_testing.rb
  lib/master/state/experience.rb
  lib/master/tools/apply_diff.rb
]

dead_files.each do |f|
  path = File.join(BASE, f)
  if File.exist?(path)
    size = File.size(path)
    File.delete(path)
    puts "deleted: #{f} (#{size} bytes)"
  else
    puts "skip: #{f} (not found)"
  end
end

# Clean empty dirs left behind
%w[lib/master/introspection lib/master/quality lib/master/state].each do |d|
  path = File.join(BASE, d)
  if Dir.exist?(path) && Dir.empty?(path)
    Dir.rmdir(path)
    puts "rmdir: #{d}"
  end
end

# --- 2. Merge fallback_models.yml into models.yml ---
fb_path = File.join(BASE, "data/fallback_models.yml")
if File.exist?(fb_path)
  fb_content = File.read(fb_path)
  models_path = File.join(BASE, "data/models.yml")
  models_content = File.read(models_path)
  unless models_content.include?("# Merged from fallback_models.yml")
    models_content += "\n# Merged from fallback_models.yml\n#{fb_content}\n"
    File.write(models_path, models_content)
    File.delete(fb_path)
    puts "merged: fallback_models.yml into models.yml"
  end
end

# --- 3. Extract shared resolve(path) into Tools::PathGuard ---
guard_path = File.join(BASE, "lib/master/tools/path_guard.rb")
unless File.exist?(guard_path)
  File.write(guard_path, <<~'RB')
    # frozen_string_literal: true

    module Master
      module Tools
        module PathGuard
          def resolve(path)
            full = File.expand_path(path, @root)
            return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)
            Result.ok(full)
          end
        end
      end
    end
  RB
  puts "created: lib/master/tools/path_guard.rb"
end

# Update read_file.rb, write_file.rb, str_replace.rb to use PathGuard
%w[read_file write_file str_replace].each do |tool|
  path = File.join(BASE, "lib/master/tools/#{tool}.rb")
  next unless File.exist?(path)
  content = File.read(path)

  # Add include if not already there
  if content.include?("def resolve(path)") && !content.include?("PathGuard")
    # Remove the duplicate resolve method
    content.gsub!(/\n\s*def resolve\(path\)\n.*?end\n/m, "\n")
    # Add include after class line
    content.sub!(/(class \w+ < (?:Base|Tool))/) { "#{$1}\n        include PathGuard" }
    File.write(path, content)
    puts "patched: #{tool}.rb (uses PathGuard)"
  else
    puts "skip: #{tool}.rb (already patched or no resolve method)"
  end
end

# --- 4. Fix double frozen_string_literal in git_operations.rb ---
git_ops = File.join(BASE, "lib/master/git_operations.rb")
if File.exist?(git_ops)
  content = File.read(git_ops)
  lines = content.lines
  # Remove duplicate frozen_string_literal and require lines
  seen_frozen = false
  seen_open3 = false
  cleaned = lines.reject do |l|
    if l.strip == '# frozen_string_literal: true'
      if seen_frozen
        true
      else
        seen_frozen = true
        false
      end
    elsif l.strip == 'require "open3"'
      if seen_open3
        true
      else
        seen_open3 = true
        false
      end
    else
      false
    end
  end
  if cleaned.length < lines.length
    File.write(git_ops, cleaned.join)
    puts "fixed: git_operations.rb (removed duplicates)"
  end
end

# --- 5. Fix duplicate MIN_API_KEY_LENGTH ---
agent_path = File.join(BASE, "lib/master/agent.rb")
if File.exist?(agent_path)
  content = File.read(agent_path)
  if content.include?("MIN_API_KEY_LENGTH = 20") && !content.include?("Master::MIN_API_KEY_LENGTH")
    content.sub!(/    MIN_API_KEY_LENGTH\s*=\s*20/, "    MIN_API_KEY_LENGTH = Master::MIN_API_KEY_LENGTH")
    File.write(agent_path, content)
    puts "fixed: agent.rb MIN_API_KEY_LENGTH references Master constant"
  end
end

# --- 6. Move audit.log path from data/ to .master/ ---
audit_path = File.join(BASE, "data/audit.log")
if File.exist?(audit_path)
  target = File.join(BASE, ".master/audit.log")
  File.rename(audit_path, target)
  puts "moved: data/audit.log -> .master/audit.log"
end

# Check if audit_log.rb references data/audit.log and fix it
Dir.glob(File.join(BASE, "lib/**/*.rb")).each do |f|
  content = File.read(f)
  if content.include?('"data/audit.log"') || content.include?("'data/audit.log'")
    content.gsub!(/(['"])data\/audit\.log\1/, '".master/audit.log"')
    File.write(f, content)
    puts "fixed: #{f.sub(BASE + '/', '')} (audit.log path)"
  end
end

# --- 7. Add chrome.core to .gitignore ---
gitignore = File.join(BASE, ".gitignore")
if File.exist?(gitignore)
  content = File.read(gitignore)
  unless content.include?("*.core")
    File.write(gitignore, content.rstrip + "\n*.core\n")
    puts "updated: .gitignore (added *.core)"
  end
else
  File.write(gitignore, "*.core\n")
  puts "created: .gitignore"
end

puts "\ndone."
