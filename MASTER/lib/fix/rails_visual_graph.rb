# frozen_string_literal: true

require "open3"
require "timeout"

module Master
  module Fix
    # A small, source-first map of a Rails application's visual dependency graph.
    # It deliberately complements GeometryProbe rather than replacing it:
    # GeometryProbe proves what the browser rendered; this graph explains where
    # that render came from and which surfaces share the same source.
    class RailsVisualGraph
      SOURCE_EXTENSIONS = %w[.css .scss .erb .html .htm .js .ts].freeze
      ASSET_EXTENSIONS = %w[.css .scss .js .ts .erb .html .htm .woff .woff2 .ttf .otf .png .jpg .jpeg .webp .svg .gif .ico].freeze
      PARTIAL_SUFFIXES = %w[.html.erb .turbo_stream.erb .erb .scss .css .js .ts .html].freeze
      APP_NAMES = %w[brgen amber bsdports].freeze
      # `rails routes` prints the route name before the verb for every named
      # route, so the verb is not at the start of the line.
      ROUTE_RE = /^\s*(?:\S+\s+)?(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)\s+(\/\S*)\s+(\S+#\S+)/

      SurfaceMap = Data.define(:surface, :app, :route, :sources)

      attr_reader :apps, :routes, :edges, :errors

      def initialize(root:)
        @root = root
        @apps = {}
        @routes = Hash.new { |h, k| h[k] = [] }
        @edges = Hash.new { |h, k| h[k] = [] }
        @errors = []
      end

      def build
        app_roots.each do |name, path|
          next unless File.directory?(path)

          @apps[name] = path
          discover_routes(name, path)
          discover_source_edges(name, path)
        end
        self
      end

      def sources_for(surface)
        app = surface.app.to_s
        root = @apps[app]
        return [] unless root

        route = matching_route(app, surface.path)
        seeds = []
        if route
          seeds.concat(controller_sources(root, route))
          seeds.concat(view_sources(root, route))
        end

        seeds.concat(layout_sources(root))
        seeds.concat(entry_assets(root))
        closure(root, seeds).first(80)
      end

      def map(surface)
        SurfaceMap.new(surface:, app: surface.app, route: matching_route(surface.app, surface.path),
                       sources: sources_for(surface))
      end

      def context
        route_count = @routes.values.sum(&:length)
        edge_count = @edges.values.sum(&:length)
        apps = @apps.keys.sort.join(", ")
        errors = @errors.empty? ? "" : "; errors=#{@errors.size}"
        "Rails visual graph: apps=#{apps}; routes=#{route_count}; dependency_edges=#{edge_count}#{errors}"
      end

      def coverage(surfaces, captures)
        expected = Array(surfaces).map(&:id)
        actual = Array(captures).map { |capture| capture[:surface].id }
        {
          expected:,
          captured: actual,
          missing: expected - actual,
          ratio: expected.empty? ? 1.0 : actual.uniq.length.to_f / expected.uniq.length,
        }
      end

      private

      def app_roots
        APP_NAMES.to_h { |name| [name, File.join(@root, "RAILS", name)] }.tap do |rows|
          Dir.glob(File.join(@root, "RAILS", "brgen", "engines", "*")).each do |path|
            rows[File.basename(path)] = path if File.directory?(path)
          end
        end
      end

      def discover_routes(app, root)
        command = File.join(root, "bin", "rails")
        return unless File.executable?(command)

        output, status = Timeout.timeout(ROUTES_TIMEOUT_S) { app_capture(command, root) }
        unless status.success?
          @errors << "routes #{app}: rails routes exited #{status.exitstatus}: #{output.lines.last(3).join.strip}"
          return
        end

        output.each_line do |line|
          match = line.match(ROUTE_RE)
          next unless match

          method, path, target = match.captures
          # The optional format suffix belongs to nearly every route; drop the
          # suffix, not the route.
          @routes[app] << { method:, path: normalize_path(path.delete_suffix("(.:format)")), target: }
        end
      rescue Errno::ENOENT, Timeout::Error, SystemCallError => e
        @errors << "routes #{app}: #{e.class}: #{e.message}"
      rescue StandardError => e
        @errors << "routes #{app}: #{e.class}: #{e.message}"
      end

      # A cold `rails routes` boots the whole app; 15s timed out under load.
      ROUTES_TIMEOUT_S = 60

      def app_capture(command, root) = RailsApp.capture(root, command, "routes", timeout: ROUTES_TIMEOUT_S)

      def discover_source_edges(_app, root)
        files = Dir.glob(File.join(root, "**", "*")).select { |path| source_file?(path) }
        files.each do |file|
          source = File.read(file, encoding: "UTF-8")
          references(source).each do |reference|
            target = resolve_reference(root, file, reference)
            next unless target

            @edges[file] << target unless @edges[file].include?(target)
          end
        rescue ArgumentError, SystemCallError
          next
        end
      end

      def references(source)
        patterns = [
          /@(?:use|forward|import)\s+["']([^"']+)/,
          /\b(?:import|require)\s*(?:\([^)]*|from\s*)?["']([^"']+)/,
          /\b(?:render|partial|stylesheet_link_tag|javascript_include_tag|image_tag|asset_path|image_path)\s*\(?\s*["']([^"']+)/,
        ]
        patterns.flat_map { |pattern| source.scan(pattern).flatten }.uniq
      end

      def resolve_reference(root, source, reference)
        ref = reference.to_s.sub(/\?.*\z/, "")
        return if ref.empty? || ref.start_with?("http", "//", "#")

        lookup_dirs(root, source, ref).flat_map { |dir| asset_variants(File.expand_path(ref.delete_prefix("~"), dir)) }
                                      .find { |path| File.file?(path) }
      end

      # Where Rails and Sass look: beside the source, the app root, the view and
      # stylesheet load paths, and the shared engine every app mounts.
      def lookup_dirs(root, source, ref)
        shared = File.join(@root, "RAILS", "shared")
        loads = [root, shared].flat_map do |base|
          [File.join(base, "app", "views"), File.join(base, "app", "assets", "stylesheets")]
        end
        [File.dirname(source), root, *loads].uniq.then { |dirs| ref.start_with?("~") ? [root] : dirs }
      end

      # A bare name is a partial as often as a file: `shared/pager` is
      # `shared/_pager.html.erb`, `@use "base"` is `_base.scss`.
      def asset_variants(path)
        ext = File.extname(path)
        return [path, File.join(File.dirname(path), "_#{File.basename(path)}")] unless ext.empty? || ext == ".erb"

        partial = File.join(File.dirname(path), "_#{File.basename(path)}")
        [path, partial].flat_map { |base| [base] + PARTIAL_SUFFIXES.map { |suffix| "#{base}#{suffix}" } }
      end

      def matching_route(app, path)
        wanted = normalize_path(path)
        Array(@routes[app]).find do |route|
          route_path = route[:path]
          next true if route_path == wanted

          pattern = route_path.split("/").map do |segment|
            if segment.start_with?(":")
              "[^/]+"
            elsif segment.start_with?("*")
              ".*"
            else
              Regexp.escape(segment)
            end
          end.join("/")
          /\A#{pattern}\z/ =~ wanted
        end
      end

      def controller_sources(root, route)
        controller, action = route[:target].split("#", 2)
        path = File.join(root, "app", "controllers", "#{controller.delete_prefix("/controllers/")}.rb")
        return [] unless File.file?(path)

        [path] + Dir.glob(File.join(root, "app", "controllers", "**", "*.rb")).select do |candidate|
          File.read(candidate, encoding: "UTF-8").include?("def #{action}")
        rescue StandardError => e
          raise "visual graph: controller source unreadable #{candidate}: #{e.class}: #{e.message}"
        end
      end

      def view_sources(root, route)
        controller, action = route[:target].split("#", 2)
        controller = controller.sub(%r{\A/}, "")
        candidates = [
          File.join(root, "app", "views", controller, "#{action}.html.erb"),
          File.join(root, "app", "views", controller, "#{action}.erb"),
        ]
        candidates.select { |path| File.file?(path) }
      end

      def layout_sources(root)
        Dir.glob(File.join(root, "app", "views", "layouts", "**", "*.erb"))
      end

      def entry_assets(root)
        [
          Dir.glob(File.join(root, "app", "assets", "stylesheets", "application.{scss,css}")),
          Dir.glob(File.join(root, "app", "javascript", "application.{js,ts}")),
          Dir.glob(File.join(root, "app", "assets", "javascripts", "application.{js,ts}")),
        ].flatten.select { |path| File.file?(path) }
      end

      def closure(root, seeds)
        seen = []
        queue = seeds.compact.uniq
        until queue.empty?
          path = queue.shift
          next if seen.include?(path) || !File.file?(path)

          seen << path
          Array(@edges[path]).each { |target| queue << target unless seen.include?(target) }
        end

        # The graph should still explain a surface when route discovery is
        # unavailable (for example, a cold Rails app with broken dependencies).
        fallback = Dir.glob(File.join(root, "app", "**", "*")).select { |path| source_file?(path) }
        (seen + fallback.first(20)).uniq
      end

      def normalize_path(path)
        value = path.to_s.split("(.:format)").first
        value = "/#{value}" unless value.start_with?("/")
        value.gsub(%r{/+}, "/").sub(%r{/$}, "").then { |v| v.empty? ? "/" : v }
      end

      def source_file?(path)
        File.file?(path) && SOURCE_EXTENSIONS.include?(File.extname(path).downcase)
      end
    end
  end
end
