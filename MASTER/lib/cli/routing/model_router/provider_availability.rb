# frozen_string_literal: true

module Master
  module CLI
    module Routing
      class ModelRouter
        # Which provider lanes are reachable right now (Grok API key, claude
        # CLI binary, keyless web-chat, live free-tier catalog) — separate
        # from ModelRouter's own preference/escalation/failover logic.
        module ProviderAvailability
          # Grok/OpenRouter API when a key is present; then the agy CLI when its
          # binary exists; subscription Opus when claude binary exists; browser
          # web-chat when keyless. A configured API key leads because it is a
          # paid, health-checked lane — the agy CLI answers "quota reached" when
          # its subscription is spent, so prepending it made agy:auto the active
          # model and stalled every LLM-backed rule. Paid APIs stay in flattened
          # tiers for escalation.
          def primary_models
            models = []
            models.concat(grok_api_models) if grok_api_available?
            if agy_cli_available?
              agy_ids = Array(@rules.dig("models", "primary")).filter_map { |m| m["id"] }
                .select { |id| id.to_s.start_with?("agy:") || id.to_s == "agy" }
              agy_ids << "agy:auto" if agy_ids.empty?
              models.concat(agy_ids)
            end
            models.concat(keyless_web_chat_models) if keyless_mode?
            if claude_cli_available?
              models.concat(
                Array(@rules.dig("models", "primary")).filter_map { |m| m["id"] }
                  .select { |id| id.to_s.start_with?("claude-cli:") },
              )
            end
            models.uniq
          end

          def agy_cli_available?
            return false if ENV["MASTER_NO_AGY_CLI"] == "1"
            return @agy_cli_available unless @agy_cli_available.nil?
            @agy_cli_available = !find_agy_executable.nil?
          end

          def find_agy_executable
            if ENV["AGY_BIN"] && File.file?(ENV["AGY_BIN"]) && File.executable?(ENV["AGY_BIN"])
              return ENV["AGY_BIN"]
            end
            home_bin = File.expand_path("~/.local/bin/agy")
            return home_bin if File.file?(home_bin) && File.executable?(home_bin)

            ENV["PATH"].to_s.split(File::PATH_SEPARATOR).each do |dir|
              candidate = File.join(dir, "agy")
              return candidate if File.file?(candidate) && File.executable?(candidate)
            end
            nil
          end

          def grok_api_models
            Array(@rules.dig("models", "grok_primary")).filter_map { |m| m["id"] }
          end

          def grok_api_available?
            Master.api_key_present?("XAI_API_KEY") || Master.api_key_present?("OPENROUTER_API_KEY")
          end

          def keyless_web_chat_models
            return [] unless web_chat_enabled?
            Array(@rules.dig("ferrum_web_chat", "free_latest"))
          end

          def keyless_mode?
            return true if ENV["MASTER_KEYLESS"].to_s != ""
            return true if auto_keyless? && !Master.any_api_key_present?
            false
          end

          def claude_cli_available?
            return false if ENV["MASTER_NO_CLAUDE_CLI"] == "1"
            return @claude_cli_available unless @claude_cli_available.nil?
            @claude_cli_available = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
              exe = File.join(dir, "claude")
              File.file?(exe) && File.executable?(exe)
            end
          end

          def continuity_models
            return [] if @rules.dig("continuity", "enabled") == false
            latest = [@rules.dig("openrouter", "free_latest"), live_free_models]
            latest << @rules.dig("ferrum_web_chat", "free_latest") if web_chat_enabled?
            latest.flatten.compact.uniq
          end

          def web_chat_enabled?
            return false if ENV["MASTER_NO_WEB_CHAT"] == "1"
            return true if keyless_mode?
            gate = @rules.dig("ferrum_web_chat", "enabled_when_env").to_s
            gate.empty? ? false : ENV[gate].to_s != ""
          end

          def auto_keyless?
            @rules.dig("ferrum_web_chat", "auto_when_keyless") != false
          end

          def web_chat_model?(model_id) = model_id.to_s.start_with?("web-chat:")

          # Live free slugs refreshed into the SQLite catalog; read-only, never creates the DB.
          def live_free_models
            return [] unless @rules.dig("openrouter", "use_live_catalog")
            require_relative "../../../io/catalog_index"
            db = Master::Io::CatalogIndex::DEFAULT_DB
            return [] unless File.exist?(db)
            rows = Master::Io::CatalogIndex.new(db_path: db).search(":free", source: "openrouter", limit: 40)
            rows.filter_map { |row| row["id"] }.select { |id| id.to_s.end_with?(":free") }
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.live_free_models")
            []
          end
        end
      end
    end
  end
end
