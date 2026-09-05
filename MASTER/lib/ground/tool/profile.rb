# frozen_string_literal: true

module Master
  module Ground
    module Tool
      # Three tool surfaces. public is the open internet; messaging is a paired
      # visitor (fetch + personal memory, never Shell); full is an authenticated
      # operator. Elevation still gates dangerous tools inside full.
      module Profile
        CONFIG_PATH = Master.data_path("security.yml").freeze
        NAMES = %i[public messaging full elevated].freeze
        FALLBACK = {
          "public" => %w[AskLlm WebSearch SubdomainOrchestrator],
          "messaging" => %w[AskLlm WebSearch SubdomainOrchestrator WebFetch MemoryRecord],
        }.freeze

        module_function

        def current
          return :public if Fiber[:master_visitor] && !Fiber[:master_paired]
          return :messaging if Fiber[:master_visitor] && Fiber[:master_paired]
          return :elevated if Fiber[:master_elevated]

          :full
        end

        def current_name = current.to_s

        def allowlist(profile = current)
          key = profile.to_s
          return nil if %w[full elevated].include?(key)

          configured = Array(profiles_config[key]).map(&:to_s)
          configured.empty? ? FALLBACK.fetch(key, []) : configured
        end

        def allow?(name, profile: current)
          list = allowlist(profile)
          return true if list.nil?

          list.include?(name.to_s)
        end

        def public_names = allowlist(:public)
        def messaging_names = allowlist(:messaging)

        def session_note
          case current
          when :public
            "Session scope: public visitor. Tools: #{public_names.join(', ')}. " \
              "Pairing required for personal memory."
          when :messaging
            "Session scope: paired messaging. Personal workspace loaded. Not a full operator session."
          when :elevated
            "Session scope: elevated operator. Dangerous tools unlocked."
          else
            build = group("build")
            suffix = build.empty? ? "" : " Build group: #{build.join(', ')}."
            "Session scope: full operator.#{suffix}"
          end
        end

        def groups
          data = Master.load_yaml(Master.data_path("agent_taxonomy.yml")) || {}
          hash = data["toolset_groups"]
          hash.is_a?(Hash) ? hash.transform_values { |names| Array(names).map(&:to_s) } : {}
        rescue StandardError => e
          Swallow.log(e, context: "ToolProfile.groups")
          {}
        end

        def group(name) = Array(groups[name.to_s])

        def profiles_config
          data = Master.load_yaml(CONFIG_PATH) || {}
          hash = data.dig("tools", "profiles")
          hash.is_a?(Hash) ? hash : {}
        rescue StandardError => e
          Swallow.log(e, context: "ToolProfile.profiles")
          {}
        end
      end
    end
  end
end
