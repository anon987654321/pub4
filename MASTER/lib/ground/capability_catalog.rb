# frozen_string_literal: true

require_relative "tool"
require_relative "../plugin"

module Master
  module Ground
    # One read-only discovery view over built-in tools and declared plugin
    # observations. Metadata describes what is registered; it never promises
    # a provider is reachable or an action will succeed.
    module CapabilityCatalog
      MAX_RESULTS = 60
      module_function

      def call(action:, query: nil, name: nil, root: Master::ROOT)
        verb = action.to_s.downcase
        raise ArgumentError, "action must be list, search or describe" unless %w[list search describe].include?(verb)

        tools = builtin_tools(root:)
        plugins = plugin_entries
        case verb
        when "list"
          { "status" => "ok", "profile" => Tool::Profile.current_name,
            "core_tools" => tools.first(MAX_RESULTS),
            "plugins" => plugins.first(MAX_RESULTS),
            "truncated" => tools.size > MAX_RESULTS || plugins.size > MAX_RESULTS,
            "note" => "Registration is not proof of live availability. Plugin actions listed here are read-only observation actions only." }
        when "search"
          needle = query.to_s.strip.downcase
          raise ArgumentError, "query is required" if needle.empty?

          searchable = tools.map { |item| item.merge("kind" => "core_tool") } +
                       plugins.map { |item| item.merge("kind" => "plugin") }
          matches = searchable.select do |item|
            item.values.flatten.compact.any? { |value| value.to_s.downcase.include?(needle) }
          end
          { "status" => "ok", "query" => query.to_s[0, 160],
            "results" => matches.first(MAX_RESULTS), "count" => matches.size, "truncated" => matches.size > MAX_RESULTS }
        when "describe"
          key = name.to_s.strip
          raise ArgumentError, "name is required" if key.empty?

          tool = tools.find { |item| item["name"].casecmp?(key) }
          return { "status" => "found", "kind" => "core_tool", "capability" => tool } if tool

          plugin = plugins.find { |item| item["id"].casecmp?(key) }
          return { "status" => "found", "kind" => "plugin", "capability" => plugin } if plugin

          parts = key.split(":")
          if parts.length == 3 && parts[0] == "plugin"
            plugin = plugins.find { |item| item["id"] == parts[1] }
            action = plugin && plugin["observation_actions"].find { |row| row["name"] == parts[2] }
            return { "status" => "found", "kind" => "plugin_observation", "plugin" => parts[1], "capability" => action } if action
          end
          { "status" => "not_found", "name" => key }
        end
      rescue KeyError, Psych::Exception => e
        { "status" => "inconclusive", "reason" => "capability metadata unavailable: #{e.class}: #{e.message}" }
      end

      def builtin_tools(root: Master::ROOT)
        rows = Master.tools_config(root:)
        raise ArgumentError, "tool registry must be an array" unless rows.is_a?(Array)

        allowed = Tool::Profile.allowlist
        rows.select { |row| row.is_a?(Hash) }.map do |row|
          name = row["name"].to_s
          raise ArgumentError, "unnamed tool in registry" if name.empty?

          {
            "name" => name,
            "description" => row["description"].to_s[0, 360],
            "elevated_required" => row.fetch("elevated", true) != false,
            "boot_enabled" => row.fetch("default", false) == true,
            "allowed_by_current_profile" => allowed.nil? || allowed.include?(name),
          }
        end
      end
      private_class_method :builtin_tools

      def plugin_entries
        Master::Plugin.list.map do |manifest|
          policy_present = begin
            Master::Plugin.policy(manifest.id)
            true
          rescue KeyError
            false
          end
          actions = manifest.observe_actions.map do |action|
            { "name" => action, "access" => "read_only", "tool_name" => "PluginObserve" }
          end
          {
            "id" => manifest.id,
            "version" => manifest.version,
            "description" => manifest.description[0, 360],
            "policy_present" => policy_present,
            "observation_actions" => actions,
            "status" => !policy_present ? "policy_missing" : actions.empty? ? "no_observation_actions" : "declared",
          }
        end
      end
      private_class_method :plugin_entries
    end
  end
end
