# frozen_string_literal: true

require "fileutils"

module Master
  module Ground
    # Session adherence posture restored from fossil master.yml modes.
    # Source of truth: data/limits.yml#session_modes + ENV MASTER_MODE.
    class ModePosture
      MODES = %w[loose balanced strict].freeze
      STATE_REL = File.join(".master", "mode").freeze

      def self.current(root: Master::ROOT)
        new(root:).current
      end

      def self.set!(mode, root: Master::ROOT)
        new(root:).set!(mode)
      end

      def initialize(root: Master::ROOT)
        @root = root
        @cfg = load_cfg
      end

      def current = describe(resolve_name)

      # The resolved settings for any named mode, not only the active one, so
      # `/mode list` can show what each posture does without switching into it.
      def describe(name)
        key = name.to_s.strip.downcase
        spec = modes[key] || modes["balanced"] || {}
        {
          name: key,
          scan_profile: spec["scan_profile"] || "full",
          council: spec["council"],
          autofix_llm: truthy?(spec.fetch("autofix_llm", true)),
          autofix_mechanical: truthy?(spec.fetch("autofix_mechanical", true)),
          max_fix_passes: Integer(spec["max_fix_passes"] || 8),
          severity_floor: spec["severity_floor"],
          description: spec["description"].to_s,
        }
      end

      def set!(mode)
        name = mode.to_s.strip.downcase
        raise ArgumentError, "unknown mode #{mode.inspect}; use #{MODES.join("|")}" unless MODES.include?(name)

        path = state_path
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{name}\n")
        ENV["MASTER_MODE"] = name
        current
      end

      # Defaults to the active posture; takes a spec so `/mode list` renders
      # every mode through the same formatter the status line already uses.
      def line(spec = current)
        council = case spec[:council]
                  when true then "council=on"
                  when false then "council=off"
                  else "council=#{spec[:council]}"
                  end
        "mode=#{spec[:name]} profile=#{spec[:scan_profile]} #{council} fix_passes=#{spec[:max_fix_passes]}"
      end

      private

      def resolve_name
        env = ENV["MASTER_MODE"].to_s.strip.downcase
        return env if MODES.include?(env)

        if File.file?(state_path)
          disk = File.read(state_path).to_s.strip.downcase
          return disk if MODES.include?(disk)
        end

        default = @cfg["default"].to_s
        MODES.include?(default) ? default : "balanced"
      end

      def modes
        @cfg["modes"] || {}
      end

      def state_path
        File.join(@root, STATE_REL)
      end

      def load_cfg
        data = Master.load_yaml(Master.limits_path, default: {}) || {}
        data["session_modes"] || { "default" => "balanced", "modes" => {} }
      rescue StandardError
        { "default" => "balanced", "modes" => {} }
      end

      def truthy?(value)
        value == true || value.to_s == "true" || value.to_s == "1"
      end
    end
  end
end
