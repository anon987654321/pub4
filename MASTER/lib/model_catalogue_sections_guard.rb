# frozen_string_literal: true

module Master
  # Validates the nested provider-lane and media-lane catalogues inside models.yml.
  # Kept separate from tier identity/routing so each schema has one responsibility.
  module ModelCatalogueSectionsGuard
    module_function

    def validate(data, tiers:, errors:)
      strict_fields(data["routing"], %w[enabled strategy escalation_enabled escalation_tier provider],
                    "models.yml routing", errors)
      routing_config = data["routing"].is_a?(Hash) ? data["routing"] : {}
      unless tiers.key?(routing_config["escalation_tier"])
        errors << "models.yml routing.escalation_tier must reference a declared model tier"
      end
      strict_fields(data["fallback_policy"], ["on"], "models.yml fallback_policy", errors)
      strict_fields(data["failover"],
                    %w[sequence cooldown_seconds cooldown_tiers skip_ttl_ms transient_skip_ttl_ms max_retries],
                    "models.yml failover", errors)
      strict_fields(data["defaults"], ["score"], "models.yml defaults", errors)
      strict_fields(data["continuity"], %w[enabled updated_at], "models.yml continuity", errors)
      continuity = data["continuity"].is_a?(Hash) ? data["continuity"] : {}
      errors << "models.yml continuity.enabled must be boolean" unless [true, false].include?(continuity["enabled"])
      errors << "models.yml continuity.updated_at must be non-empty text" unless
        continuity["updated_at"].is_a?(String) && !continuity["updated_at"].strip.empty?

      strict_fields(data["openrouter"], %w[use_live_catalog daily_quota_per_model keys_env free_latest],
                    "models.yml openrouter", errors)
      openrouter = data["openrouter"].is_a?(Hash) ? data["openrouter"] : {}
      errors << "models.yml openrouter.use_live_catalog must be boolean" unless [true, false].include?(openrouter["use_live_catalog"])
      errors << "models.yml openrouter.daily_quota_per_model must be a positive integer" unless
        openrouter["daily_quota_per_model"].is_a?(Integer) && openrouter["daily_quota_per_model"].positive?
      validate_string_list(openrouter["keys_env"], "models.yml openrouter.keys_env", errors, nonempty: true)
      validate_string_list(openrouter["free_latest"], "models.yml openrouter.free_latest", errors, nonempty: true)

      strict_fields(data["ferrum_web_chat"],
                    %w[enabled_when_env auto_when_keyless profile_dir free_latest providers],
                    "models.yml ferrum_web_chat", errors)
      ferrum = data["ferrum_web_chat"].is_a?(Hash) ? data["ferrum_web_chat"] : {}
      %w[enabled_when_env profile_dir].each do |field|
        errors << "models.yml ferrum_web_chat.#{field} must be non-empty text" unless
          ferrum[field].is_a?(String) && !ferrum[field].strip.empty?
      end
      errors << "models.yml ferrum_web_chat.auto_when_keyless must be boolean" unless
        [true, false].include?(ferrum["auto_when_keyless"])
      validate_string_list(ferrum["free_latest"], "models.yml ferrum_web_chat.free_latest", errors, nonempty: true)
      ferrum_providers = ferrum["providers"].is_a?(Hash) ? ferrum["providers"] : {}
      ferrum_providers.each do |name, row|
        strict_fields(row, %w[url input_selector reply_selector timeout], "models.yml ferrum_web_chat.providers.#{name}", errors)
        next unless row.is_a?(Hash)

        %w[url input_selector reply_selector].each do |field|
          errors << "models.yml ferrum_web_chat.providers.#{name}.#{field} must be non-empty text" unless
            row[field].is_a?(String) && !row[field].strip.empty?
        end
        errors << "models.yml ferrum_web_chat.providers.#{name}.timeout must be positive" unless
          row["timeout"].is_a?(Numeric) && row["timeout"].positive?
      end
      errors << "models.yml ferrum_web_chat.providers must not be empty" if ferrum_providers.empty?

      strict_fields(data["three_mirror_redundancy"], %w[pool quorum], "models.yml three_mirror_redundancy", errors)
      mirrors = data["three_mirror_redundancy"].is_a?(Hash) ? data["three_mirror_redundancy"] : {}
      validate_string_list(mirrors["pool"], "models.yml three_mirror_redundancy.pool", errors, nonempty: true)
      errors << "models.yml three_mirror_redundancy.quorum must be between 1 and pool size" unless
        mirrors["quorum"].is_a?(Integer) && mirrors["quorum"].positive? &&
        mirrors["pool"].is_a?(Array) && mirrors["quorum"] <= mirrors["pool"].size

      cli_lanes = data["cli_lanes"].is_a?(Hash) ? data["cli_lanes"] : {}
      cli_lanes.each do |name, row|
        label = "models.yml cli_lanes.#{name}"
        strict_fields(row, %w[binary signed_in ask model_flag models login], label, errors)
        next unless row.is_a?(Hash)

        %w[binary model_flag login].each do |field|
          errors << "#{label}.#{field} must be non-empty text" unless row[field].is_a?(String) && !row[field].strip.empty?
        end
        validate_string_list(row["ask"], "#{label}.ask", errors, nonempty: true)
        validate_string_list(row["models"], "#{label}.models", errors, nonempty: true)
        strict_fields(row["signed_in"], %w[args match refuse], "#{label}.signed_in", errors)
        signed = row["signed_in"]
        if signed.is_a?(Hash)
          validate_string_list(signed["args"], "#{label}.signed_in.args", errors, nonempty: true)
          if signed.key?("match") && !(signed["match"].is_a?(String) && !signed["match"].empty?)
            errors << "#{label}.signed_in.match must be non-empty text"
          end
          if signed.key?("refuse") && !(signed["refuse"].is_a?(String) && !signed["refuse"].empty?)
            errors << "#{label}.signed_in.refuse must be non-empty text"
          end
          errors << "#{label}.signed_in must declare match or refuse" unless signed.key?("match") || signed.key?("refuse")
        end
      end

      compatible = data["openai_compatible"].is_a?(Hash) ? data["openai_compatible"] : {}
      compatible.each do |name, row|
        label = "models.yml openai_compatible.#{name}"
        strict_fields(row, %w[base key_env keyless_max_concurrency concurrency_wait_seconds quota_bucket keyless],
                      label, errors)
        next unless row.is_a?(Hash)

        errors << "#{label}.base must be a non-empty URL" unless row["base"].is_a?(String) && row["base"].match?(/\Ahttps?:\/\//)
        validate_string_list(row["key_env"], "#{label}.key_env", errors, nonempty: true)
        %w[keyless_max_concurrency concurrency_wait_seconds].each do |field|
          next unless row.key?(field)

          errors << "#{label}.#{field} must be positive" unless row[field].is_a?(Numeric) && row[field].positive?
        end
        if row.key?("quota_bucket")
          errors << "#{label}.quota_bucket must be non-empty text" unless row["quota_bucket"].is_a?(String) && !row["quota_bucket"].empty?
        end
        if row.key?("keyless")
          strict_fields(row["keyless"], %w[tier usage_based_only], "#{label}.keyless", errors)
          keyless = row["keyless"]
          if keyless.is_a?(Hash)
            errors << "#{label}.keyless.tier must be non-empty text" unless keyless["tier"].is_a?(String) && !keyless["tier"].empty?
            if keyless.key?("usage_based_only")
              errors << "#{label}.keyless.usage_based_only must be boolean" unless [true, false].include?(keyless["usage_based_only"])
            end
          end
        end
      end

      strict_fields(data["ollama"], %w[default_base_url keep_alive max_num_ctx local_model_allowlist],
                    "models.yml ollama", errors)
      ollama = data["ollama"].is_a?(Hash) ? data["ollama"] : {}
      %w[default_base_url keep_alive].each do |field|
        errors << "models.yml ollama.#{field} must be non-empty text" unless ollama[field].is_a?(String) && !ollama[field].empty?
      end
      errors << "models.yml ollama.max_num_ctx must be a positive integer" unless ollama["max_num_ctx"].is_a?(Integer) && ollama["max_num_ctx"].positive?
      validate_string_list(ollama["local_model_allowlist"], "models.yml ollama.local_model_allowlist", errors, nonempty: true)

      strict_fields(data["free_tier"], %w[neutral_latency_s unmeasured_timeout_s call_timeout_s],
                    "models.yml free_tier", errors)
      free_tier = data["free_tier"].is_a?(Hash) ? data["free_tier"] : {}
      free_tier.each do |field, value|
        errors << "models.yml free_tier.#{field} must be positive" unless value.is_a?(Numeric) && value.positive?
      end

      strict_fields(data["paid_tail"],
                    %w[enabled max_prompt_usd_per_m max_completion_usd_per_m run_cap_usd max_models],
                    "models.yml paid_tail", errors)
      paid = data["paid_tail"].is_a?(Hash) ? data["paid_tail"] : {}
      errors << "models.yml paid_tail.enabled must be boolean" unless [true, false].include?(paid["enabled"])
      %w[max_prompt_usd_per_m max_completion_usd_per_m run_cap_usd].each do |field|
        errors << "models.yml paid_tail.#{field} must be positive" unless paid[field].is_a?(Numeric) && paid[field].positive?
      end
      errors << "models.yml paid_tail.max_models must be a positive integer" unless paid["max_models"].is_a?(Integer) && paid["max_models"].positive?

      strict_fields(data["media_lanes"],
                    %w[budget_usd call_cap_usd image_tokens video_seconds timeouts catalog_merge providers image video],
                    "models.yml media_lanes", errors)
      media = data["media_lanes"].is_a?(Hash) ? data["media_lanes"] : {}
      %w[budget_usd call_cap_usd].each do |field|
        validate_fields(media[field], %w[image video], "models.yml media_lanes.#{field}", errors)
        values = media[field].is_a?(Hash) ? media[field] : {}
        %w[image video].each do |kind|
          errors << "models.yml media_lanes.#{field}.#{kind} must be positive" unless values[kind].is_a?(Numeric) && values[kind].positive?
        end
      end
      %w[image_tokens video_seconds].each do |field|
        errors << "models.yml media_lanes.#{field} must be a positive integer" unless media[field].is_a?(Integer) && media[field].positive?
      end
      strict_fields(media["timeouts"], %w[call_s video_total_s poll_s max_polls], "models.yml media_lanes.timeouts", errors)
      timeouts = media["timeouts"].is_a?(Hash) ? media["timeouts"] : {}
      timeouts.each do |field, value|
        errors << "models.yml media_lanes.timeouts.#{field} must be positive" unless value.is_a?(Numeric) && value.positive?
      end
      strict_fields(media["catalog_merge"], %w[max_prompt_usd_per_m max_models], "models.yml media_lanes.catalog_merge", errors)
      catalog_merge = media["catalog_merge"].is_a?(Hash) ? media["catalog_merge"] : {}
      errors << "models.yml media_lanes.catalog_merge.max_prompt_usd_per_m must be positive" unless
        catalog_merge["max_prompt_usd_per_m"].is_a?(Numeric) && catalog_merge["max_prompt_usd_per_m"].positive?
      errors << "models.yml media_lanes.catalog_merge.max_models must be a positive integer" unless
        catalog_merge["max_models"].is_a?(Integer) && catalog_merge["max_models"].positive?
      media_providers = media["providers"].is_a?(Hash) ? media["providers"] : {}
      media_providers.each do |name, row|
        strict_fields(row, %w[env base], "models.yml media_lanes.providers.#{name}", errors)
        next unless row.is_a?(Hash)

        validate_string_list(row["env"], "models.yml media_lanes.providers.#{name}.env", errors, nonempty: true)
        if row.key?("base")
          errors << "models.yml media_lanes.providers.#{name}.base must be a non-empty URL" unless
            row["base"].is_a?(String) && row["base"].match?(/\Ahttps?:\/\//)
        end
      end
      %w[image video].each do |kind|
        rows = media[kind]
        unless rows.is_a?(Array) && !rows.empty?
          errors << "models.yml media_lanes.#{kind} must be a non-empty list"
          next
        end
        rows.each_with_index do |row, index|
          label = "models.yml media_lanes.#{kind}[#{index}]"
          allowed = %w[provider model price_id usd_per_call usd_per_second image_tokens]
          strict_fields(row, allowed, label, errors)
          next unless row.is_a?(Hash)

          errors << "#{label}.provider must name a declared media provider" unless
            row["provider"].is_a?(String) && media_providers.key?(row["provider"])
          errors << "#{label}.model must be non-empty text" unless row["model"].is_a?(String) && !row["model"].empty?
          %w[price_id].each do |field|
            next unless row.key?(field)

            errors << "#{label}.#{field} must be non-empty text" unless row[field].is_a?(String) && !row[field].empty?
          end
          %w[usd_per_call usd_per_second].each do |field|
            next unless row.key?(field)

            errors << "#{label}.#{field} must be positive" unless row[field].is_a?(Numeric) && row[field].positive?
          end
          if row.key?("image_tokens")
            errors << "#{label}.image_tokens must be a positive integer" unless row["image_tokens"].is_a?(Integer) && row["image_tokens"].positive?
          end
        end
      end
    end

    def strict_fields(value, allowed, label, errors)
      validate_fields(value, allowed, label, errors)
    end

    def validate_fields(value, allowed, label, errors)
      unless value.is_a?(Hash)
        errors << "#{label} must be a mapping"
        return false
      end
      unknown = value.keys.map(&:to_s) - allowed
      errors << "#{label} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
      true
    end

    def validate_string_list(value, label, errors, nonempty: false)
      valid = value.is_a?(Array) && (!nonempty || !value.empty?) &&
              value.all? { |item| item.is_a?(String) && !item.strip.empty? }
      errors << "#{label} must be a list of non-empty strings" unless valid
      valid
    end

  end
end
