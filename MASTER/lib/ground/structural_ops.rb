# frozen_string_literal: true

module Master
  module Ground
    # Loads structural_ops taxonomy from rules.yml — verbs the rewriter may apply.
    class StructuralOps
      RULES_PATH = Master::RULES_PATH

      @mutex = Mutex.new
      @cache = nil
      @mtime = nil

      class << self
        def load!
          @mutex.synchronize do
            mtime = File.mtime(RULES_PATH)
            if @cache.nil? || mtime != @mtime
              raw = Master.load_yaml(RULES_PATH) || {}
              @cache = normalize(raw.fetch("structural_ops", {}))
              @mtime = mtime
            end
            @cache
          end
        end

        def ops
          load!.fetch(:ops, {})
        end

        def verify_after_each?
          load!.fetch(:verify_after_each, true)
        end

        def allowed_verbs
          ops.keys.map(&:to_s)
        end

        def prompt_section
          lines = ["Structural operations (apply only when they eliminate the violation):"]
          ops.each do |verb, spec|
            desc = spec[:desc] || spec["desc"]
            risk = spec[:risk] || spec["risk"]
            law = spec[:supports_law] || spec["supports_law"]
            verify = spec[:verify] || spec["verify"]
            lines << "- #{verb}: #{desc} (risk=#{risk}, law=#{law}, verify=#{verify})"
          end
          lines << "Verify after each structural op." if verify_after_each?
          lines.join("\n")
        end

        def risk_for(verb)
          spec = ops[verb.to_sym] || ops[verb.to_s]
          (spec && (spec[:risk] || spec["risk"])).to_s
        end

        private

        def normalize(section)
          {
            preserve_note: section["preserve_note"] || section[:preserve_note],
            verify_after_each: section.fetch("verify_after_each", true),
            ops: (section["ops"] || section[:ops] || {}).transform_keys(&:to_sym)
          }
        end
      end
    end
  end
end