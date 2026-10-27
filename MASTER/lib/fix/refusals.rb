# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "../boot/paths"
require_relative "../ground/swallow"

module Master
  module Fix

    # Every per-fix gate that turns a repair down says so here, with a reason:
    # one dmesg line, one row in .master/fix_refusals.jsonl, one count for the
    # pass summary. Refusals that read "UNSAFE" or "blocked" with nothing more
    # hid their cause in swallowed_errors.jsonl; a reasonless refusal is the
    # gate's defect, so it raises unless an exception can stand in for one.
    module Refusals
      LOG_PATH = File.join(MasterPaths::ROOT, ".master", "fix_refusals.jsonl").freeze
      MAX_BYTES = 5_242_880
      KEEP_BACKUPS = 3

      # The order the pass summary names them in; a gate not listed still counts.
      GATES = %i[budget scope verifier consensus collapse new_violations boyscout priority test compile primitive visual
                 exception lint commit].freeze

      class MissingReason < ArgumentError; end

      @mutex = Mutex.new
      @pass = Hash.new(0)

      class << self
        # context: error: (an exception the gate swallowed; it stands in for a
        # missing reason), law:, and root: (what file is named relative to).
        def record(gate:, file:, reason: nil, **context)
          error = context[:error]
          text = reason_for(gate, reason:, error:)
          rel = relative(file, context[:root])
          @mutex.synchronize { @pass[gate.to_sym] += 1 }

          Master::Trace::Dmesg.status("fix0", "#{rel} refused by #{gate}: #{text[0, 300]}")
          append(at: Time.now.utc.iso8601, gate: gate.to_s, file: rel, law: context[:law]&.to_s, reason: text,
                 error: error && "#{error.class}: #{error.message}")
          text
        end

        # "fix0: refusals this pass: budget=0 scope=2 ...", then a fresh count.
        def pass_summary_line
          counts = @mutex.synchronize { @pass.dup.tap { @pass = Hash.new(0) } }
          gates = GATES + (counts.keys - GATES)
          "fix0: refusals this pass: #{gates.map { |gate| "#{gate}=#{counts.fetch(gate, 0)}" }.join(" ")}"
        end

        def begin_run! = @mutex.synchronize { @pass = Hash.new(0) }

        def counts = @mutex.synchronize { @pass.dup }

        # The suite points it at a temporary file (test_helper).
        def log_path = ENV.fetch("MASTER_FIX_REFUSALS_PATH", LOG_PATH)

        private

        def relative(files, root)
          prefix = "#{root || MasterPaths::REPO}/"
          Array(files).map { |path| path.to_s.delete_prefix(prefix) }.join(", ")
        end

        def reason_for(gate, reason:, error:)
          text = reason.to_s.strip
          raised = error && "#{error.class}: #{error.message}".strip
          return raised if text.empty? && raised
          raise MissingReason, "#{gate} refused a repair without a reason" if text.empty?

          raised && !text.include?(error.message.to_s) ? "#{text} (#{raised})" : text
        end

        # A refusal that cannot be written is still printed and counted; the
        # write failing must not turn into a second, silent refusal. The lock is
        # a sidecar because rotation renames the log out from under its holder.
        def append(row)
          line = "#{JSON.generate(row.compact)}\n"
          FileUtils.mkdir_p(File.dirname(log_path), mode: 0o700)

          File.open("#{log_path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
            lock.flock(File::LOCK_EX)
            Master::Ground::Swallow.rotate!(path: log_path, max_bytes: MAX_BYTES - line.bytesize, keep: KEEP_BACKUPS)

            File.open(log_path, File::WRONLY | File::CREAT | File::APPEND, 0o600) { |file| file.write(line) }
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Fix::Refusals.append")
        end
      end
    end
  end
end
