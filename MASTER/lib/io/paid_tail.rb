# frozen_string_literal: true

require "monitor"
require_relative "catalog_index"

module Master
  module Io
    # Cheap paid models as a last stop before the free ones. The list is the live
    # provider catalog's non-free OpenRouter chat models priced under the caps in
    # data/models.yml (paid_tail:), minus anything models.yml already names. What
    # the tail costs is counted here, from the cost each reply records, and at
    # run_cap_usd it turns itself off for the rest of the process with one line.
    module PaidTail
      extend self

      PER_MILLION = 1_000_000.0
      # Models that are not general chat: media, search, embedding, guard and unstable previews.
      NOT_CHAT_RE = /image|search|embed|guard|moderat|audio|tts|preview|\bvl\b|-vl-/i
      LOCK = Monitor.new
      @spent = 0.0
      @capped = false
      @all = nil

      def config = LaneSelection.config.fetch("paid_tail", {})

      def enabled? = ENV["MASTER_PAID_TAIL"] != "0" && config["enabled"] != false && !capped?

      def capped? = LOCK.synchronize { @capped }

      def spent = LOCK.synchronize { @spent }

      def run_cap_usd = Float(config.fetch("run_cap_usd", 5.0))

      # Catalog models under the price caps, dearest first inside the caps (price
      # tracks capability), as OpenRouter ids. Empty with no catalog or the tail off.
      def models(db: default_db, cfg: config, explicit: LaneSelection.explicit_models)
        enabled? ? all(db:, cfg:, explicit:) : []
      end

      # In the catalogue's list, whether or not the tail is on.
      def member?(id, db: default_db, cfg: config, explicit: LaneSelection.explicit_models)
        return false if explicit.include?(id.to_s)

        all(db:, cfg:, explicit:).include?(id.to_s)
      end

      # Counts a reply's cost against the cap. Only the tail's own models count.
      def spend!(model, usd)
        return unless member?(model)

        LOCK.synchronize do
          @spent += usd.to_f
          if !@capped && @spent >= run_cap_usd
            @capped = true
            Master::Trace::Dmesg.status("paid0", "run cap $#{format("%.2f", run_cap_usd)} reached ($#{format("%.2f", @spent)} spent), paid tail off for the rest of this run")
          end
        end
      end

      def reset!
        LOCK.synchronize { @spent = 0.0; @capped = false; @all = nil }
      end

      private

      def all(db:, cfg:, explicit:)
        LOCK.synchronize do
          key = [:all, db, File.exist?(db.to_s) ? File.mtime(db).to_f : 0, cfg.hash, explicit.size]
          return @all[1] if @all && @all[0] == key

          @all = [key, read(db, cfg, explicit)]
          @all[1]
        end
      end

      def read(db, cfg, explicit)
        return [] unless File.file?(db.to_s)

        max_prompt = Float(cfg.fetch("max_prompt_usd_per_m", 1.0))
        max_completion = Float(cfg.fetch("max_completion_usd_per_m", 3.0))
        rows = Master::Io::CatalogIndex.new(db_path: db).search(nil, source: "openrouter", limit: 5_000)
        found = rows.filter_map do |row|
          id = row["id"].to_s
          prompt = row["price_prompt"].to_f * PER_MILLION
          completion = row["price_completion"].to_f * PER_MILLION
          next if id.empty? || id.end_with?(":free") || id.include?(":") || id.start_with?("~")
          next if explicit.include?(id) || (prompt.zero? && completion.zero?)
          next if prompt > max_prompt || completion > max_completion
          next if NOT_CHAT_RE.match?(id) || !chat?(row)

          [id, completion]
        end
        found.sort_by { |id, completion| [-completion, id] }.map(&:first).first(Integer(cfg.fetch("max_models", 12)))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Io::PaidTail.read")
        []
      end

      def chat?(row)
        inputs = row["input_modalities"].to_s.split(",").map(&:strip)
        outputs = row["output_modalities"].to_s.split(",").map(&:strip)
        outputs == ["text"] && (inputs.empty? || inputs.include?("text"))
      end

      def default_db = Master::Io::CatalogIndex::DEFAULT_DB
    end
  end
end
