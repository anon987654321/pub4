# frozen_string_literal: true

module Master
  module Io
    # Rotate across multiple keys of one provider to spread rate limits.
    # OpenRouter :free and openrouter/ lanes rotate the openrouter.keys_env
    # list through RubyLLM's configuration; a hosted endpoint lane
    # ("groq:llama-...") rotates that endpoint's own key_env list, which the
    # hosted sender resolves per call (HttpSender#send_hosted), so a rotation
    # takes effect without rebuilding the router's endpoint index. Pins one
    # key per provider between rotations and advances only on
    # rate-limit/quota outcomes (the OpenClaw pattern). A single configured
    # key makes every method a no-op.
    module KeyRotator
      ROTATABLE_RE = /:free\z|\Aopenrouter\//.freeze

      @mutex = Mutex.new
      @index = 0
      @positions = {}

      module_function

      def env_vars
        vars = Master.models_config.dig("openrouter", "keys_env")
        configured = Array(vars).map(&:to_s).reject(&:empty?)
        configured.empty? ? %w[OPENROUTER_API_KEY] : configured
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "KeyRotator.env_vars")
        raise "key rotation policy unreadable: #{e.class}: #{e.message}"
      end

      # The hosted endpoint's declared key list (models.yml
      # openai_compatible.<name>.key_env). Empty for a name the catalogue does
      # not declare; the catalogue guard owns the field's schema.
      def hosted_env_vars(name)
        vars = Master.models_config.dig("openai_compatible", name.to_s, "key_env")
        Array(vars).map(&:to_s).reject(&:empty?)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "KeyRotator.hosted_env_vars", provider: name.to_s)
        []
      end

      def keys(vars = env_vars)
        vars.map { |var| ENV[var].to_s }
            .reject { |key| key.length < Master::MIN_API_KEY_LENGTH_HEURISTIC }
            .uniq
      end

      # A hosted lane id ("groq:llama-...") names a rotating provider only when
      # the catalogue declares a key_env list for it; every other id shape
      # (web-chat:, ollama:, bare vendor slugs) answers nil.
      def hosted_name(model)
        id = model.to_s
        name = id.split(":", 2).first
        return nil unless id.include?(":") && !name.to_s.empty?

        name if hosted_env_vars(name).any?
      end

      def active_key
        all = keys
        return if all.empty?
        @mutex.synchronize { all[@index % all.size] }
      end

      # The hosted lane's active key, read at call time.
      def active_key_for(name)
        all = keys(hosted_env_vars(name))
        return if all.empty?
        @mutex.synchronize { all[positions(name) % all.size] }
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
        if (name = hosted_name(model.to_s))
          return false if keys(hosted_env_vars(name)).size < 2

          @mutex.synchronize { @positions[name] = positions(name) + 1 }
          return true
        end
        return false unless ROTATABLE_RE.match?(model.to_s)
        return false if keys.size < 2
        @mutex.synchronize { @index += 1 }
        configure_current!
      end

      def positions(name) = @positions.fetch(name, 0)
    end
  end
end
