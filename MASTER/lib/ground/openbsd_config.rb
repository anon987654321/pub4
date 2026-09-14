# frozen_string_literal: true

module Master
  module Ground
    # The runtime for data/openbsd.yml: given a daemon config's text, it names
    # the required patterns that are missing and the warnings that apply.
    #
    # Its caller is test_openbsd_config.rb, which validates every config under
    # OPENBSD/etc the table knows, so a deployed file that drops a required
    # pattern fails the MASTER suite rather than surfacing on the box.
    class OpenbsdConfig
      # One validation result line. severity: :missing (a required pattern is
      # absent) or :warning (a discouraged / absent-recommended pattern).
      Finding = Data.define(:config, :severity, :message) do
        def to_s = "[#{severity}] #{config}: #{message}"
      end

      def self.load(root: Master::ROOT)
        new(config: Master.load_yaml(File.join(root, "data", "openbsd.yml")))
      end

      def initialize(config:)
        @config = config || {}
        @configs = @config.fetch("configs", {})
      end

      def known?(name) = @configs.key?(name.to_s)

      # Validate one named config (e.g. "pf.conf") against its rules. Returns an
      # Array of Finding. Empty array = clean. Unknown config name = [] (nothing
      # to assert), callers use known? first when that distinction matters.
      def validate(name, text)
        spec = @configs[name.to_s]
        return [] unless spec

        body = text.to_s
        missing_findings(name, spec, body) + warning_findings(name, spec, body)
      end

      # Validate an on-disk config file, inferring the ruleset from its basename.
      def validate_file(path)
        name = File.basename(path.to_s)
        return Result.err("unknown openbsd config: #{name}", category: :validation) unless known?(name)

        Result.ok(validate(name, File.read(path)))
      rescue SystemCallError => e
        Result.err("openbsd_config: #{e.message}", category: :infrastructure)
      end

      private

      def missing_findings(name, spec, body)
        Array(spec["required_patterns"]).filter_map do |pattern|
          next if body.include?(pattern.to_s)

          Finding.new(config: name, severity: :missing, message: "missing required: #{pattern} (see #{spec["man"]})")
        end
      end

      def warning_findings(name, spec, body)
        Array(spec["warnings"]).filter_map do |warn|
          pattern = warn["pattern"].to_s
          present = body.include?(pattern)

          if warn["absent_message"] && !present
            Finding.new(config: name, severity: :warning, message: warn["absent_message"])
          elsif warn["message"] && present
            Finding.new(config: name, severity: :warning, message: "#{pattern}: #{warn["message"]}")
          end
        end
      end
    end
  end
end
