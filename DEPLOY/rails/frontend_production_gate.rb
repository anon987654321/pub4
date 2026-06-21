#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("../..", __dir__)
RAILS_ROOT = File.join(ROOT, "DEPLOY", "rails")
WEB_ROOT = File.join(ROOT, "MASTER", "web")
APPS_YML = File.join(RAILS_ROOT, "apps.yml")

def layout_files(app_dir)
  [File.join(app_dir, "app/views/layouts/application.html.erb")].select { |path| File.file?(path) }
end

def web_layout_files
  Dir.glob(File.join(WEB_ROOT, "app/views/layouts/*.html.erb")) +
    [File.join(WEB_ROOT, "app/views/chat/index.html.erb")]
end

def check_layout(path)
  body = File.read(path)
  issues = []
  issues << "missing lang on <html>" if body.match?(/<html\b/i) && !body.match?(/<html[^>]*\blang=/i)
  viewport = body.match?(/name=["']viewport["']/i) || body.match?(/name:\s*["']viewport["']/i)
  issues << "missing viewport meta" unless viewport
  charset = body.match?(/<meta\s+charset=/i) || body.match?(/tag\.meta\s+charset/i)
  issues << "missing charset meta" if body.match?(/<head\b/i) && !charset
  unsafe = body.match?(/<%=\s*[^%]+\.html_safe\s*%>/) && !body.match?(/sanitize|strip_tags|\.to_json\.html_safe/)
  issues << "unsafe raw <%= without sanitize" if unsafe
  issues
end

def check_views(app_dir)
  issues = []
  Dir.glob(File.join(app_dir, "app/views/layouts/**/*.html.erb")).each do |path|
    body = File.read(path)
    issues << "#{path}: <a href='#'> action link" if body.match?(/<a\s+href=["']#["']/i)
  end
  issues
end

failures = []
apps = YAML.safe_load(File.read(APPS_YML)).fetch("apps")

apps.each_key do |name|
  app_dir = File.join(RAILS_ROOT, name)
  next unless File.directory?(app_dir)

  layout_files(app_dir).each do |path|
    check_layout(path).each { |issue| failures << "#{name} #{File.basename(path)}: #{issue}" }
  end
  check_views(app_dir).each { |issue| failures << "#{name}: #{issue.delete_prefix(app_dir + '/')}" }
end

web_layout_files.each do |path|
  check_layout(path).each { |issue| failures << "MASTER/web #{File.basename(path)}: #{issue}" }
end

if failures.any?
  warn "Frontend production gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Frontend production gate passed (#{apps.size} apps + MASTER/web layouts)."