# frozen_string_literal: true

require "pathname"
require_relative "json_config"

module Master
  module Ground
    module Antigravity
      # Discovery traverses directory trees and discovers Antigravity customization roots
      # across workspace projects, declared configs, global and built-in paths.
      class Discovery
        WORKSPACE_ROOT_DIRS = %w[.agents .agent _agents _agent].freeze
        GLOBAL_CONFIG_PATH = "~/.gemini/config"
        BUILTIN_PATH = "~/.gemini/antigravity-cli/builtin"

        attr_reader :workspace_root, :cwd

        def initialize(cwd: Dir.pwd, workspace_root: nil)
          @cwd = File.expand_path(cwd)
          @workspace_root = workspace_root ? File.expand_path(workspace_root) : find_repo_root(@cwd)
        end

        def find_repo_root(start_dir)
          current = Pathname.new(start_dir)
          loop do
            return current.to_s if (current + ".git").exist? || (current + ".agents").exist?
            break if current.root?

            current = current.parent
          end
          start_dir
        end

        # Discovers all active customization directories in precedence order:
        # 1. Workspace Project (.agents/)
        # 2. Declared JSON configs (skills.json, plugins.json in workspace)
        # 3. Global Discovery (~/.gemini/config/)
        # 4. Built-in Customizations (~/.gemini/antigravity-cli/builtin/)
        # 5. Global Declared JSON configs
        def workspace_customization_roots
          roots = []
          current = Pathname.new(@cwd)
          stop_at = Pathname.new(@workspace_root).parent

          while current && current != stop_at && !current.root?
            WORKSPACE_ROOT_DIRS.each do |name|
              candidate = current + name
              roots << candidate.to_s if candidate.directory?
            end
            current = current.parent
          end
          roots.uniq
        end

        def global_customization_root
          expanded = File.expand_path(GLOBAL_CONFIG_PATH)
          File.directory?(expanded) ? expanded : nil
        end

        def builtin_customization_root
          expanded = File.expand_path(BUILTIN_PATH)
          File.directory?(expanded) ? expanded : nil
        end

        def declared_skills_entries
          entries = []
          workspace_customization_roots.each do |root|
            cfg = File.join(root, "skills.json")
            entries.concat(JsonConfig.load(cfg, workspace_root: @workspace_root)) if File.file?(cfg)
          end
          entries
        end

        def declared_plugins_entries
          entries = []
          workspace_customization_roots.each do |root|
            cfg = File.join(root, "plugins.json")
            entries.concat(JsonConfig.load(cfg, workspace_root: @workspace_root)) if File.file?(cfg)
          end
          entries
        end

        def settings_files
          files = []
          workspace_customization_roots.each do |root|
            s = File.join(root, "settings.json")
            files << s if File.file?(s)
          end
          cli_settings = File.expand_path("~/.gemini/antigravity-cli/settings.json")
          files << cli_settings if File.file?(cli_settings)
          files.uniq
        end

        def hooks_files
          files = []
          workspace_customization_roots.each do |root|
            h = File.join(root, "hooks.json")
            files << h if File.file?(h)
          end
          if global_customization_root
            gh = File.join(global_customization_root, "hooks.json")
            files << gh if File.file?(gh)
          end
          files.uniq
        end

        def mcp_config_files
          files = []
          workspace_customization_roots.each do |root|
            m = File.join(root, "mcp_config.json")
            files << m if File.file?(m)
          end
          if global_customization_root
            gm = File.join(global_customization_root, "mcp_config.json")
            files << gm if File.file?(gm)
          end
          files.uniq
        end
      end
    end
  end
end
