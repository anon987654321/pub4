# frozen_string_literal: true
# Run on VPS via: cd ~/pub4/MASTER && ruby refactor_deploy.rb

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
require "master"
require "net/http"
require "json"

OPENROUTER_KEY = ENV["OPENROUTER_API_KEY"]
DEPLOY_ROOT    = File.expand_path("DEPLOY", __dir__)

def ask_llm(prompt)
  uri  = URI("https://openrouter.ai/api/v1/chat/completions")
  body = {
    model: "anthropic/claude-opus-4",
    messages: [{ role: "user", content: prompt }],
    max_tokens: 8192
  }
  req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json",
                                 "Authorization" => "Bearer #{OPENROUTER_KEY}")
  req.body = JSON.generate(body)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) { |h| h.request(req) }
  data = JSON.parse(res.body)
  data.dig("choices", 0, "message", "content").to_s
rescue => e
  "ERROR: #{e.message}"
end

SYSTEM = <<~PROMPT
  You are a senior OpenBSD sysadmin and Rails 8 developer.
  Rules:
  - Use doas, never sudo
  - Use rcctl, never systemctl
  - Use pkg_add, never apt/brew
  - Use zsh native patterns, avoid grep/sed/awk/find where zsh builtins work
  - Scripts begin with: #!/usr/bin/env zsh
    emulate -L zsh
    setopt err_return no_unset pipe_fail extended_glob
  - Remove any backtick markdown fencing embedded in shell scripts (lines like ```zsh or ``` alone)
  - Fix all syntax errors
  - Return ONLY the corrected script, no explanation, no markdown fencing
PROMPT

sh_files = Dir.glob(File.join(DEPLOY_ROOT, "**/*.sh")).sort

puts "Found #{sh_files.size} .sh files"
puts

sh_files.each do |path|
  rel     = path.delete_prefix(DEPLOY_ROOT + "/")
  content = File.read(path)

  # Quick scan using MASTER scanner (ruby files only, sh not in rules - just use it for any findings)
  scanner = Master::Scan::Scanner.new
  scan_result = scanner.scan(path, depth: :quick)
  scan_findings = scan_result.ok? ? scan_result.value! : []

  has_sudo     = content.include?("sudo ")
  has_backtick = content.include?("```")
  has_mangled  = content.match?(/=\(zsh|=\(rails|=\(bundle/)
  has_systemctl = content.include?("systemctl")
  has_apt      = content.include?("apt-get") || content.include?("apt ")

  needs_fix = has_sudo || has_backtick || has_mangled || has_systemctl || has_apt || scan_findings.any?

  unless needs_fix
    puts "#{rel}: clean (#{content.lines.size} lines)"
    next
  end

  flags = []
  flags << "sudo"      if has_sudo
  flags << "backtick"  if has_backtick
  flags << "mangled"   if has_mangled
  flags << "systemctl" if has_systemctl
  flags << "apt"       if has_apt
  flags << "scan:#{scan_findings.size}" if scan_findings.any?

  puts "#{rel}: fixing (#{flags.join(', ')})..."

  prompt   = "#{SYSTEM}\n\nFile: #{rel}\n\n#{content}"
  fixed    = ask_llm(prompt)

  if fixed.start_with?("ERROR:")
    puts "  !! #{fixed}"
    next
  end

  # Strip any accidental markdown fencing the LLM added
  fixed = fixed.gsub(/\A```[a-z]*\n/, "").gsub(/\n```\z/, "").gsub(/^```[a-z]*\n/, "").gsub(/^```\n/, "")

  # Sanity check - must start with shebang
  unless fixed.start_with?("#!/")
    puts "  !! LLM returned non-script output (#{fixed[0..80].inspect}), skipping"
    next
  end

  original_lines = content.lines.size
  fixed_lines    = fixed.lines.size

  # Snapshot + write
  File.write("#{path}.bak", content)
  File.write(path, fixed)
  puts "  ok (#{original_lines} -> #{fixed_lines} lines)"
end

puts
puts "Done. #{sh_files.size} files processed."
