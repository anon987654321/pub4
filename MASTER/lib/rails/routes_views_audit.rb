# frozen_string_literal: true

module Master
  module Rails
    class RoutesViewsAudit
      DEPLOY_RAILS = Master::DEPLOY_RAILS

      RESOURCE_ACTIONS = %i[index show new create edit update destroy].freeze
      MUTATING_ACTIONS = %w[create update destroy].freeze
      VIEW_OPTIONAL_CONTROLLERS = %w[rails/pwa rails/health].freeze
      ROUTE_TO_PATTERN = /to:\s*["']([^"']+)["']/
      ROUTE_HASH_TARGET_PATTERN = /["'][^"']+["']\s*=>\s*["']([^"']+)["']/
      RESOURCES_PATTERN = /resources\s+:(\w+)(?:,\s*only:\s*%w\[([^\]]+)\])?/
      AS_PATTERN = /\bas:\s*:(\w+)/
      PATH_HELPER_PATTERN = /\b([a-z][a-z0-9_]*_(?:path|url))\b/
      EXPLICIT_RENDER_PATTERN = /render\s+(?:partial|json|js|xml|plain|head|inline)|redirect_to|respond_to/m

      Finding = Struct.new(:id, :severity, :file, :message, keyword_init: true)

      def initialize(root: Master::ROOT)
        @root = root
      end

      def audit(app_path)
        routes_sources = collect_routes_sources(app_path)
        routes_text = routes_sources.map { |_, text| text }.join("\n")
        route_names = extract_route_names(routes_text)
        violations = []

        explicit_routes(routes_text).each do |verb, controller, action|
          check_route_target(app_path, controller, action, violations, require_view: view_required?(verb, action))
        end

        resources_routes(routes_text).each do |controller, actions|
          actions.each do |action|
            next if MUTATING_ACTIONS.include?(action)

            check_route_target(app_path, controller, action, violations, require_view: true)
          end
        end

        scan_path_helpers(app_path, route_names, violations)
        scan_orphan_partials(app_path, violations)

        {
          violations: violations.map { |v| { id: v.id, severity: v.severity, file: v.file, message: v.message } },
          counts: violations.group_by(&:id).transform_values(&:size),
        }
      end

      private

      def collect_routes_sources(app_path)
        sources = []
        main = File.join(app_path, "config", "routes.rb")
        sources << [main, File.read(main)] if File.file?(main)

        sources.last&.last.to_s.scan(/instance_eval\(File\.read\(File\.expand_path\(["']([^"']+)["']/).each do |relative|
          shared_path = File.expand_path(relative, File.dirname(main))
          sources << [shared_path, File.read(shared_path)] if File.file?(shared_path)
        rescue StandardError
          next
        end

        sources
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "routes_views_audit.collect_routes", path: app_path)
        sources || []
      end

      def explicit_routes(routes_text)
        routes_text.lines.filter_map do |line|
          next if line.strip.start_with?("#")

          verb = line[/\b(get|post|put|patch|delete)\b/i, 1]&.downcase
          next unless verb

          target = line[ROUTE_TO_PATTERN, 1] || line[ROUTE_HASH_TARGET_PATTERN, 1]
          next unless target

          controller, action = target.split("#", 2)
          next unless controller && action && !action.empty?

          [verb, controller, action]
        end.uniq
      end

      def resources_routes(routes_text)
        routes_text.scan(RESOURCES_PATTERN).map do |resource, only_list|
          name = resource.to_s
          controller = name.end_with?("s") ? name : "#{name}s"
          actions = if only_list
                      only_list.split(/\s+/).map(&:strip)
                    else
                      RESOURCE_ACTIONS.map(&:to_s)
                    end
          [controller, actions]
        end
      end

      def extract_route_names(routes_text)
        names = routes_text.scan(AS_PATTERN).flatten
        routes_text.scan(RESOURCES_PATTERN).each do |resource, only_list|
          names << resource.to_s
          names << "#{resource}_index" unless only_list && !only_list.include?("index")
        end
        names.uniq
      end

      def view_required?(verb, action)
        verb == "get" && !MUTATING_ACTIONS.include?(action)
      end

      def check_route_target(app_path, controller, action, violations, require_view:)
        controller_path = controller_file(app_path, controller)
        unless File.file?(controller_path)
          violations << finding(:missing_controller, :high, "config/routes.rb",
                                "route targets missing controller #{controller} (#{controller}##{action})")
          return
        end

        source = File.read(controller_path)
        unless source.match?(/^\s*def\s+#{Regexp.escape(action)}\b/m)
          violations << finding(:missing_action, :medium, relative(app_path, controller_path),
                                "controller lacks ##{action} referenced by routes")
        end

        return unless require_view
        return if VIEW_OPTIONAL_CONTROLLERS.include?(controller)
        return if source.match?(EXPLICIT_RENDER_PATTERN)

        view = view_path(app_path, controller, action)
        return if File.file?(view)
        return if alternate_templates?(app_path, controller, action)

        violations << finding(:missing_view, :medium, "app/views/#{controller}/#{action}",
                              "no HTML template for #{controller}##{action}")
      end

      def alternate_templates?(app_path, controller, action)
        %w[html.erb json.erb json.jbuilder turbo_stream.erb].any? do |ext|
          File.file?(File.join(app_path, "app", "views", controller, "#{action}.#{ext}"))
        end
      end

      def scan_path_helpers(app_path, route_names, violations)
        Dir.glob(File.join(app_path, "app", "views", "**", "*.{erb,html}")).each do |path|
          rel = relative(app_path, path)
          body = File.read(path)
          body.scan(PATH_HELPER_PATTERN).flatten.uniq.each do |helper|
            base = helper.sub(/_(?:path|url)\z/, "")
            next if route_names.include?(base)
            next if known_rails_helper?(base)

            violations << finding(:unknown_path_helper, :low, rel,
                                  "references #{helper} but no matching `as:`/resource name in routes")
          end
        rescue StandardError
          next
        end
      end

      def scan_orphan_partials(app_path, violations)
        partials = Dir.glob(File.join(app_path, "app", "views", "**", "_*.html.erb"))
        return if partials.empty?

        corpus = Dir.glob(File.join(app_path, "app", "views", "**", "*")).select { |path| File.file?(path) }.map do |path|
          File.read(path)
        rescue StandardError
          ""
        end.join("\n")

        controllers = Dir.glob(File.join(app_path, "app", "controllers", "**", "*.rb")).map do |path|
          File.read(path)
        rescue StandardError
          ""
        end.join("\n")

        render_corpus = "#{corpus}\n#{controllers}"

        partials.each do |path|
          rel = relative(app_path, path)
          partial_ref = partial_reference(rel)
          next if render_corpus.include?(partial_ref)
          next if render_corpus.include?(File.basename(path, ".html.erb"))

          violations << finding(:orphaned_partial, :low, rel,
                                "partial not referenced via render in views/controllers")
        end
      end

      def partial_reference(view_rel)
        parts = view_rel.delete_prefix("app/views/").sub(/\.html\.erb\z/, "").split("/")
        name = parts.pop.delete_prefix("_")
        folder = parts.join("/")
        folder.empty? ? name : "#{folder}/#{name}"
      end

      def known_rails_helper?(base)
        %w[root rails root_url rails_url].include?(base) ||
          base.end_with?("_offline", "pwa_offline") ||
          base.start_with?("new_", "edit_")
      end

      def controller_file(app_path, controller)
        File.join(app_path, "app", "controllers", "#{controller}_controller.rb")
      end

      def view_path(app_path, controller, action)
        File.join(app_path, "app", "views", controller, "#{view_basename(controller, action)}")
      end

      def view_basename(_controller, action)
        return "index.html.erb" if action == "index"

        "#{action}.html.erb"
      end

      def relative(app_path, path)
        path.delete_prefix("#{app_path}/")
      end

      def finding(id, severity, file, message)
        Finding.new(id:, severity:, file:, message:)
      end
    end
  end
end
