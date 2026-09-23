# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "timeout"
require "uri"

module Master
  module CLI
    module Routing
      class ModelRouter
        # The pool: every model this machine can ask right now. A lane joins it
        # when it can answer — a key that is set, a CLI that is signed in, a
        # daemon or server that lists the model — and a model outside it
        # carries the one thing to do about that. OpenCrabs builds its list the
        # same way, live from each provider, so /model never offers a model
        # that answers "not found" and the chain never walks through one.
        #
        # The slow probes (a CLI's sign-in check, OpenRouter's balance) run on
        # threads started with the router. Until one answers its lane stays out
        # of the chain rather than stalling a turn, and /model list waits for it.
        module Pool
          PROBE_TIMEOUT_S = 15
          SERVER_TIMEOUT_S = 1
          CATALOG_MAX_AGE_S = 86_400
          CATALOG_MODEL_LIMIT = 5_000
          CREDITS_URL = "https://openrouter.ai/api/v1/credits"
          KEY_FILES = "~/.config/master/env (or /etc/master.env on OpenBSD)"

          def reachable?(model_id) = unreachable_reason(model_id).nil?

          # nil when the model can be asked, otherwise what to do about it.
          def unreachable_reason(model_id, wait: false)
            id = model_id.to_s
            case lane_of(id)
            when :cli_lane then cli_lane_problem(id, wait:)
            when :ollama then ollama_problem(id)
            when :api then api_problem(id, wait:)
            else binary_lane_problem(id)
            end
          end

          # Every reachable model, strongest lanes first: what /model list shows.
          def pool(wait: false)
            start_pool_probes
            lanes = [primary_models, cli_lane_models(wait:), tier_ids, continuity_models,
                     ollama_cloud_catalog, ollama_cloud_models, local_server_models,
                     live_catalog_models, replicate_models, local_models]
            lanes.flatten.uniq.select { |id| unreachable_reason(id, wait:).nil? }
          end

          # The distinct fixes that would grow the pool, keys gathered on one line.
          def pool_growth(wait: false)
            reasons = (tier_ids + cli_lane_ids + replicate_models).filter_map { |id| unreachable_reason(id, wait:) }
            gather_keys(reasons.uniq.reject { |reason| reason.start_with?("checking") })
          end

          def gather_keys(reasons)
            keys, rest = reasons.partition { |reason| reason.start_with?("set ") && reason.end_with?(KEY_FILES) }
            envs = keys.map { |reason| reason.delete_prefix("set ").delete_suffix(" in #{KEY_FILES}") }
            (envs.empty? ? [] : ["set #{envs.join(', ')} in #{KEY_FILES}"]) + rest
          end

          # What kind of lane a model is, for the column beside it.
          def lane_label(model_id)
            id = model_id.to_s
            return "free" if id.end_with?(":free", ":cloud", "-cloud") || id.start_with?("web-chat:")

            { claude_cli: "subscription", agy: "subscription", cli_lane: "subscription", ollama: "local",
              local_server: "local", replicate: "paid", api: "paid" }.fetch(lane_of(id))
          end

          def cli_lane_model?(model_id) = cli_lanes.key?(model_id.to_s.split(":", 2).first)

          def cli_lane(model_id) = cli_lanes[model_id.to_s.split(":", 2).first]

          # The base URL of the local server that listed this model.
          def local_server_for(model_id) = local_server_index[model_id.to_s]

          def start_pool_probes
            return {} if ENV["MASTER_NO_POOL_PROBES"] == "1"

            @pool_probes ||= cli_lanes.keys.to_h { |name| [name, Thread.new { probe_cli_lane(name) }] }.merge(
              "openrouter_credits" => Thread.new { probe_openrouter_credits },
              "provider_catalogs" => Thread.new { refresh_provider_catalogs },
            )
          end

          # Invalidate discovery caches without forgetting durable telemetry.
          def refresh_pool!
            @ollama_installed_models = nil
            @local_server_index = nil
            @api_providers = nil
            @provider_rows = nil
            @live_catalog_models = nil
            @catalog_index = nil
            @pool_probes = nil
            start_pool_probes
            self
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.pool.refresh")
            self
          end

          private

          # The lanes that need a binary, a browser profile or a running server
          # rather than a key: each is present or it is not. A CLI lane without
          # its binary fails with ENOENT, which the dispatcher files as a
          # retriable provider_error, so the chain slept through its backoff
          # before walking on — 90s of a web turn on ai.brgen.no, 2026-09-15.
          def binary_lane_problem(id)
            present, fix = case lane_of(id)
                           when :claude_cli then [claude_cli_available?, "install Claude Code"]
                           when :agy then [agy_cli_available?, "install the Antigravity CLI"]
                           when :web_chat then [web_chat_enabled?, "browser chat is off; MASTER_WEB_CHAT=1 turns it on"]
                           when :local_server
                             [local_server_for(id), "no local server lists #{id.delete_prefix('local:')}"]
                           else [replicate_key?, "set REPLICATE_API_TOKEN in #{KEY_FILES}"]
                           end
            fix unless present
          end

          def lane_of(id)
            return :claude_cli if id.start_with?("claude-cli:")
            return :agy if id.start_with?("agy:") || id == "agy"
            return :web_chat if id.start_with?("web-chat:")
            return :ollama if id.start_with?("ollama:", "ollama/")
            return :local_server if id.start_with?("local:")
            return :replicate if id.start_with?("replicate:")

            cli_lane_model?(id) ? :cli_lane : :api
          end

          def tier_ids = Array(@rules["models"]&.values).flatten.filter_map { |row| row["id"] if row.is_a?(Hash) }

          def cli_lanes = @rules.fetch("cli_lanes", {})

          def cli_lane_ids
            cli_lanes.flat_map { |name, lane| Array(lane["models"]).map { |model| "#{name}:#{model}" } }
          end

          def cli_lane_models(wait: false) = cli_lane_ids.select { |id| cli_lane_problem(id, wait:).nil? }

          # Models discovered from provider-owned catalogs are first-class pool
          # members. This is the autonomous part: adding a model at a provider
          # does not require a models.yml edit. Catalog metadata is consumed by
          # ComputePool; the router only needs a provider credential.
          def live_catalog_models
            return @live_catalog_models if defined?(@live_catalog_models)
            return @live_catalog_models = [] unless Master.api_key_present?("OPENROUTER_API_KEY")

            @live_catalog_models = catalog_rows("openrouter").filter_map do |row|
              id = row["id"].to_s
              next if id.empty? || id.end_with?(":free") && Master::Io::ModelQuota.over_quota?(id)
              next unless chat_catalog_model?(row)

              id
            end
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.live_catalog")
            @live_catalog_models = []
          end

          def chat_catalog_model?(row)
            inputs = row["input_modalities"].to_s.split(",").map(&:strip)
            outputs = row["output_modalities"].to_s.split(",").map(&:strip)
            return true if inputs.empty? && outputs.empty?

            outputs.include?("text") && (inputs.empty? || inputs.include?("text"))
          end

          def catalog_rows(source)
            require_relative "../../../io/catalog_index"
            db = Master::Io::CatalogIndex::DEFAULT_DB
            return [] unless File.file?(db)

            @catalog_index ||= Master::Io::CatalogIndex.new(db_path: db)
            @catalog_index.search(nil, source:, limit: CATALOG_MODEL_LIMIT)
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.catalog_rows", source:)
            []
          end

          def cli_lane_problem(id, wait:)
            name = id.split(":", 2).first
            lane = cli_lanes.fetch(name)
            return "install #{lane['binary']}" unless executable_on_path?(lane["binary"])

            signed_in = probe_value(name, wait:)
            return "checking whether #{lane['binary']} is signed in" if signed_in.nil?

            ("run #{lane['login']}" unless signed_in)
          end

          # nil while the probe runs, and always with probes off.
          def probe_value(name, wait:)
            thread = start_pool_probes[name]
            return if thread.nil?
            return thread.value unless thread.alive?

            wait ? thread.join(PROBE_TIMEOUT_S)&.value : nil
          end

          def probe_cli_lane(name)
            lane = cli_lanes.fetch(name)
            return false unless executable_on_path?(lane["binary"])

            output = run_probe(lane["binary"], *Array(lane.dig("signed_in", "args")))
            signed_in_output?(output, lane.fetch("signed_in", {}))
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.pool.cli_lane")
            false
          end

          def signed_in_output?(output, rule)
            return false if output.nil?
            return output.include?(rule["match"].to_s) if rule["match"]

            !output.downcase.include?(rule["refuse"].to_s.downcase)
          end

          # Output and error together, since CLIs disagree about which a status goes to.
          def run_probe(*command)
            Open3.popen2e(*command) do |stdin, output, waiter|
              stdin.close
              reader = Thread.new { output.read }
              next reader.value if waiter.join(PROBE_TIMEOUT_S)

              Process.kill("KILL", waiter.pid)
              reader.kill
              nil
            end
          rescue SystemCallError => e
            Master::Ground::Swallow.log(e, context: "model_router.pool.run_probe")
            nil
          end

          def executable_on_path?(binary)
            home = File.expand_path("~/.local/bin/#{binary}")
            ([home] + ENV["PATH"].to_s.split(File::PATH_SEPARATOR).map { |dir| File.join(dir, binary.to_s) })
              .any? { |path| File.file?(path) && File.executable?(path) }
          end

          # A key the provider takes, from providers.yml; an owner/name id and
          # any id the registry does not know go to OpenRouter, as the sender
          # sends them.
          def api_problem(id, wait:)
            provider = api_provider(id)
            envs = Array((@provider_rows ||= Master.provider_config).dig(provider, "env"))
            return "set #{envs.join(' or ')} in #{KEY_FILES}" unless envs.any? { |env| Master.api_key_present?(env) }
            return unless provider == "openrouter" && !id.end_with?(":free")
            return unless probe_value("openrouter_credits", wait:) == false

            "OpenRouter credit is spent; top up at openrouter.ai/settings/credits"
          end

          def api_provider(id)
            return "openrouter" if id.include?("/")

            (@api_providers ||= {})[id] ||= registry_provider(id)
          end

          # The gem's registry is what the sender resolves an id against, so the
          # pool asks the same one rather than keeping a prefix table beside it.
          def api_provider_for(id) = api_provider(id)

          def registry_provider(id)
            require "ruby_llm"
            RubyLLM.models.find(id).provider.to_s
          rescue StandardError
            "openrouter"
          end

          # false only when OpenRouter says the balance is gone; nil when it cannot say.
          def probe_openrouter_credits
            key = ENV["OPENROUTER_API_KEY"].to_s
            return if key.empty?

            data = JSON.parse(get_json(CREDITS_URL, headers: { "Authorization" => "Bearer #{key}" }).to_s)["data"] || {}
            data["total_credits"].to_f > data["total_usage"].to_f
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.pool.credits")
            nil
          end

          # OpenRouter adds and withdraws :free models every week, and a catalog
          # refreshed by hand once was a month stale, so the free lane offered
          # models that had gone and missed the ones that had come. A day old,
          # it refreshes; live_free_models reads it on the next chain.
          def refresh_provider_catalogs
            require_relative "../../../io/catalog_index"
            index = Master::Io::CatalogIndex.new(db_path: Master::Io::CatalogIndex::DEFAULT_DB)

            catalog_credentials.each do |source, token|
              next unless index.stale?(source, max_age: CATALOG_MAX_AGE_S)

              begin
                index.refresh(source, token:)
              rescue StandardError => e
                Master::Ground::Swallow.log(e, context: "model_router.pool.catalog", source:)
              end
            end
            nil
          end

          def catalog_credentials
            {
              "openrouter" => ENV["OPENROUTER_API_KEY"],
              "openai" => ENV["OPENAI_API_KEY"],
              "gemini" => ENV["GEMINI_API_KEY"].to_s.empty? ? ENV["GOOGLE_API_KEY"] : ENV["GEMINI_API_KEY"],
              "deepseek" => ENV["DEEPSEEK_API_KEY"],
              "xai" => ENV["XAI_API_KEY"],
              "mistral" => ENV["MISTRAL_API_KEY"],
            }.select { |_source, token| token && !token.empty? }
          end

          def get_json(url, headers: {}, timeout: PROBE_TIMEOUT_S)
            uri = URI(url)
            Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                            open_timeout: timeout, read_timeout: timeout) do |http|
              response = http.get(uri.request_uri, headers)
              response.body if response.is_a?(Net::HTTPSuccess)
            end
          end

          def ollama_problem(id)
            name = id.sub(%r{Aollama[:/]}, "")
            installed = ollama_installed_models
            return (ollama_enabled? ? nil : "start Ollama") if installed.nil?
            return "ollama pull #{name}" unless ollama_pulled?(id)
            return if name.end_with?(":cloud", "-cloud")

            ("#{name} needs more memory than this machine has" unless runs_here?(id))
          end

          def ollama_cloud_models
            Array(ollama_installed_models).select { |name| name.end_with?(":cloud", "-cloud") }
                                          .map { |name| "ollama:#{name}" }
          end

          def local_server_models = local_server_index.keys

          def local_server_index
            return {} if ENV["MASTER_NO_POOL_PROBES"] == "1"

            @local_server_index ||= Array(@rules["local_servers"]).each_with_object({}) do |base, index|
              server_model_ids(base).each { |model| index["local:#{model}"] ||= base }
            end
          end

          def server_model_ids(base)
            body = get_json("#{base.chomp('/')}/models", timeout: SERVER_TIMEOUT_S)
            Array(JSON.parse(body.to_s)["data"]).filter_map { |row| row["id"] }
          rescue StandardError
            []
          end

          def replicate_models = Array(@rules["replicate_chat"]).map { |slug| "replicate:#{slug}" }

          def replicate_key? = %w[REPLICATE_API_TOKEN REPLICATE_API_KEY].any? { |env| Master.api_key_present?(env) }
        end
      end
    end
  end
end