# frozen_string_literal: true

# Every model data/models.yml names must be one the provider still serves.
#
# A fallback chain padded with withdrawn models degrades one entry at a time and
# says nothing until a run ends on "No endpoints found for <id>", which is how
# this was found: a /through pass finished its scans, spent ¢390, and died in the
# council on google/gemma-2-9b-it:free.
#
#   ruby MASTER/tools/model_catalog_check.rb          # report
#   ruby MASTER/tools/model_catalog_check.rb --json   # machine-readable
#
# Needs the network, so it cannot live in bin/check. `rake lint:models` runs it
# and skips rather than fails when the catalogue has never been fetched.

require "json"
require "psych"
require_relative "../lib/providers/catalog_index"

module Pub4
  module ModelCatalogCheck
    MODELS_PATH = File.expand_path("../data/models.yml", __dir__)
    # A bare id (deepseek-chat, gemini-2.5-pro) addresses a native API; only
    # vendor/model ids are routed through OpenRouter and can be checked here.
    LOCAL_PREFIXES = %w[ollama: web-chat: claude-].freeze

    module_function

    def live_ids
      Master::Providers::CatalogIndex.new
                                     .search("", source: "openrouter", limit: 5000)
                                     .filter_map { |row| row["id"] || row[:id] }
                                     .to_set
    end

    def checkable?(id)
      id.to_s.include?("/") && LOCAL_PREFIXES.none? { |prefix| id.to_s.start_with?(prefix) }
    end

    # Anchors carry the ids; aliases carry them into chains. Read the AST rather
    # than the loaded hash, so an anchor whose name no longer matches its id is
    # still reported against the id it actually holds.
    def declared
      ids = []
      walk(Psych.parse_file(MODELS_PATH)) do |node|
        pairs = node.children.each_slice(2).to_h do |key, value|
          [key.respond_to?(:value) ? key.value : nil, value.respond_to?(:value) ? value.value : nil]
        end
        ids << pairs["id"] if pairs["id"]
      end
      ids.uniq
    end

    def walk(node, &block)
      block.call(node) if node.is_a?(Psych::Nodes::Mapping)
      node.children&.each { |child| walk(child, &block) }
    end

    # A chain is any array of model rows. Zero live entries in one means every
    # route through it fails, which no count of dead ids on its own tells you.
    def chains
      data = Psych.safe_load_file(MODELS_PATH, aliases: true, permitted_classes: [])
      found = {}
      data.each do |section, body|
        next unless body.is_a?(Hash)

        body.each do |key, value|
          next unless value.is_a?(Array) && !value.empty?
          next unless value.all? { |row| row.is_a?(Hash) && row["id"] }

          found["#{section}.#{key}"] = value.map { |row| row["id"] }
        end
      end
      found
    end

    def run(json: false)
      live = live_ids
      return skip(json) if live.empty?

      dead = declared.select { |id| checkable?(id) && !live.include?(id) }
      empty = chains.reject { |_, ids| ids.any? { |id| !checkable?(id) || live.include?(id) } }
      report(dead:, empty:, live:, json:)
      empty.empty? ? 0 : 1
    end

    def skip(json)
      message = "model_catalog: no openrouter catalogue — run `bin/provider-catalog refresh openrouter` first"
      puts(json ? JSON.generate(skipped: true, reason: message) : message)
      0
    end

    # "Gone" is three different problems and they take different fixes: a :free
    # tier withdrawn while the paid variant lives, an id renamed under the same
    # vendor, or a vendor absent from the provider altogether. Naming the
    # nearest live id turns the first two into an edit rather than a decision.
    def nearest(id, live)
      vendor = id.split("/").first
      siblings = live.select { |candidate| candidate.start_with?("#{vendor}/") }
      return [:vendor_absent, nil] if siblings.empty?
      return [:free_tier_withdrawn, id.delete_suffix(":free")] if id.end_with?(":free") && siblings.include?(id.delete_suffix(":free"))

      # Only a stem match is a suggestion. Falling back to the vendor's shortest
      # id offers gemma-3-4b-it in place of gemini-flash-lite, which is a wrong
      # answer wearing the shape of a right one.
      stem = id.delete_suffix(":free").split(/[-.]/).first(3).join("-")
      match = siblings.select { |candidate| candidate.start_with?(stem) }.min_by(&:length)
      match ? [:renamed, match] : [:no_successor, nil]
    end

    def report(dead:, empty:, live:, json:)
      live_ids_set = live.is_a?(Integer) ? [] : live
      return puts(JSON.pretty_generate(live:, dead:, chains_with_no_live_model: empty)) if json

      puts "model_catalog: #{live.is_a?(Integer) ? live : live.size} models live, #{dead.size} declared id(s) no longer served"
      dead.sort.each do |id|
        kind, suggestion = nearest(id, live_ids_set)
        puts format("  %-22s %-42s %s", kind, id, suggestion ? "-> #{suggestion}" : "(no live successor under this vendor)")
      end
      empty.each { |name, ids| puts "  EMPTY CHAIN #{name} — every one of its #{ids.size} models is gone" }
      puts(empty.empty? ? "model_catalog: every chain still has a live model" : "model_catalog: #{empty.size} chain(s) route nowhere")
    end
  end
end

exit Pub4::ModelCatalogCheck.run(json: ARGV.include?("--json")) if $PROGRAM_NAME == __FILE__
