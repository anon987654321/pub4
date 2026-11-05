# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../support/geometry_probe"

module Deploy
  # Measures computed accessible names from Chrome's accessibility tree.
  #
  # This catches unnamed controls and informative images in the rendered page.
  # It does not simulate a screen reader's speech, rotor or announcement timing;
  # those remain human evidence and are reported separately by BaymardUXCheck.
  class AccessibilityTreeCheck
    ROOT = File.expand_path("../../../..", __dir__)

    CONTROL_ROLES = %w[
      button link textbox searchbox combobox checkbox radio switch slider tab
      menuitem option treeitem spinbutton
    ].freeze
    NAMED_ROLES = (CONTROL_ROLES + ["image"]).freeze
    VIEWPORTS = %w[desktop mobile].freeze
    MAX_SURFACES_PER_APP_VIEWPORT = 2

    def self.run = new.run

    # Public for deterministic contract tests; ignored AX nodes include
    # intentionally decorative content and must not be treated as failures.
    def self.unnamed_nodes(nodes)
      Array(nodes).filter_map do |node|
        next unless node.is_a?(Hash)
        next if node["ignored"] == true

        role = node.dig("role", "value").to_s
        next unless NAMED_ROLES.include?(role)

        name = node.dig("name", "value").to_s.strip
        next unless name.empty?

        { "role" => role, "node_id" => node["nodeId"] }
      end
    end

    def run
      result = CheckResult.new
      unless GeometryProbe.available?
        result.inconclusive!("accessibility_tree: no Chrome/Chromium - computed accessibility names not measured")
        return result
      end

      surfaces = target_surfaces
      if surfaces.empty?
        result.inconclusive!("accessibility_tree: no desktop or mobile surfaces are declared")
        return result
      end

      unreachable = GeometryProbe.unreachable_apps(surfaces)
      unreachable.each do |app|
        result.incomplete!("accessibility_tree: #{app} is not listening - its accessibility tree was not measured")
      end

      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        result.inconclusive!("accessibility_tree: no target app is reachable")
        return result
      end

      measured = 0
      GeometryProbe.with_browser(warm: live) do |cdp|
        cdp.command("Accessibility.enable")
        live.each do |surface|
          label = "#{surface.app}/#{surface.label}/#{surface.viewport}"
          payload = GeometryProbe.walk(cdp, surface)
          unless GeometryProbe.ok?(payload)
            result.incomplete!("accessibility_tree: #{label} did not render - #{payload["error"] || "HTTP #{payload["status"]}"}")
            next
          end

          tree = cdp.command("Accessibility.getFullAXTree")
          nodes = tree["nodes"]
          unless nodes.is_a?(Array) && nodes.any?
            result.incomplete!("accessibility_tree: #{label} returned no computed accessibility nodes")
            next
          end

          measured += 1
          unnamed = self.class.unnamed_nodes(nodes)
          next if unnamed.empty?

          examples = unnamed.first(5).map { |node| "#{node["role"]}(#{node["node_id"]})" }.join(", ")
          result.fail(
            "accessibility_tree: #{label} has #{unnamed.size} unnamed interactive/image node(s): #{examples}",
          )
        rescue CdpSession::Error => e
          result.incomplete!("accessibility_tree: #{label} could not be read - #{e.class.name.split("::").last}: #{e.message}")
        end
      end

      if measured.zero?
        result.inconclusive!("accessibility_tree: 0/#{live.size} rendered surface(s) yielded an accessibility tree")
      else
        result.checked!(measured)
        result.warn("accessibility_tree: measured computed names on #{measured}/#{live.size} rendered surfaces")
        if measured < live.size
          result.incomplete!("accessibility_tree: #{live.size - measured} reachable surface(s) were not measured")
        end
      end
      result
    rescue StandardError => e
      CheckResult.from_error(e, check: "AccessibilityTreeCheck")
    end

    private

    def target_surfaces
      GeometryProbe.surfaces
                    .select { |surface| VIEWPORTS.include?(surface.viewport) }
                    .group_by { |surface| [surface.app, surface.viewport] }
                    .sort_by { |(app, viewport), _rows| [app, viewport] }
                    .flat_map { |_key, rows| rows.first(MAX_SURFACES_PER_APP_VIEWPORT) }
    end
  end
end
