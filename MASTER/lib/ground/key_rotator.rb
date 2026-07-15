# frozen_string_literal: true

module Master
  module Ground
    # Rotate across multiple OpenRouter keys to spread free-tier rate limits.
    # Pins one key between rotations and advances only on rate-limit/quota outcomes
    # (the OpenClaw pattern). A single configured key makes every method a no-op.
    module KeyRotator
      ROTATABLE_RE = /:free\z|\Aopenrouter\//.freeze

      @mutex = Mutex.new
      @index = 0

      module_function

      def env_vars
        vars = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml")).dig("openrouter", "keys_env")
        Array(vars).empty? ? %w[OPENROUTER_API_KEY] : Array(vars)
      rescue StandardError
        %w[OPENROUTER_API_KEY]
      end

      def keys
        env_vars.map { |var| ENV[var].to_s }
                .reject { |key| key.length < Master::MIN_API_KEY_LENGTH_HEURISTIC }
                .uniq
      end

      def active_key
        all = keys
        return if all.empty?
        @mutex.synchronize { all[@index % all.size] }
      end

      def configure_current!
        key = active_key
        return false if key.nil?
        RubyLLM.configure { |cfg| cfg.openrouter_api_key = key }
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "KeyRotator.configure_current!")
        false
      end

      def rotate_for(model)
        return false unless ROTATABLE_RE.match?(model.to_s)
        return false if keys.size < 2
        @mutex.synchronize { @index += 1 }
        configure_current!
      end
    end
  end
end
