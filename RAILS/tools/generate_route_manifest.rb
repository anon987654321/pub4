# frozen_string_literal: true

# Writes gates/data/route_manifest.yml: controller#action -> GET paths, per app.
#
# PageInventory used to derive a URL from a view's filename through a ladder of
# special cases (dating's singular :profile, TV nested under channels, partner
# ids). Every route that did not follow the convention had to be added by hand,
# and four that were not -- bookmarks#index at /saved, and the three legal pages
# -- made page_simulation probe 404s and report them as broken pages. Routes are
# the truth; this file carries them to the gate.
#
#   ruby RAILS/tools/generate_route_manifest.rb [app ...]
#
# Naming one app regenerates that app and leaves the others as they are. It used
# to rewrite the whole file, so regenerating for one deleted the other two, and
# the header said so in capitals — while page_simulation, the thing that tells
# you a digest is stale, printed the single-app command. The advice on screen
# walked into the trap the header warned about, which is a warning doing no work.
# Merging removes the trap instead of restating it.
#
# Each app records a digest of its route sources. PageInventory fails the
# simulation when the digest no longer matches, so a stale manifest is loud
# rather than silently wrong -- which is the failure the hand-maintained ladder
# had.

require "digest"
require "open3"
require "yaml"

module Deploy
  module RouteManifest
    ROOT = File.expand_path("../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    PATH = File.join(RAILS_ROOT, "gates", "data", "route_manifest.yml")
    APPS = %w[brgen amber bsdports].freeze

    # Prefix and defaults are both optional and the prefix may be blank, so anchor
    # on the verb rather than counting columns.
    ROUTE_LINE = /^\s*(?<prefix>\S*)\s+(?<verb>[A-Z]+(?:\|[A-Z]+)*)\s+(?<pattern>\/\S*)\s+(?<endpoint>.+?)\s*$/
    ENDPOINT = /^(?<controller>[a-z0-9_\/]+)#(?<action>[a-z0-9_]+)(?:\s+\{(?<defaults>.*)\})?$/

    module_function

    def app_root(app) = File.join(RAILS_ROOT, app)

    # Every file that can add a route, so editing any of them invalidates the digest.
    def route_sources(app)
      base = app_root(app)
      Dir.glob(File.join(base, "config", "routes.rb")) +
        Dir.glob(File.join(base, "config", "routes", "**", "*.rb")).sort +
        Dir.glob(File.join(RAILS_ROOT, "shared", "config", "routes.rb")) +
        Dir.glob(File.join(RAILS_ROOT, "shared", "config", "routes", "**", "*.rb")).sort +
        Dir.glob(File.join(base, "engines", "*", "config", "routes.rb")).sort
    end

    def digest(app)
      Digest::SHA256.hexdigest(route_sources(app).map { |f| File.read(f) }.join("\n"))[0, 16]
    end

    def capture_routes(app)
      out, status = Open3.capture2e(
        { "RBENV_VERSION" => ruby_version, "RAILS_ENV" => "development" },
        "rbenv", "exec", "bundle", "exec", "bin/rails", "routes",
        chdir: app_root(app)
      )
      raise "bin/rails routes failed in #{app}:\n#{out.lines.last(15).join}" unless status.success?

      out
    end

    def ruby_version
      path = File.join(ROOT, ".ruby-version")
      File.file?(path) ? File.read(path).strip : ENV.fetch("RBENV_VERSION", "")
    end

    # controller#action -> sorted GET paths. A pages#show carrying `{page: "terms"}`
    # also registers as pages#terms, because that is the name its view file has.
    def parse(text)
      table = Hash.new { |hash, key| hash[key] = [] }
      text.each_line do |line|
        match = ROUTE_LINE.match(line)
        next unless match && match[:verb].split("|").include?("GET")

        endpoint = ENDPOINT.match(match[:endpoint].strip)
        next unless endpoint

        path = match[:pattern].sub("(.:format)", "")
        key = "#{endpoint[:controller]}##{endpoint[:action]}"
        table[key] << path
        default_alias(endpoint).each { |name| table["#{endpoint[:controller]}##{name}"] << path }
      end
      table.transform_values { |paths| paths.uniq.sort_by { |p| [p.count(":"), p.length] } }
    end

    def default_alias(endpoint)
      endpoint[:defaults].to_s.scan(/:?\w+:?\s*=?>?\s*"([a-z0-9_]+)"/).flatten
    end

    def build(apps = APPS)
      {
        "schema" => 1,
        "apps" => apps.to_h { |app| [app, { "digest" => digest(app), "routes" => parse(capture_routes(app)) }] },
      }
    end

    # Merged into whatever is already on disk, so regenerating one app leaves the
    # other two intact. Each app carries its own digest and the inventory test
    # compares them per app, so a merged-in entry that has since gone stale is
    # still caught — nothing is traded away for this.
    def write(apps = APPS)
      existing = File.file?(PATH) ? (YAML.safe_load_file(PATH) || {}) : {}
      merged = build(apps)
      merged["apps"] = (existing["apps"] || {}).merge(merged["apps"])
      merged["apps"] = merged["apps"].sort.to_h
      File.write(PATH, YAML.dump(merged))
      merged
    end
  end
end

if $PROGRAM_NAME == __FILE__
  apps = ARGV.empty? ? Deploy::RouteManifest::APPS : ARGV
  manifest = Deploy::RouteManifest.write(apps)
  # Only the apps this run rebuilt. The manifest carries the others too now, and
  # printing them would read as having re-measured what it merely preserved.
  manifest["apps"].slice(*apps).each { |app, row| puts "#{app}: #{row['routes'].size} controller#action keys (digest #{row['digest']})" }
  kept = manifest["apps"].keys - apps
  puts "kept unchanged: #{kept.join(', ')}" if kept.any?
  puts "wrote #{Deploy::RouteManifest::PATH.sub("#{Deploy::RouteManifest::ROOT}/", '')}"
end
