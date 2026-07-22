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

      def current
        name = resolve_name
        spec = modes[name] || modes["balanced"] || {}
        {
          name:,
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

      def line
        c = current
        council = case c[:council]
                  when true then "council=on"
                  when false then "council=off"
                  else "council=#{c[:council]}"
                  end
        "mode=#{c[:name]} profile=#{c[:scan_profile]} #{council} fix_passes=#{c[:max_fix_passes]}"
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
