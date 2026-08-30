# frozen_string_literal: true

require "json"
require_relative "discovery"

module Master
  module Ground
    module Antigravity
      # Plugins manages Antigravity plugin bundles, packaging skills, rules,
      # hooks, and MCP servers into single units with config.json toggle support.
      class Plugins
        attr_reader :discovery, :plugins

        def initialize(discovery: Discovery.new, config_file: nil)
          @discovery = discovery
          @config_file = config_file || File.expand_path("~/.gemini/antigravity-cli/config.json")
          @plugins = {}
          @user_config = load_user_config
        end

        def discover!
          @plugins = {}

          # 1. Workspace plugins
          @discovery.workspace_customization_roots.each do |root|
            scan_plugins_dir(File.join(root, "plugins"))
          end

          # 2. Declared plugins in plugins.json
          @discovery.declared_plugins_entries.each do |entry|
            scan_plugins_dir(entry[:path], include_only: entry[:include_only], exclude: entry[:exclude])
          end

          # 3. Global plugins
          if @discovery.global_customization_root
            scan_plugins_dir(File.join(@discovery.global_customization_root, "plugins"))
          end

          # 4. Built-in plugins
          if @discovery.builtin_customization_root
            scan_plugins_dir(File.join(@discovery.builtin_customization_root, "plugins"))
          end

          @plugins.values
        end

        def enabled_plugins
          discover!.select { |p| enabled?(p) }
        end

        def enabled?(plugin)
          dir_name = plugin[:dir_name]
          user_pref = @user_config.dig("plugins", dir_name, "enabled")
          return user_pref unless user_pref.nil?

          !plugin[:disabled]
        end

        def set_enabled(dir_name, enabled)
          @user_config["plugins"] ||= {}
          @user_config["plugins"][dir_name.to_s] = { "enabled" => !!enabled }
          save_user_config
        end

        private

        def scan_plugins_dir(dir_path, include_only: [], exclude: [])
          return unless File.directory?(dir_path)

          inc_patterns = Array(include_only).map { |p| Regexp.new(p) }
          exc_patterns = Array(exclude).map { |p| Regexp.new(p) }

          Dir.glob(File.join(dir_path, "*")).sort.each do |plugin_dir|
            next unless File.directory?(plugin_dir)

            dir_name = File.basename(plugin_dir)
            next if inc_patterns.any? && inc_patterns.none? { |r| r.match?(dir_name) }
            next if exc_patterns.any? { |r| r.match?(dir_name) }

            manifest_file = File.join(plugin_dir, "plugin.json")
            next unless File.file?(manifest_file)

            plugin = parse_plugin(plugin_dir, manifest_file, dir_name)
            @plugins[dir_name] = plugin if plugin
          end
        end

        def parse_plugin(plugin_dir, manifest_file, dir_name)
          manifest = JSON.parse(File.read(manifest_file, encoding: "UTF-8")) rescue {}
          name = manifest["name"] || dir_name
          disabled = !!manifest["disabled"]

          skills_dir = File.join(plugin_dir, "skills")
          rules_dir = File.join(plugin_dir, "rules")
          hooks_file = File.join(plugin_dir, "hooks.json")
          mcp_file = File.join(plugin_dir, "mcp_config.json")

          {
            name:,
            dir_name:,
            dir: plugin_dir,
            manifest:,
            disabled:,
            skills_dir: File.directory?(skills_dir) ? skills_dir : nil,
            rules_dir: File.directory?(rules_dir) ? rules_dir : nil,
            hooks_file: File.file?(hooks_file) ? hooks_file : nil,
            mcp_file: File.file?(mcp_file) ? mcp_file : nil,
          }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.plugins.parse", manifest_file:)
          nil
        end

        def load_user_config
          return {} unless File.file?(@config_file)

          JSON.parse(File.read(@config_file, encoding: "UTF-8")) rescue {}
        end

        def save_user_config
          require "fileutils"
          FileUtils.mkdir_p(File.dirname(@config_file))
          File.write(@config_file, JSON.pretty_generate(@user_config))
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.plugins.save_user_config")
        end
      end
    end
  end
end
