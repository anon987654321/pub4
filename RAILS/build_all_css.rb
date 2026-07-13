#!/usr/bin/env ruby
# frozen_string_literal: true

# Rebuild Rails app CSS from SCSS (dartsass when available, npx sass fallback).
# Syncs shared static tokens + ensures nerd fonts are present.
#
# Usage:
#   ruby RAILS/build_all_css.rb           # all apps with application.scss
#   ruby RAILS/build_all_css.rb --app brgen
#   ruby RAILS/build_all_css.rb --check   # verify x tokens without building

require "open3"
require "yaml"
require "fileutils"

RAILS_ROOT = File.expand_path(__dir__)
ROOT = File.expand_path("..", __dir__)
SHARED_STYLES = File.join(RAILS_ROOT, "shared", "app", "assets", "stylesheets")
def shared_public_dir
  home = ENV["HOME"].to_s
  if home != "" && File.directory?(File.join(home, "shared"))
    File.join(home, "shared", "public")
  else
    File.join(RAILS_ROOT, "shared", "public")
  end
end

def fonts_dir
  File.join(shared_public_dir, "fonts")
end
X_TOKEN_MARKERS = ["--x-text: #e7e9ea", "--x-accent: #1d9bf0", "JetBrainsMono Nerd Font"].freeze

FONT_CDN = "https://cdn.jsdelivr.net/gh/Nick2bad4u/nerd-fonts-woff2@v1.0.5/fonts/woff2/JetBrainsMono/Ligatures".freeze
FONT_SOURCES = {
  "JetBrainsMonoNerdFont-Regular.woff2" => "#{FONT_CDN}/Regular/JetBrainsMonoNerdFont-Regular.woff2",
  "JetBrainsMonoNerdFont-Bold.woff2" => "#{FONT_CDN}/Bold/JetBrainsMonoNerdFont-Bold.woff2",
}.freeze

def apps_from_yml
  yml = File.join(RAILS_ROOT, "apps.yml")
  return [] unless File.file?(yml)

  data = YAML.safe_load(File.read(yml))
  (data.fetch("apps", {}).keys + data.fetch("archived_apps", {}).keys).uniq
end

def apps_with_scss
  Dir.children(RAILS_ROOT)
    .select { |name| name != "shared" && File.directory?(File.join(RAILS_ROOT, name)) && app_has_scss?(name) }
    .sort
end

def app_has_scss?(app)
  File.file?(File.join(RAILS_ROOT, app, "app", "assets", "stylesheets", "application.scss"))
end

def selected_apps
  idx = ARGV.index("--app")
  if idx
    name = ARGV[idx + 1]
    abort "usage: --app NAME" unless name && !name.start_with?("-")
    [name]
  else
    apps_with_scss
  end
end

def ensure_fonts!
  FileUtils.mkdir_p(fonts_dir)
  FONT_SOURCES.each do |filename, url|
    path = File.join(fonts_dir, filename)
    next if File.file?(path) && File.size(path).positive?

    warn "css: fetching #{filename}"
    unless system("curl", "-fsSL", "-o", path, url)
      warn "css: font download skipped (#{filename}) — CDN fallback in _fonts.scss"
      FileUtils.rm_f(path)
    end
  end
end

def sync_static_tokens!
  tokens = File.join(shared_public_dir, "styles", "tokens.css")
  FileUtils.mkdir_p(File.dirname(tokens))
  unless File.writable?(File.dirname(tokens))
    return warn "css: skip token sync — using existing #{tokens}" if File.file?(tokens)

    abort "css: cannot write tokens to #{File.dirname(tokens)}"
  end
  File.write(tokens, <<~CSS)
    /* Auto-synced by build_all_css.rb — x.com base tokens */
    :root {
      color-scheme: dark;
      --x-bg: #000000;
      --x-surface: #000000;
      --x-surface-elevated: #16181c;
      --x-search-bg: #202327;
      --x-text: #e7e9ea;
      --x-text-secondary: #71767b;
      --x-border: #2f3336;
      --x-hover: color-mix(in srgb, var(--x-text) 10%, transparent);
      --x-hover-subtle: color-mix(in srgb, var(--x-text) 3%, transparent);
      --x-accent: #1d9bf0;
      --x-danger: #f4212e;
      --x-font: "JetBrainsMono Nerd Font", "JetBrains Mono", ui-monospace, monospace;
      --x-weight-normal: 400;
      --x-weight-medium: 500;
      --x-weight-bold: 700;
      --x-weight-heavy: 800;
      --x-radius-xs: 4px;
      --x-radius-sm: 8px;
      --x-radius-md: 12px;
      --x-radius-card: 16px;
      --x-radius-lg: 16px;
      --x-radius-pill: 9999px;
      --transition-fast: 180ms;
      --transition-normal: 300ms;
      --z-chrome: 10;
      --z-ui: 90;
      --z-overlay: 100;
      --z-modal: 1000;
      --z-toast: 1100;
      --z-skip: 2000;
      --color-background: var(--x-bg);
      --color-midtone: var(--x-text-secondary);
      --color-highlight: var(--x-surface);
      --color-accent: var(--x-accent);
      --color-border: var(--x-border);
      --text-primary: var(--x-text);
      --text-secondary: var(--x-text-secondary);
    }
    @media (prefers-color-scheme: light) {
      :root {
        color-scheme: light;
        --x-bg: #ffffff;
        --x-text: #0f1419;
        --x-text-secondary: #536471;
        --x-border: #eff3f4;
        --x-hover: color-mix(in srgb, var(--x-text) 10%, transparent);
        --x-hover-subtle: color-mix(in srgb, var(--x-text) 3%, transparent);
        --color-background: var(--x-bg);
        --color-highlight: var(--x-bg);
        --text-primary: var(--x-text);
        --text-secondary: var(--x-text-secondary);
      }
    }
  CSS
