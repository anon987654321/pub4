# frozen_string_literal: true

require "yaml"
require_relative "../../../checks/support/geometry_probe"
require_relative "../../../checks/support/brgen_vertical_surfaces"

module Master
  module Fix
    class ScreenshotSweep
      # Which pages a sweep visits. The route manifest is the page inventory; a
      # route with a parameter (/posts/:id) is reached through the first link on
      # an already-visited page that matches it, so it renders a real record.
      # Nothing is invented: a pattern no visited page links to is reported as
      # unresolved.
      class Plan
        MANIFEST = File.join("MASTER", "checks", "data", "route_manifest.yml")

        # Machine endpoints, auth hand-offs and probes are not pages.
        NOT_A_PAGE = %r{
          \A/(?:\.well-known|service-worker|manifest|up\b|rails/|internal/|cable|webhooks/|api/|sso/|auth/)
        }x.freeze
        FILE_LIKE = /\.(?!html\z)[a-z0-9]+\z/i.freeze
        LOOPBACK = "127.0.0.1"
        # brgen mounts each vertical engine at / on its own subdomain. A route's
        # manifest key starts with its engine (tv/feed#index), and
        # DomainRegistry::SUBAPP_ALIASES says which subdomains serve which engine.
        ALIAS = /"([a-z0-9-]+)"\s*=>\s*:([a-z_]+)/.freeze

        Page = Data.define(:app, :host, :path, :route) do
          def key = "#{host}#{path}"
        end

        def initialize(root:)
          @root = root
          @manifest = YAML.safe_load_file(File.join(root, MANIFEST)).fetch("apps")
        end

        # The root leads, so a capped sweep still shows each app's front page.
        # The master face has no manifest routes; its page is the root.
        def seeds(app)
          root = Page.new(app:, host: default_host(app), path: "/", route: "/")
          fixed = page_routes(app).reject { |_key, path| dynamic?(path) }
          pages = fixed.map { |key, path| Page.new(app:, host: route_host(app, key), path:, route: path) }
          ([root] + pages + vertical_roots(app)).uniq(&:key)
        end

        # pattern string => Regexp matching a concrete path. A pattern with no
        # literal segment (/:slug) would claim any link, so it is not resolved.
        def patterns(app)
          routes = page_routes(app).map(&:last).uniq.select { |path| dynamic?(path) && literal_segment?(path) }
          routes.to_h { |path| [path, matcher(path)] }
        end

        # The host a manifest route answers on: its engine's subdomain, else the app's.
        # Only hosts the probe already routes to loopback are chosen, so a sweep
        # never resolves a production name.
        def route_host(app, key)
          engine = key.split("/").first
          host = known_hosts(app).find { |candidate| subapp_aliases[candidate.split(".").first] == engine }
          host || default_host(app)
        end

        # brgen's routing keys off the Host header; the other apps answer on loopback.
        def default_host(app) = app == "brgen" ? Deploy::BrgenVerticalSurfaces::APEX : nil

        def known_hosts(app)
          return [] unless app == "brgen"

          Deploy::BrgenVerticalSurfaces::SURFACES.filter_map { |surface| surface[:host] }.uniq
        end

        def own_host?(app, host) = host.start_with?(LOOPBACK) || [default_host(app), *known_hosts(app)].include?(host)

        def host_for(app, link_host) = link_host.start_with?(LOOPBACK) ? default_host(app) : link_host

        private

        def dynamic?(path) = path.include?(":") || path.include?("*")

        def literal_segment?(path)
          path.split("/").any? { |segment| !segment.empty? && !dynamic?(segment) }
        end

        def matcher(path)
          body = path.split("/").map { |segment| segment_pattern(segment) }.join("/")
          /\A#{body}\z/
        end

        def segment_pattern(segment)
          return "[^/]+" if segment.start_with?(":")
          return ".+" if segment.start_with?("*")

          Regexp.escape(segment)
        end

        # [manifest key, path] pairs for every route that is a page.
        def page_routes(app)
          routes = @manifest.dig(app, "routes") || {}
          routes.flat_map { |key, paths| Array(paths).map { |path| [key, path] } }.select { |_key, path| page?(path) }
        end

        def page?(path)
          path.start_with?("/") && !path.match?(NOT_A_PAGE) && !path.match?(FILE_LIKE)
        end

        def subapp_aliases
          @subapp_aliases ||= begin
            source = File.read(Deploy::BrgenVerticalSurfaces::REGISTRY, encoding: "UTF-8")
            block = source[/SUBAPP_ALIASES = \{(.*?)\}/m, 1].to_s
            block.scan(ALIAS).to_h
          end
        end

        def vertical_roots(app)
          known_hosts(app).map { |host| Page.new(app:, host:, path: "/", route: "#{host}/") }
        end
      end

      # The crawl state for one app: seeds first; when they run out, the first
      # learned link that matches each still-unvisited parameter route.
      class Frontier
        def initialize(plan, app)
          @plan = plan
          @app = app
          @queue = plan.seeds(app)
          @patterns = plan.patterns(app)
          @seen = {}
          @reached = {}
          @links = []
        end

        def next_page
          @queue.concat(resolve) if @queue.empty?
          page = @queue.shift
          page = @queue.shift while page && @seen[page.key]
          @seen[page.key] = true if page
          page
        end

        def learn(links) = @links.concat(links.select { |(host, _path)| @plan.own_host?(@app, host) })

        def unresolved = @patterns.keys - @reached.keys

        private

        def resolve
          @patterns.filter_map do |route, regex|
            next if @reached[route]

            link = @links.find { |(_host, path)| path.match?(regex) }
            next unless link

            @reached[route] = true
            Plan::Page.new(app: @app, host: @plan.host_for(@app, link.first), path: link.last, route:)
          end
        end
      end
    end
  end
end
