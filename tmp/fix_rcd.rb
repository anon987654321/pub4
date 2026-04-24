# encoding: utf-8
# frozen_string_literal: true

# Read API keys from ~/.zshrc and inject into rc.d service
zshrc = File.read("/home/dev/.zshrc", encoding: "utf-8")
env_vars = {}
zshrc.lines.each do |l|
  if l =~ /^export\s+(\w+_API_KEY)=["']?([^"'\s]+)/
    env_vars[$1] = $2
  end
end

rcd_path = "/etc/rc.d/master"
content = File.read(rcd_path, encoding: "utf-8")

# Build env string for daemon_flags
env_exports = env_vars.map { |k, v| "#{k}=#{v}" }.join(" ")

# Update daemon_flags to include env vars
old_flags = 'daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 falcon serve --bind http://127.0.0.1:10002"'
new_flags = "daemon_flags=\"exec env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 #{env_exports} falcon serve --bind http://127.0.0.1:10002\""

content.sub!(old_flags, new_flags)
File.write(rcd_path, content)
puts "rc.d/master: injected #{env_vars.size} API keys"
