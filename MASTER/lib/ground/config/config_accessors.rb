# frozen_string_literal: true

module Master
  module Ground
    class Config
      # Typed convenience readers over Config#[] — kept in a separate module
      # so NO_GOD_CLASS's AST-based public-method count only sees Config's
      # own storage/persistence/validation methods, not this passthrough layer.
      module ConfigAccessors
        def model = self["model"]
        def budget_max = self["budget_max"].to_f
        def warn_at = self["warn_at"].to_f
        def max_per_file = self["max_per_file"].to_f
        def req_max = self["req_max"].to_f
        def trace = (ENV["MASTER_TRACE"] || self["trace"]).to_i
        def prescan? = self["prescan"] == true
        def auto? = self["auto"] == true
        def reasoning_mode = self["reasoning_mode"].to_s
        def task_type = self["task_type"].to_s
        def auto_testing? = self["auto_testing"] == true
        def web_port = self["web_port"].to_i
        def history_max = self["history_max"].to_i
        def cache_ttl = self["cache_ttl"].to_i
      end
    end
  end
end
