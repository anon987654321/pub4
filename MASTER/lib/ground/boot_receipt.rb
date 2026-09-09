# frozen_string_literal: true

require "digest"

module Master
  module Ground
    # What this process actually booted with, mechanically.
    #
    # boot_checks.rb proves the files parse, bin/doctor probes the host, and
    # boot_phases.rb names the order — three readings, none of them a single
    # answer to "what is in force right now". So a report could quote a rule
    # count from data/rules.yml while the scanner held a different registry, and
    # nothing compared them. This is the comparison: commit, constitution, the
    # three rule populations, providers and capabilities in one hash, over a
    # digest of the files that decide behaviour.
    #
    # Deterministic: no timestamps, no host paths. Two boots of the same tree
    # produce the same digest, so a changed digest names a changed constitution
    # rather than a changed clock.
    module BootReceipt
      # Every file that changes what MASTER may do. A digest over these is what
      # makes "the same constitution" checkable, rather than a version string
      # somebody remembered to bump.
      GOVERNING_FILES = %w[
        data/soul.yml data/rules.yml data/providers.yml data/models.yml data/limits.yml
      ].freeze

      module_function

      def build(root: MasterPaths::ROOT)
        {
          commit: commit(root),
          constitution: constitution(root),
          law:,
          providers:,
          capabilities:,
          degraded:,
        }
      end

      # One line per section, in authority order. bin/doctor prints these, so
      # the receipt has a reader rather than only a format.
      def lines(root: MasterPaths::ROOT)
        receipt = build(root:)
        law_counts = receipt[:law]
        [
          "receipt: commit #{receipt[:commit]} constitution=#{receipt[:constitution][:digest]}",
          "receipt: soul #{receipt[:constitution][:soul_version]} " \
          "persona=#{receipt[:constitution][:persona]} " \
          "sacred_paths=#{receipt[:constitution][:sacred_paths]}",
          "receipt: law #{law_counts[:declared]} declared, #{law_counts[:registry]} scan rules, " \
          "#{law_counts[:domain]} in law/",
          "receipt: providers #{availability(receipt[:providers])}",
          "receipt: capabilities #{availability(receipt[:capabilities])}",
          degraded_line(receipt[:degraded]),
        ]
      end

      def digest(root: MasterPaths::ROOT)
        parts = GOVERNING_FILES.map do |rel|
          path = File.join(root, rel)
          File.file?(path) ? Digest::SHA256.file(path).hexdigest : "absent"
        end
        Digest::SHA256.hexdigest(parts.join("\n"))[0, 16]
      end

      def commit(root)
        head = File.join(root, "..", ".git", "HEAD")
        return "unknown" unless File.file?(head)

        ref = File.read(head).strip
        return ref[0, 12] unless ref.start_with?("ref: ")

        path = File.join(root, "..", ".git", ref.delete_prefix("ref: "))
        File.file?(path) ? File.read(path).strip[0, 12] : "unknown"
      rescue StandardError
        "unknown"
      end

      # Through the existing readers, not around them. Opening soul.yml,
      # rules.yml and providers.yml here put each of the three one over its
      # reader ceiling, and lint:reader_singularity said so on the first run —
      # correctly. A receipt that reports what is in force must read it the way
      # the runtime does, or it reports a second parse of the same file.
      def constitution(root)
        soul = Rules.new(root:).soul_data
        {
          soul_version: soul["version"] || "unreadable",
          persona: soul["persona"],
          sacred_paths: Array(soul.dig("absolute", "sacred_paths")).size,
          digest: digest(root:),
        }
      end

      # Three populations, counted from what is loaded rather than from a number
      # in prose. They are allowed to differ — 78 declared rules resolve through
      # a fold and carry no detector — but a receipt that prints one of them as
      # the total is the misreport this exists to prevent.
      # `rules:` is a flat array, whatever CLAUDE.md's enumeration snippet says
      # about scopes — that snippet raises on this file. Counting the array is
      # the reading that matches the data.
      def law(root: MasterPaths::ROOT)
        {
          declared: Array(Master.law("rules", root:)).size,
          registry: Review::Scan::Rule.registry.size,
          domain: domain_rule_count(root),
        }
      end

      # Loaded here rather than assumed: law/ reaches the registry only when
      # something has required it, so a receipt printed from bin/doctor said
      # "0 in law/" while 122 rules were defined and waiting.
      def domain_rule_count(root)
        require File.join(root, "law", "law.rb")
        ::Law.load_all(File.join(root, "law")) if ::Law.rules.empty?
        ::Law.rules.size
      rescue StandardError => e
        Swallow.log(e, context: "BootReceipt.domain_rule_count")
        0
      end

      # `schema:` is a version pin, not a provider, and it has no `env` — so it
      # printed as a permanently unavailable provider and put the receipt one
      # short of honest.
      def providers(root: MasterPaths::ROOT)
        rows = Master.provider_config(root:)
        keyed = rows.filter_map do |name, row|
          next unless row.is_a?(Hash)

          [name, Array(row["env"]).any? { |key| ENV[key].to_s.strip.length.positive? }]
        end.to_h
        keyed.merge("agy" => Master.agy_cli_available?)
      end

      # What the process can do, as against what it is configured for.
      #
      # `network` is the one MASTER-136 asks for by name: offline is a capability
      # state, not a mysterious failure, and one `network=no` explains every
      # provider miss printed under it.
      def capabilities
        {
          "network" => network?,
          "tts" => tts?,
          "local_models" => ENV["OLLAMA_BASE_URL"].to_s.strip.length.positive?,
          "git" => File.directory?(File.join(MasterPaths::REPO, ".git")),
        }
      end

      def degraded
        missing = capabilities.reject { |_name, ok| ok }.keys
        missing << "providers" if providers.none? { |_name, ok| ok }
        missing
      end

      # A TCP open, not a DNS lookup: a captive portal answers DNS and nothing
      # else, which is the case that reads as "the model is down".
      def network?
        require "socket"
        Socket.tcp("1.1.1.1", 53, connect_timeout: 1, &:close)
        true
      rescue StandardError
        false
      end

      def tts?
        Voice::Speech.edge_tts_ready?
      rescue StandardError
        false
      end

      def availability(row)
        return "none" if row.empty?

        row.map { |name, ok| "#{name}=#{ok ? "yes" : "no"}" }.join(" ")
      end

      def degraded_line(names)
        return "receipt: degraded none" if names.empty?

        "receipt: degraded #{names.join(", ")} — anything above measured less than it claims"
      end
    end
  end
end
