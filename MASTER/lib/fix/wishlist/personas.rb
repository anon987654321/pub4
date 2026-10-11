# frozen_string_literal: true

module Master
  module Fix
    class Wishlist
      # Each council persona drafts its own wishes from its own lens, and the
      # ledger keeps who asked. A wish several personas raise independently
      # carries more weight and is claimed first. Personas only propose: the
      # ledger rows are still queued work, never edits.
      module Personas
        DEFAULT = ["Graphic Designer", "Typographer", "Security", "Maintainer"].freeze
        FALLBACK_FOCUS = {
          "Graphic Designer" => "visual hierarchy, composition, spacing and colour consistency in rendered pages",
          "Typographer" => "type scale, measure, line height, reading rhythm and layout alignment",
          "Security" => "injection, privilege, data exposure and unsafe defaults",
          "Maintainer" => "readability, naming, duplication and long-term maintenance burden",
          "Reliability" => "retries, timeouts, degradation, idempotency and rollback safety",
          "User Advocate" => "clarity, friction and error recovery for the person using it",
        }.freeze
        PER_PERSONA = 4
        SIMILARITY = 0.5
        OPEN = %w[stale rejected superseded].freeze

        Voice = Data.define(:name, :focus, :question)

        module_function

        def voices(env = ENV)
          wanted = env["MASTER_FIX_WISH_PERSONAS"].to_s.split(",").map(&:strip).reject(&:empty?)
          names = wanted.empty? ? DEFAULT : wanted
          council = council_rows
          names.map do |name|
            row = council[name.downcase]
            focus = [row&.role, row&.prompt].compact.join(": ")
            Voice.new(name: row&.name || name, focus: focus.empty? ? FALLBACK_FOCUS.fetch(name, name) : focus,
                      question: row&.question)
          end
        end

        # One model call per persona; a failed call costs that persona its turn only.
        def collect(agent:, base:, parse:, normalize:, env: ENV)
          drafts = voices(env).filter_map do |voice|
            items = normalize.call(parse.call(agent.ask(prompt(voice, base)))).first(PER_PERSONA)
            [voice.name, items] unless items.empty?
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "Fix::Wishlist::Personas.collect", persona: voice.name)
            nil
          end
          merge(drafts)
        end

        def council_rows
          require_relative "../../review/council/personas"
          Master::Review::Council::Personas.load.to_h { |persona| [persona.name.downcase, persona] }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Fix::Wishlist::Personas.council_rows")
          {}
        end

        def prompt(voice, base)
          <<~TEXT
            You are the #{voice.name} on the MASTER council, drafting only the wishes your own
            lens finds. Lens: #{voice.focus}.#{voice.question ? " Your question: #{voice.question}" : ""}
            Propose 0 to #{PER_PERSONA} items. Skip anything outside your lens; other personas
            cover it. Each item is a proposal for a later /fix, not an edit.

            #{base}
          TEXT
        end

        # drafts: [[voice_name, [normalized item, ...]], ...] -> items with
        # "proposed_by" (sorted names) and "weight", heaviest first.
        def merge(drafts)
          clusters = []
          drafts.each do |name, items|
            items.each do |item|
              home = clusters.find { |cluster| same?(cluster.first, item) }
              home ? home << item.merge("proposed_by" => [name]) : clusters << [item.merge("proposed_by" => [name])]
            end
          end
          clusters.map { |group| group.first.merge("proposed_by" => group.flat_map { |i| i["proposed_by"] }.uniq.sort) }
                  .map { |item| item.merge("weight" => item["proposed_by"].size) }
                  .sort_by.with_index { |item, index| [-item["weight"], index] }
        end

        # An open ledger row that already is this wish takes the new names
        # instead of a second row. True when absorbed.
        def absorb!(rows, item)
          home = rows.find do |row|
            !OPEN.include?(row["status"].to_s) &&
              (row["fingerprint"] == item["fingerprint"] || same?(row, item))
          end
          return false unless home

          names = (Array(home["proposed_by"]) + Array(item["proposed_by"])).uniq.sort
          home["proposed_by"] = names unless names.empty?
          home["weight"] = [names.size, 1].max
          true
        end

        def order(rows)
          rows.sort_by.with_index { |row, index| [-row.fetch("weight", 1).to_i, index] }
        end

        # Schema 1 rows predate attribution; one shared call drafted them.
        def migrate!(ledger)
          ledger["proposals"].each do |row|
            row["proposed_by"] ||= ["shared"]
            row["weight"] ||= 1
          end
          ledger["schema"] = 2
          ledger
        end

        def same?(left, right)
          return false unless left["anchor"] == right["anchor"]
          return true if left["id"] == right["id"]

          a = words(left["title"])
          b = words(right["title"])
          !a.empty? && !b.empty? && (a & b).size.to_f / (a | b).size >= SIMILARITY
        end

        def words(text) = text.to_s.downcase.scan(/[a-z0-9]+/).uniq
      end
    end
  end
end