end

def scss_sources(app_dir)
  dirs = [
    File.join(app_dir, "app", "assets", "stylesheets"),
    SHARED_STYLES,
  ]
  dirs.flat_map { |d| File.directory?(d) ? Dir.glob(File.join(d, "**", "*.scss")) : [] }
end

def build_stale?(app_dir, out)
  return true unless File.file?(out)

  out_mtime = File.mtime(out)
  script = File.join(RAILS_ROOT, "build_all_css.rb")
  return true if File.file?(script) && File.mtime(script) > out_mtime

  scss_sources(app_dir).any? { |path| File.mtime(path) > out_mtime }
end

def try_dartsass(app_dir)
  return false unless File.file?(File.join(app_dir, "Gemfile"))

  out, status = Open3.capture2e("bundle", "exec", "rails", "dartsass:build", chdir: app_dir)
  if status.success?
    warn "css: #{File.basename(app_dir)} dartsass ok"
    return true
  end

  warn "css: #{File.basename(app_dir)} dartsass skipped (#{out.lines.last&.strip})"
  false
rescue StandardError => e
  warn "css: #{File.basename(app_dir)} dartsass error (#{e.message})"
  false
end

def try_npx_sass(app_dir)
  scss = File.join(app_dir, "app", "assets", "stylesheets", "application.scss")
  out = File.join(app_dir, "app", "assets", "builds", "application.css")
  FileUtils.mkdir_p(File.dirname(out))
  styles_dir = File.join(app_dir, "app", "assets", "stylesheets")
  cmd = [
    "npx", "--yes", "sass", scss, out,
    "--load-path=#{styles_dir}",
    "--load-path=#{SHARED_STYLES}",
    "--style=compressed",
  ]
  out_msg, status = Open3.capture2e(*cmd)
  if status.success?
    warn "css: #{File.basename(app_dir)} npx sass ok"
    true
  else
    warn "css: #{File.basename(app_dir)} npx sass fail: #{out_msg.lines.last(3).join}"
    false
  end
end

def verify_build(app, out)
  body = File.read(out)
  missing = X_TOKEN_MARKERS.reject { |m| body.include?(m) }
  return [] if missing.empty?

  ["#{app}: build missing #{missing.join(", ")}"]
end

def verify_face_css
  path = File.join(ROOT, "MASTER", "web", "public", "face.css")
  return [] unless File.file?(path)

  body = File.read(path)
  missing = ["--x-text: #e7e9ea", "JetBrainsMono Nerd Font"].reject { |m| body.include?(m) }
  missing.map { |m| "MASTER/web face.css missing #{m}" }
end

check_only = ARGV.include?("--check")
apps = selected_apps
failures = []

unless check_only
  ensure_fonts!
  sync_static_tokens!
end

apps.each do |app|
  app_dir = File.join(RAILS_ROOT, app)
  out = File.join(app_dir, "app", "assets", "builds", "application.css")
  next unless app_has_scss?(app)

  unless check_only
    next if File.file?(out) && !build_stale?(app_dir, out) && ENV["PUB4_CSS_FORCE"] != "1"

    ok = try_dartsass(app_dir) || try_npx_sass(app_dir)
    failures << "#{app}: CSS build failed" unless ok
  end

  failures.concat(verify_build(app, out)) if File.file?(out)
end

failures.concat(verify_face_css)

if failures.any?
  warn "css: #{failures.size} issue(s):"
  failures.each { |f| warn "  - #{f}" }
  exit 1
end

puts "css: clean (#{apps.size} app(s))"
exit 0
