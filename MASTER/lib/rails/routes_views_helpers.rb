# frozen_string_literal: true

module Master
  module Rails
    module RoutesViewsHelpers
      private

      def controller_option(options) = options.to_s[/\bcontroller:\s*["']?([a-z_\/]+)["']?/, 1]

      def resource_actions(options, singular)
        actions = option_actions(options, "only") || (singular ? RoutesViewsAudit::SINGULAR_RESOURCE_ACTIONS : RoutesViewsAudit::RESOURCE_ACTIONS).map(&:to_s)
        actions - (option_actions(options, "except") || [])
      end

      def option_actions(options, name)
        raw = options.to_s[/\b#{name}:\s*(%[iw]\[[^\]]*\]|\[[^\]]*\]|:\w+)/, 1]
        raw&.sub(/\A%[iw]/, "")&.scan(/[a-z_]+/)
      end

      def route_actions(routes_text) = routes_text.scan(/\b(?:get|post|put|patch|delete)\s+:(\w+)/).flatten.uniq

      def route_lines(routes_text)
        contexts = []
        routes_text.each_line.filter_map do |line|
          stripped = line.strip
          contexts.pop if stripped == "end"
          item = [line, contexts.filter_map { |context| context[:module] }.join("/")]
          contexts << { module: route_module(stripped) } if opens_route_block?(stripped)
          item
        end
      end

      def opens_route_block?(line) = !line.start_with?("#") && line.match?(/\bdo\b/) && !line.include?("{")
      def route_module(line) = line[/\bnamespace\s+:(\w+)/, 1] || line[/\bscope\s+module:\s*["']?([a-z_]+)["']?/, 1]
      def known_route_name?(base, names) = names.include?(base) || names.any? { |name| base.end_with?("_#{name}") }

      def pluralize(name)
        return name.sub(/y\z/, "ies") if name.end_with?("y") && name.length > 1
        return "#{name}es" if name.match?(/(?:s|x|z|ch|sh)\z/)

        "#{name}s"
      end

      def singularize(name)
        return name.sub(/ies\z/, "y") if name.end_with?("ies")
        return name.sub(/es\z/, "") if name.match?(/(?:ses|xes|zes|ches|shes)\z/)

        name.sub(/s\z/, "")
      end
    end
  end
end
