# frozen_string_literal: true

module Master
  module Loop
  class Sweep
    # Typed view over data/sweep_prompts.yml's techniques: catalogue. Lets the
    # rewriter (or a future planner) filter by layer, risk, language, or path
    # without reparsing prose. The prose blocks remain the LLM-facing surface;
    # this is the Ruby-facing one.
    module Techniques
      PATH = File.join(Master::ROOT, "data", "sweep_prompts.yml").freeze

      module_function

      def all
        @all ||= (Master.load_yaml(PATH)["techniques"] || []).map { |e| e.transform_keys(&:to_s) }
      end

      def by_layer(layer)
        all.select { |t| t["layer"] == layer.to_s }
      end

      def by_risk(risk)
        all.select { |t| t["risk"] == risk.to_s }
      end

      def applicable_to(path:, lang:)
        all.select { |t| applies?(t, path: path, lang: lang) }
      end

      def applies?(entry, path:, lang:)
        spec = entry["applies_to"] || {}
        return false if spec["langs"] && !spec["langs"].map(&:to_s).include?(lang.to_s)
        return false if spec["path_includes"] && spec["path_includes"].none? { |g| File.fnmatch?(g, path) }
        return false if spec["path_excludes"]&.any? { |g| File.fnmatch?(g, path) }
        true
      end
    end
  end
  end
end
