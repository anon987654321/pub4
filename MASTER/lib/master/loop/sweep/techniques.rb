# frozen_string_literal: true

module Master
  module Loop
  class Sweep
    module Techniques
      module_function

      def all
        path = Sweep::PROMPTS_PATH
        @all ||= (Master.load_yaml(path)["techniques"] || []).map { |e| e.transform_keys(&:to_s) }
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
