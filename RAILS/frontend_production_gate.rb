#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "rbconfig"
require "yaml"
require_relative "../OPENBSD/lib/utf8"

ROOT = File.expand_path("..", __dir__)

RAILS_ROOT = File.join(ROOT, "RAILS")
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
  viewport_fit = body.match?(/viewport-fit=cover/i)
  issues << "missing viewport-fit=cover" if viewport && !viewport_fit
  charset = body.match?(/<meta\s+charset=/i) || body.match?(/tag\.meta\s+charset/i)
  issues << "missing charset meta" if body.match?(/<head\b/i) && !charset
  csp = body.match?(/csp_meta_tag|content-security-policy/i)
  issues << "missing CSP meta" if body.match?(/<head\b/i) && !csp
  skip = body.match?(/skip|#main-content/i)
  issues << "missing skip link or #main-content" unless skip
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

build_script = File.join(RAILS_ROOT, "build_all_css.rb")
if File.file?(build_script)
  # A gate must be read-only and bounded by local state. The old invocation
  # performed three full Bundler/npx builds (and possible font downloads), so
  # an offline or half-installed workspace could hang here with no output.
  # Asset compilation belongs to the build/release step; this gate verifies it.
  out, status = Open3.capture2e(RbConfig.ruby, build_script, "--check", chdir: ROOT)
  unless status.success?
    warn out unless out.strip.empty?
    exit 1
  end
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

chat_index = File.join(WEB_ROOT, "app/views/chat/index.html.erb")
if File.file?(chat_index)
  body = File.read(chat_index)
  failures << "MASTER/web chat index: missing face asset path map" unless body.include?("MASTER_ASSET_PATHS")
  failures << "MASTER/web chat index: missing lazy face import" unless body.include?('import("<%= asset_path("face.js") %>")')
  failures << "MASTER/web chat index: missing primer dismissal" unless body.include?("dismissPrimer")
  failures << "MASTER/web chat index: missing prompt reveal" unless body.include?("revealPrompt")
  failures << "MASTER/web chat index: missing error-live wiring" unless body.include?("error-live")
  failures << "MASTER/web chat index: missing face boot watchdog" unless body.include?("fallback=setTimeout")
else
  failures << "MASTER/web: missing chat index"
end

face_runtime = File.join(WEB_ROOT, "public/face.runtime.js")
face_runtime_task = File.join(WEB_ROOT, "lib/tasks/face_runtime.rake")
failures << "MASTER/web: missing face.runtime.js (run rails assets:build_face_runtime)" unless File.file?(face_runtime)
failures << "MASTER/web: missing face_runtime.rake" unless File.file?(face_runtime_task)

probe_scripts = [
  File.join(WEB_ROOT, "script/probe_face"),
  File.join(WEB_ROOT, "script/ci_web_probe")
]
probe_scripts.each do |path|
  failures << "MASTER/web: missing #{File.basename(path)}" unless File.file?(path)
end

if failures.any?
  warn "Frontend production gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Frontend production gate passed (#{apps.size} apps + MASTER/web layouts)."
