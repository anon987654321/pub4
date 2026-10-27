# frozen_string_literal: true

require "yaml"
require_relative "lane_quota"
require_relative "lane_health"
require_relative "lane_state"

module Master
  module Io
    # The one rule for choosing a model, for /fix and the council alike: take
    # the models of the requested tier in the order data/models.yml lists them,
    # drop the dead lanes (quota spent, unreachable, silent, or on the hand-kept
    # dead list), and use the first that is left. A failure falls to the next
    # live one (Agent#retry_on_broke_lane walks the same order).
    #
    # After the live subscription and direct-API lanes come the cheap paid models
    # of the capped tail (Io::PaidTail), then the local Ollama models (the
    # always-online floor), then the free models: an unmetered model is a floor to
    # stand on, never a lane to prefer, and a free nemotron call cost 150 to 190
    # seconds against seconds on a live subscription CLI. Among the free ones the
    # fastest recently-answering goes first; an unmeasured one is assumed neutral.
    # A call that carries an image tries the vision-capable lanes first.
    #
    # The council spreads its personas over the live providers with `spread`,
    # so one dead lane never decides what the whole panel sounds like.
    module LaneSelection
      extend self

      MODELS = File.expand_path("../../data/models.yml", __dir__)
      CLI_BINARIES = { "claude-cli" => "claude", "grok-cli" => "grok" }.freeze
      KIND_RANK = { remote: 0, paid_tail: 1, local: 2, free: 3 }.freeze
      # The signed-in subscription CLIs lead the remote class, in this order: a
      # flat-rate lane is spent before a metered API key is, and before any free
      # or local model is asked to edit code.
      SUBSCRIPTION_LANES = %w[claude-cli grok-cli codex-cli agy].freeze
      FREE_CLASS_KINDS = %i[free local].freeze
      NOT_SUBSCRIPTION = 10_000
      NEUTRAL_LATENCY_S = 45
      UNMEASURED_TIMEOUT_S = 60
      SLOW_S = 600
      CATALOGUE_TIERS = %w[default strong local].freeze

      # The lane a model id travels: the text before ":" for CLI lanes, else the
      # vendor slug of an API id.
      def provider(model)
        id = model.to_s
        return id.split(":", 2).first(2).join(":") if id.start_with?("web-chat:")

        colon = id.index(":")
        slash = id.index("/")
        return id[0...colon].to_s if colon && (!slash || colon < slash)
        return id.split("/", 2).first.to_s if slash

        id.split(/[:-]/).first.to_s
      end

      def kind(model)
        id = model.to_s
        return :paid_tail if Io::PaidTail.member?(id)
        return :free if id.end_with?(":free", ":cloud", "-cloud") ||
                        id.start_with?("web-chat:")
        return :local if id.start_with?("ollama:", "ollama/", "local:")

        :remote
      end

      # Live models, remote before local before free, each group in the order given.
      # `free_last: false` keeps the given order, for the routes that choose the
      # free tier on purpose (greetings, explanations), where only the dead go.
      # `latency` answers seconds for a model or nil when it was never measured.
      # `vision: true` puts the lanes that read images ahead of those that do not.
      def order(models, free_last: true, latency: nil, vision: false, manual: LaneQuota.manual_dead, lead: [])
        live = Array(models).map(&:to_s).reject(&:empty?).uniq
        live = live.reject { |id| LaneQuota.dead?(id, manual:) || !LaneState.usable?(id) }
        live = live.reject { |id| kind(id) == :paid_tail && !Io::PaidTail.enabled? }
        return live unless free_last

        listed = (Array(lead) + catalogue).uniq
        ranked = live.each_with_index.sort_by { |id, index| [KIND_RANK.fetch(kind(id)), subscription_rank(id, listed), free_latency(id, latency), index] }.map(&:first)
        return ranked unless vision

        sighted, blind = ranked.partition { |id| vision?(id) }
        sighted + blind
      end

      def subscription?(model) = SUBSCRIPTION_LANES.include?(LaneQuota.lane_of(model))

      # Low for a subscription lane (its lane position, then its place in the
      # catalogue so opus precedes sonnet as data/models.yml lists them), high
      # for every other model, which keeps the order it arrived in.
      def subscription_rank(id, listed)
        return NOT_SUBSCRIPTION unless kind(id) == :remote && subscription?(id)

        SUBSCRIPTION_LANES.index(LaneQuota.lane_of(id)) * 100 + (listed.index(id) || 99)
      end

      # The same ids with the live subscription lanes first, in their fixed order;
      # every other id keeps its place. The pool's measured utility ranks within
      # a class, never across it.
      def subscriptions_first(ids, lead: [])
        listed = (Array(lead) + catalogue).uniq
        Array(ids).each_with_index.sort_by { |id, index| [subscription_rank(id, listed), index] }.map(&:first)
      end

      # The ids of the tier the rules route this task type to, in the order
      # data/models.yml lists them: the lane order the route asks for, so a route
      # to the fast tier leads with sonnet where the default tier leads with opus.
      def route_lead(rules, task_type)
        tier = rules.dig("routes", task_type.to_s)
        Array(rules.dig("models", tier)).filter_map { |row| row["id"] if row.is_a?(Hash) }
      end

      def free_latency(id, latency)
        return 0.0 unless kind(id) == :free

        (latency&.call(id) || free_tier.fetch("neutral_latency_s", NEUTRAL_LATENCY_S)).to_f
      end

      def free_tier = config.fetch("free_tier", {})

      def unmeasured_timeout_s = Integer(free_tier.fetch("unmeasured_timeout_s", UNMEASURED_TIMEOUT_S))

      # Bound every completion, not only an unmeasured lane: a short health
      # probe says nothing about the cost of a large repair prompt.
      def free_call_timeout_s
        value = Integer(free_tier.fetch("call_timeout_s", UNMEASURED_TIMEOUT_S), exception: false)
        value&.positive? ? value : UNMEASURED_TIMEOUT_S
      end

      # Whether a lane reads images: the catalog row's input modalities when it
      # has one, else the dispatcher's own list of vision families.
      def vision?(model)
        id = model.to_s
        row = catalog_modalities(id)
        return row.include?("image") if row

        d = Master::Review::LLMDispatcher
        !d::NON_VISION_RE.match?(id) && d::VISION_RE.match?(id)
      end

      def catalog_modalities(id)
        @modalities ||= begin
          require_relative "catalog_index"
          db = Master::Io::CatalogIndex::DEFAULT_DB
          File.file?(db) ? Master::Io::CatalogIndex.new(db_path: db).search(nil, source: "openrouter", limit: 5_000).to_h { |r| [r["id"], r["input_modalities"].to_s.split(",").map(&:strip)] } : {}
        rescue StandardError
          {}
        end
        @modalities[id]
      end

      # Every id models.yml names in any tier.
      def explicit_models(cfg: config)
        cfg.fetch("models", {}).values.flatten.filter_map { |row| row["id"] if row.is_a?(Hash) }.uniq
      end

      # The first live model of the list, or nil when every lane is dead.
      def first_live(models) = order(models).first

      # `order`, except that when every model is dead the list comes back as it
      # was, so the dispatcher can refuse it with the typed Offline that says why.
      def order_or_all(models, free_last: true, **rest)
        live = order(models, free_last:, **rest)
        live.empty? ? Array(models) : live
      end

      # The live models of the best class that has any: a pool may rank them by
      # measured utility, but never trades a live subscription for a free model.
      # All dead: the list as given, for the dispatcher to refuse with the typed Offline.
      def best_class(models, free_last: true, **rest)
        live = order_or_all(models, free_last:, **rest)
        return live unless free_last

        live.select { |id| kind(id) == kind(live.first) }
      end

      # One model per key, drawn from the best class that has a live lane and
      # spread across its distinct providers; a single provider is reused.
      def spread(keys, models, vision: false)
        live = order(models, vision:)
        sighted = live.select { |id| vision?(id) }
        live = sighted if vision && sighted.any?
        best = live.select { |id| kind(id) == kind(live.first) }
        flat_rate = best.select { |id| subscription?(id) }
        reps = (flat_rate.empty? ? best : flat_rate).group_by { |id| provider(id) }.values.map(&:first)
        Array(keys).each_with_index.to_h { |key, index| [key, reps.empty? ? nil : reps.fetch(index % reps.size)] }
      end

      CONFIG_LOCK = Mutex.new

      # Read straight from the file: `operator fix status` asks without booting the runtime. Parsed once per
      # change of the file and handed out frozen: a chat turn ranked its lanes three times, and parsing this
      # file on each of the hundreds of calls that made took 1.4s a turn.
      def config(path = MODELS)
        return {} unless File.file?(path)

        stat = File.stat(path)
        key = [path, stat.mtime.to_r, stat.size]
        remember_config(key, path) unless cached_config(key)
        cached_config(key)
      end

      def cached_config(key) = CONFIG_LOCK.synchronize { @config_cache.last if @config_cache&.first == key }

      def remember_config(key, path)
        parsed = deep_freeze(YAML.safe_load_file(path, aliases: true) || {})
        CONFIG_LOCK.synchronize { @config_cache = [key, parsed] }
      end

      def deep_freeze(value)
        case value
        when Hash then value.each { |key, item| deep_freeze(key) && deep_freeze(item) }
        when Array then value.each { |item| deep_freeze(item) }
        end
        value.freeze
      end

      # The models of a tier as data/models.yml lists them.
      def tier(name, cfg: config)
        Array(cfg.dig("models", name.to_s)).filter_map { |row| row["id"] if row.is_a?(Hash) }
      end

      # Every model the status lines speak about, in order, once.
      def catalogue(cfg: config)
        CATALOGUE_TIERS.flat_map { |name| tier(name, cfg:) }.uniq
      end

      # The tier's live models whose lane can answer on this machine, in selection order.
      def pool(name = "default", cfg: config, alive: method(:alive?))
        order(tier(name, cfg:)).select { |id| alive.call(id) }
      end

      def alive?(model)
        id = model.to_s
        return false if Master::Io::ModelQuota.over_quota?(id)

        binary = CLI_BINARIES[LaneQuota.lane_of(id)]
        return on_path?(binary) && ENV["MASTER_NO_#{binary.upcase}_CLI"] != "1" if binary
        return Master.agy_cli_available? if provider(id) == "agy"
        return ollama_alive?(id) if id.start_with?("ollama:")

        key_present_for?(id)
      end

      # The key the model's own provider takes: an owner/name id goes through
      # OpenRouter, a bare id through its vendor. Any key at all is the answer
      # only for a vendor this table does not name.
      API_KEYS = [
        [%r{/}, %w[OPENROUTER_API_KEY]], [/\Adeepseek/, %w[DEEPSEEK_API_KEY]], [/\Agrok-\d/, %w[XAI_API_KEY]],
        [/\Agemini/, %w[GOOGLE_API_KEY GEMINI_API_KEY]], [/\Aclaude-/, %w[ANTHROPIC_API_KEY]]
      ].freeze

      def key_present_for?(id)
        _pattern, envs = API_KEYS.find { |pattern, _envs| pattern.match?(id) }
        envs ? envs.any? { |env| Master.api_key_present?(env) } : Master.any_api_key_present?
      end

      # A local model needs the daemon, which this starts once when it is down.
      def ollama_alive?(id)
        return false if LaneQuota.dead?(id)

        %i[up started].include?(LaneHealth.ensure_ollama.state)
      end

      def on_path?(binary) = !Master::Io::Exec.cli_binary(binary).nil?

      # "online: yes via X" or "online: NO (all lanes dead) ..." over the catalogue.
      def online_line(cfg: config)
        LaneHealth.line(catalogue(cfg:), refuses: ->(m) { LaneQuota.dead?(m) || !alive?(m) })
      end

      # The models that can answer now, in selection order: the catalogue minus
      # the dead (quota, health, hand-kept list) and the lanes this machine lacks.
      def live_lanes(cfg: config, alive: method(:alive?)) = order(catalogue(cfg:)).lazy.select { |id| alive.call(id) }

      # The lane a run starts on and why. Availability decides; a saved model is
      # a preference, honoured only while it is live and no worse a class than
      # the best live lane, and MASTER_MODEL alone forces a lane.
      def boot_choice(env: ENV, saved: nil, cfg: config, alive: method(:alive?))
        forced = env["MASTER_MODEL"].to_s.strip
        return [forced, "MASTER_MODEL"] unless forced.empty?

        live = live_lanes(cfg:, alive:)
        return [saved.to_s, "saved preference"] if preference_leads?(saved, live)

        [live.first, "availability"]
      end

      def preference_leads?(model, live)
        id = model.to_s
        return false if id.empty? || !live.include?(id)

        no_worse_class?(id, live.first)
      end

      # A model of the same class as the head, or better: a free preference never
      # leads a live subscription.
      def no_worse_class?(model, head)
        KIND_RANK.fetch(kind(model)) <= KIND_RANK.fetch(kind(head))
      end

      # /fix turns the guard on: a free or local lane asked for a model call
      # while a subscription or API lane is live is the defect that spent hours
      # on a free model. One warning per lane.
      def watch_free_class!(on = true)
        @watching = on
        @warned = {}
      end

      def free_class_warning(model, operation, cfg: config, alive: method(:alive?))
        id = model.to_s
        # A lane probe asks every lane on purpose; that is not work on a free lane.
        return unless @watching && FREE_CLASS_KINDS.include?(kind(id)) && operation != :lane_probe
        return if (@warned ||= {})[id]

        better = live_lanes(cfg:, alive:).find { |candidate| !FREE_CLASS_KINDS.include?(kind(candidate)) }
        return unless better

        @warned[id] = true
        "WARNING free-class lane #{id} used for #{operation || "a model call"} while #{better} is live"
      rescue StandardError
        nil
      end

      def note_use(model, operation)
        text = free_class_warning(model, operation)
        Master::Trace::Dmesg.status("fix0", text) if text
      end

      # A MASTER_MODEL pin is the only lane; MASTER_MODEL_STRICT=0 lets it fail over.
      def strict_pin?(env = ENV) = env["MASTER_MODEL_STRICT"].to_s != "0"

      def pin_label(env = ENV)
        strict_pin?(env) ? "pinned (MASTER_MODEL), no failover" : "pinned (MASTER_MODEL), failover on"
      end

      # What /model and fix status print: the effective #1 lane and why.
      def primary_report(env: ENV, saved: nil, cfg: config, alive: method(:alive?))
        lane, source = boot_choice(env:, saved:, cfg:, alive:)
        return "primary: no live lane (every catalogue lane is dead or absent)" if lane.to_s.empty?

        why = {
          "MASTER_MODEL" => pin_label(env),
          "saved preference" => "saved preference, live",
          "availability" => "first live lane by availability (#{SUBSCRIPTION_LANES.join(" > ")}, then APIs, paid tail, local, free)"
        }.fetch(source)
        dead = catalogue(cfg:).select { |id| LaneQuota.dead?(id) }.map { |id| LaneQuota.lane_of(id) }.uniq
        "primary: #{lane} (#{why}#{dead.empty? ? "" : "; dead: #{dead.join(", ")}"})"
      end

      # What /fix prints once at its start: the live pool in selection order.
      def announce(cfg: config)
        Master::Trace::Dmesg.status("lane0", online_line(cfg:))
        live = order(catalogue(cfg:))
        Master::Trace::Dmesg.status("lane0", "selection order: #{live.empty? ? "none live" : live.first(6).join(" > ")}")
        live
      rescue StandardError, NameError
        nil
      end
    end
  end
end
