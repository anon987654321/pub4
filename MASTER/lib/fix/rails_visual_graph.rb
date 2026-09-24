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
      APP_NAMES = %w[brgen amber bsdports].freeze
      ROUTE_RE = /^\s*(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD|\*).*?\s(\/[^\s]*)\s+([^\s]+#\S+)/

      SurfaceMap = Data.define(:surface, :app, :route, :sources) do
        def source_paths = sources
      end

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
          expected: expected,
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

        output, status = Timeout.timeout(15) { Open3.capture2e(command, "routes", chdir: root) }
        unless status.success?
          @errors << "routes #{app}: rails routes exited #{status.exitstatus}: #{output.lines.last(3).join.strip}"
          return
        end

        output.each_line do |line|
          match = line.match(ROUTE_RE)
          next unless match

          method, path, target = match.captures
          next if path.include?("(.:format)")
          @routes[app] << { method:, path: normalize_path(path), target: }
        end
      rescue Errno::ENOENT, Timeout::Error, SystemCallError => e
        @errors << "routes #{app}: #{e.class}: #{e.message}"
      rescue StandardError => e
        @errors << "routes #{app}: #{e.class}: #{e.message}"
      end

      def discover_source_edges(app, root)
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

        candidates = []
        base = File.dirname(source)
        candidates << File.expand_path(ref, base)
        candidates << File.expand_path(ref, root)
        if ref.start_with?("~")
          candidates << File.expand_path(ref.delete_prefix("~"), root)
        end

        candidates.flat_map { |path| asset_variants(path) }.find { |path| File.file?(path) }
      end

      def asset_variants(path)
        ext = File.extname(path)
        base = ext.empty? ? path : path.delete_suffix(ext)
        names = [path]
        names.concat(%w[.scss .css .js .ts .erb .html].map { |suffix| "#{base}#{suffix}" }) if ext.empty?
        names.concat(["#{File.dirname(path)}/_#{File.basename(path)}#{ext}"]) if ext == ".scss"
        names
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
