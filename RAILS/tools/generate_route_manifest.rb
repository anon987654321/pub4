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
# NAME EVERY APP. This rewrites the whole file rather than merging into it, so
# regenerating for one app deletes the other two and the next run of
# route_manifest_inventory fails with "manifest covers every app the inventory
# probes". If you are here because one app's digest went stale, still pass all
# three: `amber brgen bsdports`.
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

    def write(apps = APPS)
      manifest = build(apps)
      File.write(PATH, YAML.dump(manifest))
      manifest
    end
  end
end

if $PROGRAM_NAME == __FILE__
  # Refuses a partial run rather than warning about one.
  #
  # The header above has said "NAME EVERY APP" since this was written, because
  # writing the file rewrites all of it. On 2026-08-15 the obvious invocation —
  # `generate_route_manifest.rb brgen`, straight out of the failure message that
  # sent someone here — deleted amber and bsdports from the manifest and turned
  # one stale digest into a different, larger failure. A documented footgun is
  # still a footgun; the argument list is checkable, so it is checked.
  requested = ARGV.reject { |arg| arg == "--partial" }
  apps = requested.empty? ? Deploy::RouteManifest::APPS : requested
  missing = Deploy::RouteManifest::APPS - apps

  if missing.any? && !ARGV.include?("--partial")
    warn "generate_route_manifest: this REWRITES the whole manifest, so naming " \
         "#{apps.join(", ")} would delete #{missing.join(", ")} from it."
    warn "  regenerate everything:  ruby RAILS/tools/generate_route_manifest.rb"
    warn "  really write a partial: add --partial"
    exit 1
  end

  manifest = Deploy::RouteManifest.write(apps)
  manifest["apps"].each { |app, row| puts "#{app}: #{row['routes'].size} controller#action keys (digest #{row['digest']})" }
  puts "wrote #{Deploy::RouteManifest::PATH.sub("#{Deploy::RouteManifest::ROOT}/", '')}"
end
