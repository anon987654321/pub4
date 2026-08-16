# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"

module Master
  module Ground
    class Constitution
      def initialize(dir: DIR, max_principles: nil, max_body_chars: nil)
        @dir = dir
        @max_principles = max_principles || self.class.max_principles
        @max_body_chars = max_body_chars || MAX_BODY_CHARS
        @principles = self.class.load_cached(@dir, max_principles: @max_principles, max_body_chars: @max_body_chars)
      end

      def empty? = @principles.empty?

      def system_prompt
        return if @principles.empty?

        "Constitutional principles (operator-declared, override defaults):\n#{list.join("\n")}"
      end

      def list
        @principles.map do |principle|
          detail = principle[:body].to_s.strip
          detail = principle[:description] if detail.empty?
          "#{principle[:type]}: #{principle[:name]} — #{detail}"
        end
      end

      def reload!
        self.class.clear_cache!(@dir)
        @principles = self.class.load_cached(@dir, max_principles: @max_principles, max_body_chars: @max_body_chars)
        self
      end

      class << self
        attr_writer :max_principles

        def max_principles
          @max_principles ||= (ENV["MASTER_MAX_PRINCIPLES"]&.to_i || 40)
        end

        def load_cached(dir, max_principles: nil, max_body_chars: nil)
          max_p = max_principles || self.max_principles
          @cache_mutex.synchronize do
            @constitution_cache[[dir, max_p]] ||= load_dir(dir, max_principles: max_p, max_body_chars:)
          end
        end

        def clear_cache!(dir = nil)
          @cache_mutex.synchronize do
            if dir
              @constitution_cache.delete_if { |key, _| key[0] == dir }
            else
              @constitution_cache.clear
            end
          end
        end

        private

        def load_dir(dir, max_principles:, max_body_chars:)
          return load_yaml(max_principles:, max_body_chars:).freeze if dir == DIR
          return [].freeze unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.md")).sort.filter_map { |path| parse(path, max_body_chars:) }
             .first(max_principles)
             .map(&:freeze)
             .freeze
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "constitution.load", dir:)
          [].freeze
        end

        def load_yaml(max_principles:, max_body_chars:)
          data = Master.law("operator_principles")
          Array(data["principles"]).first(max_principles).filter_map do |row|
            next unless row.is_a?(Hash)

            {
              name: row["name"].to_s,
              description: row["description"].to_s,
              type: row["type"].to_s,
              body: row["body"].to_s[0, max_body_chars || MAX_BODY_CHARS],
            }
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "constitution.load_yaml")
          []
        end

        def parse(path, max_body_chars:)
          fm = Master::Ground::Frontmatter.parse_file(path)
          return if fm[:meta].empty?

          meta = fm[:meta]
          body_limit = max_body_chars || MAX_BODY_CHARS
          {
            name: meta["name"].to_s,
            description: meta["description"].to_s,
            type: meta["type"].to_s,
            body: fm[:body][0, body_limit],
          }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "constitution.parse", path:)
          nil
        end
      end

      DIR = File.join(Master::ROOT, "data", "principles").freeze
      MAX_BODY_CHARS = 480
      @constitution_cache = {}
      @cache_mutex = Mutex.new
    end

    # Democratic amendment voting for constitutional principles.
    class Parliament
      def initialize(event_bus: nil)
        @bus = event_bus
        @amendments = load_amendments
        # Wire chain verification on load (from patch)
        return unless @amendments.any?
          ok, err = verify_chain
          @bus&.publish("parliament:chain_verify", ok:, error: err) if err

      end

      def propose(principle_id, new_text, rationale:, proposer:)
        amendment = build_amendment(principle_id, new_text, rationale, proposer)
        @amendments[amendment[:id]] = amendment
        save_amendments
        @bus&.publish("parliament:proposed", principle: principle_id, proposer:)
        Result.ok(amendment)
      rescue StandardError => e
        Result.err(e.message, category: :infrastructure)
      end

      def vote(amendment_id, voter:, stance:)
        amendment = @amendments[amendment_id]
        return Result.err("amendment not found") unless amendment
        return Result.err("already enacted") if amendment[:enacted_at]
        return Result.err("invalid stance") unless %w[approve reject abstain].include?(stance.to_s)

        amendment[:votes][voter.to_s] = stance.to_s
        save_amendments
        @bus&.publish("parliament:voted", amendment_id:, voter:, stance:)
        enact(amendment) if should_enact?(amendment)
        Result.ok(amendment)
      rescue StandardError => e
        Result.err(e.message, category: :infrastructure)
      end

      def active = @amendments.values.select { |a| a[:status] == "open" }

      def history(principle_id)
        @amendments.values
          .select { |a| a[:principle_id] == principle_id.to_s && a[:enacted_at] }
          .sort_by { |a| a[:enacted_at] }
      end

      # Verify cryptographic chain integrity. Returns [ok, error_message].
      def verify_chain
        enacted = @amendments.values
          .select { |a| a[:enacted_at] }
          .sort_by { |a| a[:enacted_at] }

        enacted.each_cons(2) do |prev, curr|
          return [false, "chain break at #{curr[:id]}: prev_hash mismatch"] if curr[:prev_hash] != prev[:hash]

          expected = Digest::SHA256.hexdigest(
            "#{curr[:principle_id]}:#{curr[:new_text]}:#{curr[:proposer]}:#{curr[:prev_hash]}",
          )
          return [false, "chain break at #{curr[:id]}: hash mismatch"] if curr[:hash] != expected
        end
        [true, nil]
      end

      private

      def build_amendment(principle_id, new_text, rationale, proposer)
        prev_hash = last_enacted_hash
        {
          id: SecureRandom.uuid,
          timestamp: Time.now.utc.iso8601,
          principle_id: principle_id.to_s,
          new_text: new_text.to_s,
          rationale: rationale.to_s,
          proposer: proposer.to_s,
          votes: {},
          status: "open",
          enacted_at: nil,
          prev_hash:,
          hash: Digest::SHA256.hexdigest("#{principle_id}:#{new_text}:#{proposer}:#{prev_hash}"),
        }
      end

      def last_enacted_hash
        enacted = @amendments.values
          .select { |a| a[:enacted_at] }
          .sort_by { |a| a[:enacted_at] }
        enacted.empty? ? "genesis" : enacted.last[:hash]
      end

      def should_enact?(amendment)
        votes = amendment[:votes].values
        return false if votes.size < QUORUM

        approvals = votes.count { |v| v == "approve" }
        approvals.to_f / votes.size >= THRESHOLD
      end

      def enact(amendment)
        amendment[:status] = "enacted"
        amendment[:enacted_at] = Time.now.utc.iso8601
        save_amendments
        @bus&.publish("parliament:enacted", principle: amendment[:principle_id], hash: amendment[:hash])
      end

      def load_amendments
        return {} unless File.exist?(STORE_PATH)

        JSON.parse(File.read(STORE_PATH), symbolize_names: true)
            .index_by { |a| a[:id] }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "parliament.load_amendments", path: STORE_PATH)
        {}
      end

      def save_amendments
        FileUtils.mkdir_p(File.dirname(STORE_PATH))
        ordered = @amendments.values.sort_by { |a| a[:timestamp] }
        File.write(STORE_PATH, JSON.pretty_generate(ordered))
      end

      QUORUM = 3
      THRESHOLD = 0.67
      STORE_PATH = File.join(Master::ROOT, ".master", "amendments.json")
    end
  end
end
