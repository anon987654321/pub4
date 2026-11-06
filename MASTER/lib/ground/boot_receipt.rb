# frozen_string_literal: true

require "digest"

module Master
  module Ground
    # What this process actually booted with, mechanically.
    #
    # boot_checks.rb proves the files parse, bin/doctor probes the host, and
    # boot_phases.rb names the order — three readings, none of them a single
    # answer to "what is in force right now". So a report could quote a rule
    # count from data/laws.yml while the scanner held a different registry, and
    # nothing compared them. This is the comparison: commit, constitution, the
    # three law populations, providers and capabilities in one hash, over a
    # digest of the files that decide behaviour.
    #
    # Deterministic: no timestamps, no host paths. Two boots of the same tree
    # produce the same digest, so a changed digest names a changed constitution
    # rather than a changed clock.
    #
    # It describes a full build because bin/doctor, its reader, always does one.
    module BootReceipt
      # Every file that changes what MASTER may do. A digest over these is what
      # makes "the same constitution" checkable, rather than a version string
      # somebody remembered to bump.
      GOVERNING_FILES = %w[
        data/soul.yml data/laws.yml data/law_runtime.yml data/providers.yml data/models.yml
        data/console.yml data/scan.yml data/budgets.yml
      ].freeze

      module_function

      NETWORK_CACHE_TTL = 30

      # No memory-store version and no model id. Those fields would let two
      # runs be diffed, and no reader diffs two receipts: bin/doctor prints one.
      # `commit` already names the checkout's HEAD. A field joins with the
      # reader that compares it.
      def build(root: MasterPaths::ROOT, agent: nil, memory: nil)
        {
          commit: commit(root),
          constitution: constitution(root),
          law:,
          providers:,
          capabilities:,
          degraded:,
          session: session(root:, agent:, memory:),
        }
      end

      def session(root: MasterPaths::ROOT, agent: nil, memory: nil)
        return {} unless agent || memory

        model = if agent&.respond_to?(:model)
                  agent.model
                end
        {
          commit: commit(root),
          constitution: digest(root:),
          memory_version: memory&.respond_to?(:version) ? memory.version : nil,
          model: model.to_s.empty? ? "unknown" : model.to_s,
        }.compact
      rescue StandardError => e
        Swallow.log(e, context: "BootReceipt.session")
        { commit: commit(root), constitution: digest(root:), memory_version: nil, model: "unknown" }
      end

      # One line per section, in authority order. bin/doctor prints these, so
      # the receipt has a reader rather than only a format.
      def lines(root: MasterPaths::ROOT)
        receipt = build(root:)
        law_counts = receipt[:law]
        lines = [
          "receipt: commit #{receipt[:commit]} constitution=#{receipt[:constitution][:digest]}",
          "receipt: soul #{receipt[:constitution][:soul_version]} " \
          "persona=#{receipt[:constitution][:persona]} " \
          "sacred_paths=#{receipt[:constitution][:sacred_paths]}",
          "receipt: law normative=#{law_counts[:normative]}, catalogue=#{law_counts[:catalogue]}, " \
          "scan=#{law_counts[:registry]}, executable=#{law_counts[:domain]}",
          "receipt: providers #{availability(receipt[:providers])}",
          "receipt: capabilities #{availability(receipt[:capabilities])}",
        ]
        lines << session_line(receipt[:session]) unless receipt[:session].empty?
        lines << degraded_line(receipt[:degraded])
        lines
      end

      def session_line(session)
        "receipt: session commit=#{session[:commit]} constitution=#{session[:constitution]} " \
          "memory=#{session[:memory_version] || "none"} model=#{session[:model]}"
      end

      def digest(root: MasterPaths::ROOT)
        parts = GOVERNING_FILES.map do |rel|
          path = File.join(root, rel)
          File.file?(path) ? Digest::SHA256.file(path).hexdigest : "absent"
        end
        Digest::SHA256.hexdigest(parts.join("\n"))[0, 16]
      end

      # git answers, rather than a hand-walk of .git. The walk opened
      # <root>/../.git/HEAD, and a worktree keeps .git as a file naming its real
      # git dir, so the path did not resolve and the receipt reported
      # `commit: unknown` in every checkout an agent is told to take.
      def commit(root)
        out, status = Master::Io::Exec.capture2e("git", "-C", root, "rev-parse", "--short=12", "HEAD")
        status.success? ? out.strip : "unknown"
      rescue StandardError
        "unknown"
      end

      # Through the existing readers, not around them. Opening soul.yml,
      # laws.yml and providers.yml here put each of the three one over its
      # reader ceiling, and lint:reader_singularity said so on the first run —
      # correctly. A receipt that reports what is in force must read it the way
      # the runtime does, or it reports a second parse of the same file.
      def constitution(root)
        soul = Laws.new(root:).soul_data
        {
          soul_version: soul["version"] || "unreadable",
          persona: soul["persona"],
          sacred_paths: Master::Soul.sacred_paths(root:).size,
          digest: digest(root:),
        }
      end

      # Report normative rows, per-Law execution metadata and the loaded
      # detector registry as distinct populations.
      def law(root: MasterPaths::ROOT)
        catalogue_count = Master.law_catalogue(root:).fetch("entries").size
        registry_count = domain_law_count(root)
        {
          normative: Master.law_entries(root:).size,
          catalogue: catalogue_count,
          registry: registry_count,
          domain: registry_count,
        }
      end

      def domain_law_count(root)
        law_root = executable_law_root(root)
        require File.join(law_root, "law", "definition.rb")
        ::Law.load_all(File.join(law_root, "law")) if ::Law.definitions.empty?
        ::Law.definitions.size
      rescue StandardError => e
        Swallow.log(e, context: "BootReceipt.domain_law_count", severity: :load_bearing)
        raise "boot receipt: executable law population unavailable: #{e.class}: #{e.message}"
      end

      def executable_law_root(root)
        candidates = [
          root,
          File.join(root, "MASTER"),
          MasterPaths::ROOT,
        ]
        candidates.find { |candidate| File.file?(File.join(candidate, "law", "definition.rb")) } || MasterPaths::ROOT
      end

      # `schema:` is a version pin, not a provider, and has no `env`; a non-Hash
      # row is skipped so it does not print as a permanently unavailable provider.
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
          "git" => Master.git_checkout?(MasterPaths::REPO),
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
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if defined?(@network_checked_at) && @network_checked_at && now - @network_checked_at < NETWORK_CACHE_TTL
          return @network_status
        end

        @network_status = begin
          require "socket"
          Socket.tcp("1.1.1.1", 53, connect_timeout: 1, &:close)
          true
        rescue StandardError
          false
        end
        @network_checked_at = now
        @network_status
      end

      def tts?
        Voice::Speech.available?
      rescue StandardError
        false
      end

      def availability(row)
        return "none" if row.empty?

        row.map { |name, ok| "#{name}=#{ok ? "yes" : "no"}" }.join(" ")
      end

      def degraded_line(names)
        return "receipt: degraded none" if names.empty?

        "receipt: degraded #{names.join(", ")} - anything above measured less than it claims"
      end
    end
  end
end
