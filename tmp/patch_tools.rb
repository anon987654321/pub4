# encoding: utf-8
# frozen_string_literal: true

BASE = "/home/dev/pub4/MASTER"

# Patch tools to use PathGuard instead of inline resolve
%w[read_file write_file str_replace].each do |tool|
  path = File.join(BASE, "lib/master/tools/#{tool}.rb")
  next unless File.exist?(path)
  content = File.read(path, encoding: "utf-8")
  lines = content.lines

  # Find and remove the resolve method
  in_resolve = false
  resolve_start = nil
  resolve_end = nil
  indent = nil

  lines.each_with_index do |line, i|
    if line =~ /^(\s*)def resolve\(path\)/
      in_resolve = true
      resolve_start = i
      indent = $1
    elsif in_resolve && line =~ /^#{indent}end/
      resolve_end = i
      break
    end
  end

  next unless resolve_start && resolve_end

  # Remove resolve method lines
  new_lines = lines[0...resolve_start] + lines[(resolve_end + 1)..]

  # Add include PathGuard after the class definition line
  new_content = new_lines.join
  if !new_content.include?("PathGuard")
    new_content.sub!(/^(\s*class \w+.*$)/) { "#{$1}\n        include PathGuard" }
  end

  File.write(path, new_content)
  puts "patched: #{tool}.rb"
end

# Fix git_operations.rb duplicates
git_ops = File.join(BASE, "lib/master/git_operations.rb")
if File.exist?(git_ops)
  content = File.read(git_ops, encoding: "utf-8")
  lines = content.lines
  seen = {}
  cleaned = lines.reject do |l|
    key = l.strip
    if key == "# frozen_string_literal: true" || key == 'require "open3"'
      if seen[key]
        true
      else
        seen[key] = true
        false
      end
    else
      false
    end
  end
  if cleaned.length < lines.length
    File.write(git_ops, cleaned.join)
    puts "fixed: git_operations.rb"
  end
end

# Fix agent.rb MIN_API_KEY_LENGTH
agent_path = File.join(BASE, "lib/master/agent.rb")
content = File.read(agent_path, encoding: "utf-8")
if content.include?("MIN_API_KEY_LENGTH = 20")
  content.sub!("MIN_API_KEY_LENGTH              = 20", "MIN_API_KEY_LENGTH = Master::MIN_API_KEY_LENGTH")
  File.write(agent_path, content)
  puts "fixed: agent.rb MIN_API_KEY_LENGTH"
end

# Move audit.log
audit_src = File.join(BASE, "data/audit.log")
audit_dst = File.join(BASE, ".master/audit.log")
if File.exist?(audit_src)
  File.rename(audit_src, audit_dst)
  puts "moved: audit.log to .master/"
end

# Fix audit.log path references
Dir.glob(File.join(BASE, "lib/**/*.rb")).each do |f|
  content = File.read(f, encoding: "utf-8")
  if content.include?("data/audit.log")
    content.gsub!("data/audit.log", ".master/audit.log")
    File.write(f, content)
    puts "fixed path: #{f.sub(BASE + '/', '')}"
  end
end

# Add *.core to .gitignore
gi = File.join(BASE, ".gitignore")
if File.exist?(gi)
  content = File.read(gi, encoding: "utf-8")
  unless content.include?("*.core")
    File.write(gi, content.rstrip + "\n*.core\n")
    puts "updated: .gitignore"
  end
else
  File.write(gi, "*.core\n")
  puts "created: .gitignore"
end

puts "done"
