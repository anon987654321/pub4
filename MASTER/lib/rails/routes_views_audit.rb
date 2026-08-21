# frozen_string_literal: true

require_relative "routes_views_helpers"

module Master
  module Rails
    class RoutesViewsAudit
      include RoutesViewsHelpers

      DEPLOY_RAILS = Master::DEPLOY_RAILS

      RESOURCE_ACTIONS = %i[index show new create edit update destroy].freeze
      SINGULAR_RESOURCE_ACTIONS = %i[show new create edit update destroy].freeze
      MUTATING_ACTIONS = %w[create update destroy].freeze
      VIEW_OPTIONAL_CONTROLLERS = %w[rails/pwa rails/health].freeze
      ROUTE_TO_PATTERN = /to:\s*["']([^"']+)["']/
      ROUTE_HASH_TARGET_PATTERN = /["'][^"']+["']\s*=>\s*["']([^"']+)["']/
      RESOURCES_PATTERN = /^\s*(resources|resource)\s+:(\w+)(.*)$/
      AS_PATTERN = /\bas:\s*(?::(\w+)|["'](\w+)["'])/
      PATH_HELPER_PATTERN = /\b([a-z][a-z0-9_]*_path)\b/
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

        check_all_routes(app_path, routes_text, violations)
        scan_path_helpers(app_path, route_names, violations)
        scan_orphan_partials(app_path, violations)

        {
          violations: violations.map { |v| { id: v.id, severity: v.severity, file: v.file, message: v.message } },
          counts: violations.group_by(&:id).transform_values(&:size),
        }
      end

      private

      def check_all_routes(app_path, routes_text, violations)
        explicit_routes(routes_text).each do |verb, controller, action|
          check_route_target(app_path, controller, action, violations, require_view: view_required?(verb, action))
        end

        resources_routes(routes_text).each do |controller, actions|
          actions.each do |action|
            next if MUTATING_ACTIONS.include?(action)

            check_route_target(app_path, controller, action, violations, require_view: true)
          end
        end
      end

      def collect_routes_sources(app_path)
        sources = []
        main = File.join(app_path, "config", "routes.rb")
        sources << [main, File.read(main)] if File.file?(main)

        sources.last&.last.to_s.scan(/instance_eval\(File\.read\(File\.expand_path\(["']([^"']+)["']/).flatten.each do |relative|
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
        route_lines(routes_text).filter_map do |line, module_prefix|
          next if line.strip.start_with?("#")

          verb = line[/\b(get|post|put|patch|delete)\b/i, 1]&.downcase
          target = if verb
                     line[ROUTE_TO_PATTERN, 1] || line[ROUTE_HASH_TARGET_PATTERN, 1]
                   else
                     line[/\broot\s+["']([^"']+)["']/, 1]
                   end
          next unless target

          controller, action = target.split("#", 2)
          next unless controller && action && !action.empty?

          controller = [module_prefix, controller].compact.reject(&:empty?).join("/")
          [verb || "get", controller, action]
        end.uniq
      end

      def resources_routes(routes_text)
        route_lines(routes_text).filter_map do |line, module_prefix|
          next if line.strip.start_with?("#")

          kind, resource, options = line.match(RESOURCES_PATTERN)&.captures
          next unless resource

          controller = controller_option(options) || (kind == "resource" ? pluralize(resource) : resource)
          controller = [module_prefix, controller].compact.reject(&:empty?).join("/")
          [controller, resource_actions(options, kind == "resource")]
        end.uniq
      end

      def extract_route_names(routes_text)
        names = routes_text.scan(AS_PATTERN).flatten.compact
        names << "root" if routes_text.match?(/\broot\s+["']/)
        resources = routes_text.scan(RESOURCES_PATTERN).map do |_kind, resource, options|
          names << "#{resource}_index" if resource_actions(options, false).include?("index")
          resource
        end
        names.concat(routes_text.scan(/\b(?:get|post|put|patch|delete)\s+["']([^"']+)["']/).flatten.map { |path| path.tr("-", "_") })
        terms = resources.flat_map { |resource| [resource, singularize(resource)] }
        names.concat(terms)
        names.concat(nested_resource_names(resources))

        route_actions(routes_text).each do |action|
          terms.each { |resource| names << "#{action}_#{resource}" }
        end
        names.uniq
      end

      def nested_resource_names(resources)
        resources.flat_map do |parent|
          resources.flat_map do |child|
            ["#{singularize(parent)}_#{child}", "#{singularize(parent)}_#{singularize(child)}"]
          end
        end
      end

      def view_required?(verb, action)
        verb == "get" && !MUTATING_ACTIONS.include?(action)
      end

      def check_route_target(app_path, controller, action, violations, require_view:)
        return if VIEW_OPTIONAL_CONTROLLERS.include?(controller)

        controller_path = controller_file(app_path, controller)
        unless File.file?(controller_path)
          violations << finding(:missing_controller, :high, "config/routes.rb",
                                "route targets missing controller #{controller} (#{controller}##{action})")
          return
        end

        source = File.read(controller_path)
        sources = [source, *included_sources(app_path, source)]
        controller = controller_from_path(app_path, controller_path, fallback: controller)
        unless sources.any? { |item| action_source(item, action) }
          violations << finding(:missing_action, :medium, relative(app_path, controller_path),
                                "controller lacks ##{action} referenced by routes")
        end

        check_view_present(app_path, controller, action, sources, violations) if require_view
      end

      def check_view_present(app_path, controller, action, sources, violations)
        return if VIEW_OPTIONAL_CONTROLLERS.include?(controller)
        return if sources.filter_map { |item| action_source(item, action) }.any? { |body| body.match?(EXPLICIT_RENDER_PATTERN) }
        return if template_exists?(app_path, controller, action)

        violations << finding(:missing_view, :medium, "app/views/#{controller}/#{action}",
                              "no HTML template for #{controller}##{action}")
      end

      def template_exists?(app_path, controller, action)
        [app_path, File.join(File.dirname(app_path), "shared")].any? do |root|
          %w[html.erb json.erb json.jbuilder turbo_stream.erb].any? do |ext|
            File.file?(File.join(root, "app", "views", controller, "#{action}.#{ext}"))
          end
        end
      end

      def scan_path_helpers(app_path, route_names, violations)
        local_helpers = view_helper_names(app_path)
        Dir.glob(File.join(app_path, "app", "views", "**", "*.{erb,html}")).each do |path|
          rel = relative(app_path, path)
          body = File.read(path)
          local_paths = body.scan(/^\s*([a-z]\w*_path)\s*=/).flatten
          body.scan(PATH_HELPER_PATTERN).flatten.uniq.each do |helper|
            base = helper.sub(/_(?:path|url)\z/, "")
            next if known_route_name?(base, route_names)
            next if local_paths.include?(helper)
            next if local_helpers.include?(helper)
            next if known_rails_helper?(base)

            violations << finding(:unknown_path_helper, :low, rel,
                                  "references #{helper} but no matching `as:`/resource name in routes")
          end
        rescue StandardError
          next
        end
      end

      def orphan_scan_corpus(app_path)
        views = Dir.glob(File.join(app_path, "app", "views", "**", "*")).select { |path| File.file?(path) }.map do |path|
          File.read(path)
        rescue StandardError
          ""
        end.join("\n")

        controllers = Dir.glob(File.join(app_path, "app", "controllers", "**", "*.rb")).map do |path|
          File.read(path)
        rescue StandardError
          ""
        end.join("\n")

        "#{views}\n#{controllers}"
      end

      def scan_orphan_partials(app_path, violations)
        partials = Dir.glob(File.join(app_path, "app", "views", "**", "_*.html.erb"))
        return if partials.empty?

        render_corpus = orphan_scan_corpus(app_path)

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
        %w[root rails asset image stylesheet javascript].include?(base) ||
          base.end_with?("_offline", "pwa_offline") ||
          base.start_with?("new_", "edit_")
      end

      def controller_file(app_path, controller)
        direct = File.join(app_path, "app", "controllers", "#{controller}_controller.rb")
        return direct if File.file?(direct)

        shared = File.join(File.dirname(app_path), "shared", "app", "controllers", "#{controller}_controller.rb")
        return shared if File.file?(shared)

        candidates = Dir.glob(File.join(app_path, "app", "controllers", "**", "#{controller}_controller.rb"))
        candidates.one? ? candidates.first : direct
      end

      def relative(app_path, path)
        path.delete_prefix("#{app_path}/")
      end

      def action_source(source, action)
        source[/^\s*def\s+#{Regexp.escape(action)}\b.*?(?=^\s*def\s+\w+\b|^\s*(?:private|protected)\b|\z)/m]
      end

      def included_sources(app_path, source)
        includes = source.scan(/^\s*include\s+([A-Z]\w*(?:::[A-Z]\w*)*)/).flatten
        parents = source.scan(/^\s*class\s+\w+(?:::\w+)*\s*<\s*([A-Z]\w*(?:::[A-Z]\w*)*)/).flatten
        includes.filter_map { |name| source_for(app_path, name, "concerns") } +
          parents.filter_map { |name| source_for(app_path, name) }
      end

      def source_for(app_path, name, directory = nil)
        relative = name.gsub("::", "/").gsub(/([a-z])([A-Z])/, "\\1_\\2").downcase
        roots = [File.join(app_path, "app", "controllers"), File.join(File.dirname(app_path), "shared", "app", "controllers")]
        path = roots.map { |root| File.join(root, directory.to_s, "#{relative}.rb") }.find { |candidate| File.file?(candidate) }
        File.read(path) if path
      end

      def controller_from_path(app_path, path, fallback:)
        return fallback unless path.start_with?(File.join(app_path, "app", "controllers"))

        relative(app_path, path).delete_prefix("app/controllers/").delete_suffix("_controller.rb")
      end

      def view_helper_names(app_path)
        Dir.glob(File.join(app_path, "app", "helpers", "**", "*.rb")).flat_map do |path|
          File.read(path).scan(/^\s*def\s+([a-z]\w*[!?=]?)/).flatten
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RoutesViewsAudit.helper_names")
          []
        end
      end

      def finding(id, severity, file, message)
        Finding.new(id:, severity:, file:, message:)
      end
    end
  end
end
