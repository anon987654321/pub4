# frozen_string_literal: true

require "fileutils"
require "yaml"

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
          return if %w[full elevated].include?(key)

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
          data = Master.agent_taxonomy
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

      # The authority an objective acts under. A standing order names one domain,
      # and the domain names what it may reach: `commands` is the turn router, and
      # through it the fold and every coding tool; `callables` is reviewed order
      # code; `exec` runs a verify; `memory` is the shared store that holds what
      # every other domain has learned. A finance or household objective reaches
      # none of the coding ones and no other domain's memory.
      #
      # Domains marked `consent: required` are off until the operator grants each
      # one by name. The grant is operator state in .master/, never data/: a
      # consent is a decision about this machine, not a default for every clone.
      module Domain
        DEFAULT = "coding"
        CONSENT_PATH = File.join(Master::ROOT, ".master", "domain_consent.yml").freeze
        # What each capability puts in an order's container. A key no domain
        # reaches is removed, so callable code cannot find it by accident.
        CONTAINER_KEYS = { "commands" => %i[commands agent tools pipeline scanner], "memory" => %i[memory] }.freeze

        module_function

        def table
          rows = (Master.load_yaml(Profile::CONFIG_PATH) || {}).dig("tools", "domains")
          rows.is_a?(Hash) ? rows : {}
        end

        def consented?(name)
          row = table[name.to_s] or return false

          row["consent"] != "required" || granted.include?(name.to_s)
        end

        # Why `name` may not use `capability`, or nil when it may.
        def refusal(name, capability)
          row = table[name.to_s]
          return "unknown domain #{name}" unless row
          return "domain #{name} is off until the operator consents: /orders consent #{name}" unless consented?(name)
          return if Array(row["reach"]).include?(capability.to_s)

          "domain #{name} cannot reach #{capability}"
        end

        def container(name, full)
          withheld = CONTAINER_KEYS.reject { |capability, _| refusal(name, capability).nil? }.values.flatten
          full.reject { |key, _| withheld.include?(key) }.merge(domain: name.to_s)
        end

        def grant(name) = record_consent(name) { |names| names | [name.to_s] }
        def revoke(name) = record_consent(name) { |names| names - [name.to_s] }

        def granted
          return [] unless File.file?(CONSENT_PATH)

          Array(Master.load_yaml(CONSENT_PATH)).map(&:to_s)
        rescue StandardError => e
          Swallow.log(e, context: "Tool::Domain.granted", path: CONSENT_PATH)
          []
        end

        def record_consent(name)
          return "unknown domain #{name}" unless table.key?(name.to_s)

          FileUtils.mkdir_p(File.dirname(CONSENT_PATH))
          File.write(CONSENT_PATH, yield(granted).to_yaml)
          "#{name}: #{consented?(name) ? "on" : "off"}"
        end
      end

      module Protocol

        CLAIM_WORDS = /\b(read|fetched|opened|searched|ran|executed|wrote|created|updated|
                           deleted|patched|committed|verified)\b/xi.freeze
        COMMAND_BLOCK = /```(?:bash|sh|zsh|python|ruby|powershell|shell)\b/i.freeze

        REQUIREMENTS = [
          "Never claim a command, file read, web fetch, or repo write happened unless a tool result proves it.",
          "Prefer action over narration when a tool can do the work.",
          "Do not output shell/code blocks as pretend execution.",
          "After tool use, provide a final text response that separates landed work from failures.",
          "For repo work, name the changed file, exposed symbol, caller, and verification result.",
        ].freeze

        module_function

        def fake_execution_risk?(text)
          text.to_s.match?(COMMAND_BLOCK)
        end

        def operational_claim?(text)
          text.to_s.match?(CLAIM_WORDS)
        end

        def brief
          "Tool protocol:\n- #{REQUIREMENTS.join("\n- ")}"
        end
      end
    end
  end
end
