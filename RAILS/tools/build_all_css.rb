#!/usr/bin/env ruby
# frozen_string_literal: true

# Rebuild Rails app CSS from SCSS (dartsass when available, npx sass fallback).
# Syncs shared static tokens + ensures nerd fonts are present.
#
# Usage:
#   ruby RAILS/tools/build_all_css.rb           # all apps with application.scss
#   ruby RAILS/tools/build_all_css.rb --app brgen
#   ruby RAILS/tools/build_all_css.rb --check   # verify x tokens without building

require "open3"
require "yaml"
require "fileutils"
require_relative "design_tokens"

RAILS_ROOT = File.expand_path("..", __dir__)
ROOT = File.expand_path("../..", __dir__)
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
def social_token_markers
  social = DesignTokens.load.fetch("social")
  [
    "--text: #{social.fetch('text')}",
    "--accent: #{social.fetch('accent')}",
    "JetBrainsMono Nerd Font",
  ].freeze
end

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
  social = DesignTokens.load.fetch("social")
  tokens = File.join(shared_public_dir, "styles", "tokens.css")
  FileUtils.mkdir_p(File.dirname(tokens))
  unless File.writable?(File.dirname(tokens))
    return warn "css: skip token sync — using existing #{tokens}" if File.file?(tokens)

    abort "css: cannot write tokens to #{File.dirname(tokens)}"
  end
  File.write(tokens, <<~CSS)
    /* Auto-synced by build_all_css.rb — social palette from design_tokens.yml */
    :root {
      color-scheme: dark;
      --bg: #{social.fetch("bg")};
      --surface: #{social.fetch("surface")};
      --surface-elevated: #{social.fetch("surface_elevated")};
      --search-bg: #{social.fetch("search_bg")};
      --text: #{social.fetch("text")};
      --text-secondary: #{social.fetch("text_secondary")};
      --border: #{social.fetch("border")};
      --hover: color-mix(in srgb, var(--text) 10%, transparent);
      --hover-subtle: color-mix(in srgb, var(--text) 3%, transparent);
      --accent: #{social.fetch("accent")};
      --danger: #{social.fetch("danger")};
      --font: "JetBrainsMono Nerd Font", "JetBrains Mono", ui-monospace, monospace;
      --weight-normal: 400;
      --weight-medium: 500;
      --weight-bold: 700;
      --weight-heavy: 800;
      --radius-xs: 4px;
      --radius-sm: 8px;
      --radius-md: 12px;
      --radius-card: 16px;
      --radius-lg: 16px;
      --radius-pill: 9999px;
      --transition-fast: 180ms;
      --transition-normal: 300ms;
      --z-chrome: 10;
      --z-ui: 90;
      --z-overlay: 100;
      --z-modal: 1000;
      --z-toast: 1100;
      --z-skip: 2000;
      --color-background: var(--bg);
      --color-midtone: var(--text-secondary);
      --color-highlight: var(--surface);
      --color-accent: var(--accent);
      --color-border: var(--border);
      --text-primary: var(--text);
      --text-secondary: var(--text-secondary);
    }
    @media (prefers-color-scheme: light) {
      :root {
        color-scheme: light;
        --bg: #ffffff;
        --text: #0f1419;
        --text-secondary: #536471;
        --border: #eff3f4;
        --hover: color-mix(in srgb, var(--text) 10%, transparent);
        --hover-subtle: color-mix(in srgb, var(--text) 3%, transparent);
        --color-background: var(--bg);
        --color-highlight: var(--bg);
        --text-primary: var(--text);
        --text-secondary: var(--text-secondary);
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

# The app's own Ruby, not whatever is first on PATH. On a Mac with rbenv the
# bare `bundle` resolved to system Ruby 2.6 and every app's dartsass:build
# "skipped" with a rubygems require line — so the npx fallback was doing all
# three builds, silently, and it is the weaker of the two paths.
def bundle_cmd(app_dir)
  version = ruby_version_for(app_dir)
  return ["bundle"] unless version && which("rbenv")

  ["rbenv", "exec", "bundle"].tap { ENV["RBENV_VERSION"] = version }
end

def ruby_version_for(app_dir)
  [app_dir, RAILS_ROOT, File.expand_path("..", RAILS_ROOT)].each do |dir|
    file = File.join(dir, ".ruby-version")
    return File.read(file).strip if File.file?(file)
  end
  nil
end

def which(bin)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
     .any? { |dir| File.executable?(File.join(dir, bin)) }
end

def try_dartsass(app_dir)
  return false unless File.file?(File.join(app_dir, "Gemfile"))

  out, status = Open3.capture2e(*bundle_cmd(app_dir), "exec", "rails", "dartsass:build", chdir: app_dir)
  if status.success?
    warn "css: #{File.basename(app_dir)} dartsass ok"
    return true
  end

  # The last line of a Ruby backtrace names rubygems, not the fault. Show the
  # first real error line so a skip says why it skipped.
  reason = out.lines.map(&:strip).find { |l| l.match?(/error|Error|cannot|Could not|incompatible/) }
  warn "css: #{File.basename(app_dir)} dartsass skipped (#{reason || out.lines.last&.strip})"
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
  # Mountable engines contribute stylesheets that the host's application.scss
  # @uses by bare name (`@use "_vertical_dating"`). Rails resolves those through
  # each engine's assets.paths; a bare `sass` invocation does not, so after the
  # vertical-as-engine split this fallback could not build brgen at all —
  # "Can't find stylesheet to import" on line 35, while dartsass:build was fine.
  engine_styles = Dir[File.join(app_dir, "engines", "*", "app", "assets", "stylesheets")].select do |d|
    File.directory?(d)
  end
  cmd = [
    "npx", "--yes", "sass", scss, out,
    "--load-path=#{styles_dir}",
    *engine_styles.map { |d| "--load-path=#{d}" },
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
  missing = social_token_markers.reject { |m| body.include?(m) }
  return [] if missing.empty?

  ["#{app}: build missing #{missing.join(", ")}"]
end

def verify_face_css
  path = File.join(ROOT, "MASTER", "web", "public", "face.css")
  return [] unless File.file?(path)

  body = File.read(path)
  anchors = DesignTokens.load.fetch("face_root").fetch("anchors")
  missing = [
    "--x-text: #{anchors.fetch('x_text')}",
    "JetBrainsMono Nerd Font",
  ].reject { |m| body.include?(m) }
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
