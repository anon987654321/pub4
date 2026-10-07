# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "yaml"
require_relative "../ai/orientation"
require_relative "../io/atomic_write"
require_relative "../io/git_operations"
require_relative "../review/scan/semantic_fingerprint"

module Master
  module Fix
    # Converts the end of a /fix run into a bounded, evidence-linked next-work
    # queue. It proposes; it does not silently edit source. Concrete wishes are
    # surfaced to the next /fix through the orientation layer.
    class Wishlist
      include Master::Io::AtomicWrite

      LEDGER_PATH = ".master/fix_wishlist.json"
      SCHEMA = 1
      MAX_NEW_ITEMS = 12
      MAX_PROPOSALS = 96
      BATCH_SIZE = 6
      MAX_ATTEMPTS = 3
      TERMINAL_STATUSES = %w[verified blocked rejected stale superseded].freeze
      AUTO_IMPLEMENTATIONS = %w[next_fix].freeze
      RULE_ID = "CONVERGENCE_WISHLIST"

      Rule = Data.define(:id) do
        def severity = :warning
      end

      def initialize(root:, agent:, event_bus: nil)
        @root = File.expand_path(root)
        @agent = agent
        @bus = event_bus
        @git = Master::Io::GitOperations.new(@root)
      end

      def call(state:, target:, run_id:)
        return "wishlist: skipped — no model" unless @agent.respond_to?(:ask)

        orientation = Master::AI::Orientation.render(root: @root, target:, depth: 2, max_entries: 80)
        response = @agent.ask(prompt(orientation:, state:, target:, run_id:))
        items = normalize(parse(response))
        ledger = load_ledger
        added = merge_new_items!(ledger, items, state:, target:, run_id:)
        save_ledger(ledger)

        queued = ledger["proposals"].count do |item|
          item["status"] == "queued" && AUTO_IMPLEMENTATIONS.include?(item["implementation"])
        end
        @bus&.publish(
          "wishlist:done",
          drafted: items.size,
          added:,
          queued:,
          target: relative(target),
          state:,
        )
        "wishlist: drafted #{items.size}, queued #{queued} → #{LEDGER_PATH}"
      rescue StandardError => e
        @bus&.publish("wishlist:error", error: e.message, state:, target:)
        "wishlist: #{e.class}: #{e.message}"
      end

      def self.pending_context(root, target: root, limit: BATCH_SIZE)
        new(root:, agent: nil).render_pending(target:, limit:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.pending_context")
        nil
      end

      def claimable(target:, limit: BATCH_SIZE, run_id: nil)
        ledger = load_ledger
        head = @git.head
        changed = false
        rows = ledger["proposals"].filter_map do |proposal|
          if proposal["status"] == "claimed"
            proposal["status"] = "queued"
            proposal.delete("claimed_at")
            proposal.delete("claimed_run")
            changed = true
          end
          next unless proposal["status"] == "queued"
          next unless AUTO_IMPLEMENTATIONS.include?(proposal["implementation"])

          anchor = anchor_file(proposal["anchor"])
          unless anchor
            proposal["status"] = "stale"
            proposal["stale_reason"] = "anchor missing"
            changed = true
            next
          end
          next unless anchor_in_target?(anchor, target)

          current_digest = Digest::SHA256.file(anchor).hexdigest
          recorded_digest = proposal["anchor_sha256"].to_s
          if recorded_digest.empty? || recorded_digest != current_digest
            proposal["status"] = "stale"
            proposal["stale_reason"] = "anchor changed since proposal"
            proposal["stale_at"] = Time.now.utc.iso8601
            changed = true
            @bus&.publish("wishlist:stale", id: proposal["uid"], reason: proposal["stale_reason"])
            next
          end

          if head.to_s.empty?
            next
          elsif proposal["basis_head"].to_s != head.to_s
            proposal["basis_head"] = head
            proposal["rebased_at"] = Time.now.utc.iso8601
            changed = true
          end

          next if run_id && proposal["last_attempt_run"].to_s == run_id.to_s
          proposal
        end.first(limit.to_i)

        save_ledger(ledger) if changed
        rows
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.claimable", event_bus: @bus)
        []
      end

      def claim!(proposals, run_id:)
        ids = Array(proposals).map { |proposal| proposal["uid"].to_s }.reject(&:empty?)
        return [] if ids.empty?

        ledger = load_ledger
        now = Time.now.utc.iso8601
        claimed = ledger["proposals"].filter_map do |proposal|
          next unless ids.include?(proposal["uid"].to_s) && proposal["status"] == "queued"

          proposal["status"] = "claimed"
          proposal["claimed_at"] = now
          proposal["claimed_run"] = run_id.to_s
          proposal
        end
        save_ledger(ledger)
        @bus&.publish("wishlist:claimed", run_id:, count: claimed.size)
        claimed
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.claim!", event_bus: @bus)
        []
      end

      def mark_attempt(proposal_id:, fixed:, status:, message:, run_id:)
        ledger = load_ledger
        proposal = ledger["proposals"].find { |item| item["uid"].to_s == proposal_id.to_s }
        return unless proposal

        attempts = proposal.fetch("attempts", 0).to_i + 1
        proposal["attempts"] = attempts
        proposal["last_attempt_run"] = run_id.to_s
        proposal["last_outcome"] = status.to_s
        proposal["last_message"] = message.to_s.byteslice(0, 500)

        if fixed.to_i.positive?
          proposal["status"] = "claimed"
          proposal["last_fixed"] = fixed.to_i
        elsif %i[human_decision needs_person].include?(status.to_sym)
          proposal["status"] = "blocked"
        elsif attempts >= MAX_ATTEMPTS
          proposal["status"] = "blocked"
          proposal["blocked_reason"] = "attempt limit reached"
        else
          proposal["status"] = "queued"
        end

        save_ledger(ledger)
        @bus&.publish(
          "wishlist:attempt",
          id: proposal_id,
          status: proposal["status"],
          outcome: status,
          fixed: fixed.to_i,
          attempts:,
        )
        proposal
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.mark_attempt", event_bus: @bus)
        nil
      end

      def mark_delivered(proposal_ids:, run_id:)
        ids = Array(proposal_ids).map(&:to_s)
        return [] if ids.empty?

        ledger = load_ledger
        changed = ledger["proposals"].filter_map do |proposal|
          next unless ids.include?(proposal["uid"].to_s)
          next unless proposal["status"] == "claimed"
          next unless proposal.fetch("last_fixed", 0).to_i.positive?

          proposal["status"] = "applied"
          proposal["applied_at"] = Time.now.utc.iso8601
          proposal["applied_run"] = run_id.to_s
          proposal.delete("claimed_at")
          proposal.delete("claimed_run")
          proposal
        end
        save_ledger(ledger) unless changed.empty?
        changed
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.mark_delivered", event_bus: @bus)
        []
      end

      def mark_verified(proposal_ids:, run_id:)
        ids = Array(proposal_ids).map(&:to_s)
        return [] if ids.empty?

        ledger = load_ledger
        changed = ledger["proposals"].filter_map do |proposal|
          next unless ids.include?(proposal["uid"].to_s)
          next unless proposal["status"] == "applied"

          proposal["status"] = "verified"
          proposal["verified_at"] = Time.now.utc.iso8601
          proposal["verified_run"] = run_id.to_s
          proposal
        end
        save_ledger(ledger) unless changed.empty?
        changed
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.mark_verified", event_bus: @bus)
        []
      end

      def pending_count(target:)
        claimable(target:, limit: MAX_PROPOSALS).size
      end

      def render_pending(target:, limit: BATCH_SIZE)
        rows = claimable(target:, limit:)
        return if rows.empty?

        body = rows.map do |proposal|
          proof = Array(proposal["proof"]).join(", ")
          [
            "proposal: #{proposal["uid"]}",
            "title: #{proposal["title"]}",
            "anchor: #{proposal["anchor"]}",
            "change: #{proposal["change"]}",
            "evidence: #{proposal["evidence"]}",
            "proof: #{proof}",
            "effort: #{proposal["effort"]}",
            "reversibility: #{proposal["reversibility"]}",
          ].join("\n")
        end

        <<~TEXT.strip
          Pending automatic convergence proposals from the durable /fix ledger.
          Treat each queued next_fix proposal as an actual bounded repair target.
          Do not treat this as a TODO list. Re-check the live source and constitutional
          rules before mutation. Unsupported, stale, operator-owned, or research-only
          work is not automatically completed.

          #{body.join("\n\n")}
        TEXT
      end

      def self.findings(proposals, root:)
        Array(proposals).filter_map do |proposal|
          path, line = proposal["anchor"].to_s.split(":", 2)
          next if path.to_s.empty? || line.to_s !~ /\A\d+\z/

          file = File.expand_path(path, root)
          next unless File.file?(file)

          fingerprint = Master::Review::Scan::SemanticFingerprint.for(File.read(file, encoding: "UTF-8"))
          proof = Array(proposal["proof"]).join(", ")
          {
            rule: RULE_ID,
            file:,
            line: line.to_i,
            severity: :warning,
            confidence: 1.0,
            reversibility: proposal["reversibility"].to_s,
            blast_radius: { files_touched: 1 },
            fingerprint:,
            message: "#{proposal["title"]}: #{proposal["rationale"]}",
            fix: [
              proposal["change"],
              "Evidence: #{proposal["evidence"]}",
              ("Proof contract: #{proof}" unless proof.empty?),
            ].compact.join("\n"),
            wishlist_id: proposal["uid"].to_s,
            wishlist_proposal: proposal,
          }
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.findings")
        []
      end

      private

      def ledger_path
        File.join(@root, LEDGER_PATH)
      end

      def load_ledger
        return { "schema" => SCHEMA, "proposals" => [] } unless File.file?(ledger_path)

        data = JSON.parse(File.read(ledger_path, encoding: "UTF-8"))
        raise "wishlist ledger schema #{data["schema"]} is unsupported" unless data["schema"].to_i == SCHEMA
        raise "wishlist ledger proposals must be an array" unless data["proposals"].is_a?(Array)

        data
      rescue JSON::ParserError => e
        raise "wishlist ledger is corrupt: #{e.message}"
      end

      def save_ledger(data)
        FileUtils.mkdir_p(File.dirname(ledger_path))
        write_atomic(ledger_path, JSON.pretty_generate(data) + "\n", mode: 0o600)
      end

      def merge_new_items!(ledger, items, state:, target:, run_id:)
        now = Time.now.utc.iso8601
        basis_head = @git.head.to_s
        added = 0

        items.each do |item|
          anchor = item["anchor"].to_s
          fingerprint = proposal_fingerprint(item)
          next if ledger["proposals"].any? do |existing|
            existing["fingerprint"].to_s == fingerprint &&
              !%w[stale rejected superseded].include?(existing["status"].to_s)
          end

          ledger["proposals"] << item.merge(
            "uid" => "#{item["id"]}-#{fingerprint[0, 12]}",
            "fingerprint" => fingerprint,
            "status" => "queued",
            "attempts" => 0,
            "created_at" => now,
            "generated_by_run" => run_id.to_s,
            "generated_state" => state.to_s,
            "target" => relative(target),
            "basis_head" => basis_head,
            "anchor_sha256" => anchor_sha256(anchor),
          )
          added += 1
        end

        prune!(ledger)
        added
      end

      def prune!(ledger)
        rows = ledger["proposals"]
        return if rows.size <= MAX_PROPOSALS

        terminal = rows.select { |proposal| TERMINAL_STATUSES.include?(proposal["status"].to_s) }
        drop = [rows.size - MAX_PROPOSALS, terminal.size].min
        ledger["proposals"] = rows - terminal.first(drop)
        ledger["proposals"] = ledger["proposals"].last(MAX_PROPOSALS) if ledger["proposals"].size > MAX_PROPOSALS
      end

      def proposal_fingerprint(item)
        Digest::SHA256.hexdigest(
          [
            item["id"],
            item["title"],
            item["anchor"],
            item["change"],
            item["evidence"],
            Array(item["proof"]).join("|"),
          ].join("\n"),
        )
      end

      def anchor_sha256(anchor)
        file = anchor_file(anchor)
        file ? Digest::SHA256.file(file).hexdigest : nil
      end

      def anchor_file(anchor)
        path, line = anchor.to_s.split(":", 2)
        return unless path && line.to_s.match?(/\A\d+\z/)

        file = File.expand_path(path, @root)
        return unless inside_root?(file) && File.file?(file)

        file
      end

      def anchor_in_target?(anchor, target)
        target = File.expand_path(target.to_s, @root)
        anchor == target || anchor.start_with?("#{target}#{File::SEPARATOR}")
      end

      def inside_root?(path)
        full = File.expand_path(path)
        full == @root || full.start_with?("#{@root}#{File::SEPARATOR}")
      end

      def relative(path)
        full = File.expand_path(path.to_s, @root)
        return "." if full == @root
        return path.to_s unless full.start_with?("#{@root}#{File::SEPARATOR}")

        full.delete_prefix("#{@root}#{File::SEPARATOR}")
      end

      def prompt(orientation:, state:, target:, run_id:)
        <<~PROMPT
          You are proposing the next bounded work queue after a completed MASTER /fix run.
          Do not claim a defect unless the supplied evidence supports it.
          Do not repeat work that is already marked done. Prefer concrete improvements
          that a later /fix can implement and verify.

          Run:
          state: #{state}
          target: #{target}
          run_id: #{run_id}

          Orientation:
          #{orientation}

          Produce 0 to #{MAX_NEW_ITEMS} wishlist items as YAML.
          Each item must contain:
          - id: snake_case
          - title: short human-readable name
          - rationale: one sentence
          - anchor: repository-relative path:line, or run:<state>
          - change: one concrete implementation sentence
          - effort: cheap, medium, or deep
          - reversibility: reversible, guarded, or operator
          - implementation: next_fix, research, or operator
          - evidence: one sentence using only facts present in the supplied orientation/run
          - proof: 0 to 6 concrete checks that can verify the proposed change

          Prefer automatic next_fix only for bounded, evidence-backed changes anchored in
          a real file. Use research when more investigation is needed and operator when
          a human, credential, device, external service, irreversible decision, or
          real-world observation is required.

          Do not invent external purchases, users, scale numbers, credentials, incidents,
          benchmarks, or measurements. Never pad the list to reach a quota.
          Return only the YAML array. No Markdown fences and no prose.
        PROMPT
      end

      def parse(text)
        body = text.to_s.sub(/\A.*?(?=^- |\A- )/m, "").sub(/\n```.*\z/m, "").strip
        data = YAML.safe_load(body, aliases: false)
        data.is_a?(Array) ? data : []
      rescue Psych::Exception => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.parse")
        []
      end

      def normalize(items)
        items.filter_map do |item|
          next unless item.is_a?(Hash)

          id = slug(item["id"] || item["title"])
          anchor = item["anchor"].to_s.strip
          next if id.empty?
          next if item["title"].to_s.strip.empty? || item["rationale"].to_s.strip.empty?
          next if item["change"].to_s.strip.empty? || item["evidence"].to_s.strip.empty?
          next unless valid_anchor?(anchor)

          reversibility = normalize_choice(item["reversibility"], %w[reversible guarded operator], "guarded")
          implementation = normalize_choice(item["implementation"], %w[next_fix research operator], "operator")
          implementation = "operator" if reversibility == "operator" && implementation == "next_fix"
          implementation = "operator" unless anchor_file(anchor) || implementation != "next_fix"

          {
            "id" => id,
            "title" => item["title"].to_s.strip,
            "rationale" => item["rationale"].to_s.strip,
            "anchor" => anchor,
            "change" => item["change"].to_s.strip,
            "effort" => normalize_choice(item["effort"], %w[cheap medium deep], "medium"),
            "reversibility" => reversibility,
            "implementation" => implementation,
            "evidence" => item["evidence"].to_s.strip,
            "proof" => Array(item["proof"]).map { |value| value.to_s.strip }.reject(&:empty?).first(6),
          }
        end.uniq { |item| [item["id"], item["anchor"], item["change"]] }.first(MAX_NEW_ITEMS)
      end

      def valid_anchor?(anchor)
        return true if anchor.match?(/\Arun:[a-z_]+\z/i)

        !anchor_file(anchor).nil?
      end

      def normalize_choice(value, allowed, fallback)
        choice = value.to_s.downcase
        allowed.include?(choice) ? choice : fallback
      end

      def slug(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")[0, 64]
      end

      def write_report(items, state:, target:, run_id:)
        FileUtils.mkdir_p(File.dirname(out_file))
        body = [
          "# MASTER wishlist — #{Time.now.utc.iso8601}",
          "",
          "run: #{run_id}",
          "target: #{target}",
          "state: #{state}",
          "items: #{items.size}",
          "",
        ]

        items.each_with_index do |item, index|
          body << "### #{index + 1}. #{item["title"]}"
          body << ""
          body << "#{item["rationale"]} [#{item["effort"]}; #{item["implementation"]}]"
          body << "id: #{item["id"]}"
          body << "anchor: #{item["anchor"]}"
          body << "change: #{item["change"]}"
          body << "evidence: #{item["evidence"]}"
          body << "implementation: #{item["implementation"]}"
          body << "reversibility: #{item["reversibility"]}"
          body << ""
        end

        File.write(out_file, body.join("\n"))
      end
    end
  end
end
