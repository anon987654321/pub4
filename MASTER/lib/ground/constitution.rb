# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"

module Master
  module Ground
    class Constitution
      def initialize(dir: DIR)
        @dir = dir
        @principles = self.class.load_cached(@dir)
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
        @principles = self.class.load_cached(@dir)
        self
      end

      class << self
        def load_cached(dir)
          @cache_mutex.synchronize do
            @constitution_cache[dir] ||= load_dir(dir)
          end
        end

        def clear_cache!(dir = nil)
          @cache_mutex.synchronize do
            dir ? @constitution_cache.delete(dir) : @constitution_cache.clear
          end
        end

        private

        def load_dir(dir)
          return load_yaml.freeze if dir == DIR && File.file?(YAML_PATH)
          return [].freeze unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.md")).sort.filter_map { |path| parse(path) }
             .first(MAX_PRINCIPLES)
             .map(&:freeze)
             .freeze
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "constitution.load", dir:)
          [].freeze
        end

        def load_yaml
          data = Master.load_yaml(YAML_PATH)
          Array(data["principles"]).first(MAX_PRINCIPLES).filter_map do |row|
            next unless row.is_a?(Hash)

            {
              name: row["name"].to_s,
              description: row["description"].to_s,
              type: row["type"].to_s,
              body: row["body"].to_s[0, MAX_BODY_CHARS],
            }
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "constitution.load_yaml")
          []
        end

        def parse(path)
          fm = Master::Ground::Frontmatter.parse_file(path)
          return if fm[:meta].empty?

          meta = fm[:meta]
          {
            name: meta["name"].to_s,
            description: meta["description"].to_s,
            type: meta["type"].to_s,
            body: fm[:body][0, MAX_BODY_CHARS],
          }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "constitution.parse", path:)
          nil
        end
      end

      YAML_PATH = File.join(Master::ROOT, "data", "operator_principles.yml").freeze
      DIR = File.join(Master::ROOT, "data", "principles").freeze
      MAX_PRINCIPLES = 40
      MAX_BODY_CHARS = 480
      @constitution_cache = {}
      @cache_mutex = Mutex.new
    end

    # Democratic amendment voting for constitutional principles.
    class Parliament
      def initialize(event_bus: nil)
        @bus = event_bus
        @amendments = load_amendments
      end

      def propose(principle_id, new_text, rationale:, proposer:)
        amendment = {
          id: SecureRandom.uuid,
          timestamp: Time.now.utc.iso8601,
          principle_id: principle_id.to_s,
          new_text: new_text.to_s,
          rationale: rationale.to_s,
          proposer: proposer.to_s,
          votes: {},
          status: "open",
          enacted_at: nil,
          hash: Digest::SHA256.hexdigest("#{principle_id}:#{new_text}:#{proposer}"),
        }
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

      private

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
