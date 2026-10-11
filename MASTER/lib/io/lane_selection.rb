# frozen_string_literal: true

require "yaml"
require_relative "lane_quota"
require_relative "lane_health"

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
      NEUTRAL_LATENCY_S = 45
      UNMEASURED_TIMEOUT_S = 60
      SLOW_S = 600
      CATALOGUE_TIERS = %w[default strong local].freeze

      # The lane a model id travels: the text before ":" for CLI lanes, else the
      # vendor slug of an API id.
      def provider(model)
        id = model.to_s
        return id.split("/").first.to_s if id.include?("/")

        id.split(/[:-]/).first.to_s
      end

      def kind(model)
        id = model.to_s
        return :paid_tail if Io::PaidTail.member?(id)
        return :free if id.end_with?(":free", ":cloud", "-cloud") || id.start_with?("web-chat:")
        return :local if id.start_with?("ollama:", "ollama/", "local:")

        :remote
      end

      # Live models, remote before local before free, each group in the order given.
      # `free_last: false` keeps the given order, for the routes that choose the
      # free tier on purpose (greetings, explanations), where only the dead go.
      # `latency` answers seconds for a model or nil when it was never measured.
      # `vision: true` puts the lanes that read images ahead of those that do not.
      def order(models, free_last: true, latency: nil, vision: false, manual: LaneQuota.manual_dead)
        live = Array(models).map(&:to_s).reject(&:empty?).uniq.reject { |id| LaneQuota.dead?(id, manual:) || LaneHealth.dead?(id) }
        live = live.reject { |id| kind(id) == :paid_tail && !Io::PaidTail.enabled? }
        return live unless free_last

        ranked = live.each_with_index.sort_by { |id, index| [KIND_RANK.fetch(kind(id)), free_latency(id, latency), index] }.map(&:first)
        return ranked unless vision

        sighted, blind = ranked.partition { |id| vision?(id) }
        sighted + blind
      end

      def free_latency(id, latency)
        return 0.0 unless kind(id) == :free

        (latency&.call(id) || free_tier.fetch("neutral_latency_s", NEUTRAL_LATENCY_S)).to_f
      end

      def free_tier = config.fetch("free_tier", {})

      def unmeasured_timeout_s = Integer(free_tier.fetch("unmeasured_timeout_s", UNMEASURED_TIMEOUT_S))

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
        reps = live.select { |id| kind(id) == kind(live.first) }.group_by { |id| provider(id) }.values.map(&:first)
        Array(keys).each_with_index.to_h { |key, index| [key, reps.empty? ? nil : reps.fetch(index % reps.size)] }
      end

      # Read straight from the file: `operator fix status` asks without booting the runtime.
      def config(path = MODELS) = YAML.safe_load_file(path, aliases: true) || {}

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

        binary = CLI_BINARIES[provider(id)]
        return on_path?(binary) if binary
        return Master.agy_cli_available? if provider(id) == "agy"
        return ollama_alive?(id) if id.start_with?("ollama:")

        Master.any_api_key_present?
      end

      # A local model needs the daemon, which this starts once when it is down.
      def ollama_alive?(id)
        return false if LaneQuota.dead?(id)

        %i[up started].include?(LaneHealth.ensure_ollama.state)
      end

      def on_path?(binary)
        ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
          exe = File.join(dir, binary)
          File.file?(exe) && File.executable?(exe)
        end
      end

      # "online: yes via X" or "online: NO (all lanes dead) ..." over the catalogue.
      def online_line(cfg: config)
        LaneHealth.line(catalogue(cfg:), refuses: ->(m) { LaneQuota.dead?(m) || !alive?(m) })
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
