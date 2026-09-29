# frozen_string_literal: true

require "json"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../support/cdp_session"
require_relative "../support/geometry_probe"
require_relative "../support/page_inventory"

module Deploy
  # Screen-reader path gate. It reads Chrome's computed accessibility tree
  # after navigation, then checks the same public surfaces the rendered family
  # already walks. An accessible DOM is not enough: the question is what Chrome
  # exposes to assistive technology.
  class AccessibilityTreeGate
    ROOT = File.expand_path("../../../..", __dir__)
    MAX_SURFACES = 8
    INTERACTIVE_ROLES = %w[button link textbox checkbox radio combobox listbox].freeze

    def self.run = new.run

    def run
      result = GateResult.new
      surfaces = Deploy::PageInventory.guest_liveable.group_by { |page| page[:app] }.values
                     .flat_map { |rows| rows.first(2) }
                     .first(MAX_SURFACES)
      unless Deploy::GeometryProbe.available?
        result.inconclusive!("accessibility_tree: no Chrome/Chromium — accessibility tree not measured")
        return result
      end
      unless surfaces.any?
        result.inconclusive!("accessibility_tree: no guest surfaces in inventory")
        return result
      end

      host_map = Deploy::GeometryProbe.host_map
      browser_surfaces = surfaces.select { |page| !page[:host] || host_map.key?(page[:host]) }
      if browser_surfaces.empty?
        result.inconclusive!("accessibility_tree: no inventory surface maps to a browser host")
        return result
      end

      Deploy::CdpSession.open(host_map:, webgl: false) do |cdp|
        browser_surfaces.each { |page| inspect_surface(cdp, page, result) }
      end
      result
    rescue StandardError => e
      result.errored!("accessibility_tree: #{e.class}: #{e.message.lines.first.to_s.strip}")
      result
    end

    private

    def inspect_surface(cdp, page, result)
      cdp.viewport(390, 844, mobile: true, scale: 1)
      cdp.navigate(surface_url(page), settle: 0.4)
      nodes = cdp.accessibility_tree
      roles = nodes.to_h { |node| [node["nodeId"], [node.dig("role", "value"), node.dig("name", "value")]] }

      result.checked!(1)
      unless roles.values.any? { |role, _name| role.to_s == "main" }
        result.fail("accessibility_tree: #{page[:id]} exposes no main landmark")
      end

      unnamed = roles.values.filter_map do |role, name|
        next unless INTERACTIVE_ROLES.include?(role.to_s)
        next unless name.to_s.strip.empty?

        role.to_s
      end
      unless unnamed.empty?
        result.fail("accessibility_tree: #{page[:id]} has unnamed interactive roles: #{unnamed.tally.sort_by { |role, count| [role, count] }.map { |role, count| "#{role}=#{count}" }.join(", ")}")
      end
    end

    def surface_url(page)
      host = page[:host] || Deploy::Fleet.public_host(page[:app])
      path = page[:path].to_s
      "http://#{host}#{path}"
    end
  end
end
