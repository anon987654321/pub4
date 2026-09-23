# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

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

          # Ollama is a first-class local lane. localhost:11434 is the default daemon;
          # OLLAMA_BASE_URL can point elsewhere, and MASTER_NO_OLLAMA is the
          # explicit opt-out. When discovery cannot answer, the configured list
          # still provides a deterministic fallback.
          def ollama_enabled?
            return false if ENV["MASTER_NO_OLLAMA"] == "1"
            true
          end

def ollama_model?(model_id) = model_id.to_s.start_with?("ollama:", "ollama/")

# models.yml names the local chain, and a name nobody pulled answers
# "ollama has no model" and falls through to a paid provider. The daemon
# lists what it holds at /api/tags, so an enabled tier offers only those.
# When the daemon cannot say — down, slow, or answering nonsense — the
# configured list stands and the dispatcher names the failure per call.
def ollama_pulled?(model_id)
  return true if ollama_cloud_model?(model_id) && ollama_cloud_catalog.include?(model_id)
  installed = ollama_installed_models
  return true if installed.nil?

  name = model_id.to_s.sub(%r{\Aollama[:/]}, "")
  installed.include?(name) || installed.include?("#{name}:latest")
end

# Read once per router: the answer changes when someone runs
# `ollama pull`, not between two turns.
def ollama_installed_models
  return @ollama_installed_models if defined?(@ollama_installed_models)

  @ollama_installed_models = fetch_ollama_tags
end

def ollama_cloud_model?(model_id)
  name = model_id.to_s.sub(%r{\Aollama[:/]}, "")
  name.end_with?(":cloud", "-cloud")
end

# Cloud models are remotely executed by Ollama, so they must not depend on
# /api/tags. Keep this list in models.yml so the operator can update it without
# changing Ruby; local discovery remains fully dynamic through /api/tags.
def ollama_cloud_catalog
  Array(@rules.dig("ollama", "cloud_models"))
end

# The local tier as the daemon holds it, best first: the models.yml chain in
# its own order where pulled, then whatever else is pulled, so a machine that
# pulled a different model still has a local lane. Embedding models are left
# out because /api/chat refuses them. When the daemon cannot say, the
# configured chain stands if the tier is enabled and nothing is offered if not.
#
# This is the method the CLI agent calls for an offline default, and the one
# FallbackChain walks when a paid lane fails with no network.
#
# And what runs on this machine. A :cloud tag answers from ollama.com, so
# an offline boot pinned glm-5.3-flash:cloud and asked the network it had
# found missing. A model past LOCAL_FIT of physical memory pages for every
# token, as gemma4:26b's 17 GB does on an 8 GB laptop. Among the rest, the
# largest the machine holds leads.
LOCAL_FIT = 0.6

def local_models
  configured = Array(@rules.dig("models", "local")).filter_map { |row| row["id"] }
  installed = ollama_installed_models
  return ollama_enabled? ? configured : [] if installed.nil?

  pulled = configured.select { |id| ollama_pulled?(id) }
  extra = installed.reject { |name| name.match?(/embed/i) }
                   .each_with_index.sort_by { |name, index| [-ollama_size(name), index] }
                   .map { |name, _| "ollama:#{name.delete_suffix(':latest')}" }
  (pulled + extra).uniq.select { |id| runs_here?(id) }
end

def runs_here?(model_id)
  name = model_id.to_s.sub(%r{\Aollama[:/]}, "")
  return false if name.end_with?(":cloud", "-cloud")

  size = ollama_size(name)
  memory_mb = Master::Core::Memory.host_memory_mb
  size.zero? || memory_mb.nil? || size <= memory_mb * 1_048_576 * LOCAL_FIT
end

# Bytes on disk, which is close to what the weights take in memory; 0 when
# the daemon did not say.
def ollama_size(name)
  sizes = @ollama_sizes || {}
  sizes.fetch(name) { sizes.fetch("#{name}:latest", 0) }
end

OLLAMA_TAGS_TIMEOUT_S = 2

# OLLAMA_BASE_URL decides whether the tier is offered while online. The
# daemon's address does not depend on it, so an unset variable still asks the
# default one, which is what an offline laptop has.
def ollama_tags_base_url
  base = ENV["OLLAMA_BASE_URL"].to_s.strip
  base = @rules.dig("ollama", "default_base_url").to_s if base.empty?
  base = "http://localhost:11434" if base.empty?
  base.chomp("/").delete_suffix("/v1")
end

def fetch_ollama_tags
  uri = URI("#{ollama_tags_base_url}/api/tags")
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                 open_timeout: OLLAMA_TAGS_TIMEOUT_S,
                                                 read_timeout: OLLAMA_TAGS_TIMEOUT_S) do |http|
    http.get(uri.request_uri)
  end
  return unless response.is_a?(Net::HTTPSuccess)

  rows = Array(JSON.parse(response.body.to_s)["models"])
  @ollama_sizes = rows.to_h { |row| [row["name"].to_s, row["size"].to_i] }
  rows.filter_map { |row| row["name"]&.to_s }
rescue StandardError => e
  Master::Ground::Swallow.log(e, context: "model_router.ollama_tags")
  nil
end

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
