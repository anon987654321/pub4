# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "set"
require "time"
require_relative "../../../io/exec"
require_relative "../../../trace/dmesg"

module Master
  module CLI
    class Pipeline
      module Proof

        # The MASTER tests a repair could have broken, and the proof that runs only them.
        #
        # A whole-tree /fix proved by bin/check --profile=ci, whose test step alone ran past ten minutes,
        # and measured the same before its first edit, so a run that changed three files spent twenty
        # minutes proving them. The tests that name a changed file, by its path or its constant, prove
        # it; a change to the code every test boots through, or one that maps to more tests than a
        # narrow proof is worth, still takes the whole suite.

        # Main is rarely green, so a failure is judged against what the last whole suite of the tree
        # named (known red), kept on disk whenever one runs. Before the first there is no record, and
        # the pass measures its baseline the whole way, as it always did. MASTER_PROOF_FULL=1 keeps
        # every proof whole; MASTER_PROOF_STORE=0 keeps no record, as for the baselines.
        module Affected
          WIDE = %r{\A(?:lib/master\.rb|lib/boot/|test/test_helper\.rb|test/support|data/|Gemfile|Rakefile)}
          LIMIT = 80
          MAX_AGE_S = Integer(ENV.fetch("MASTER_PROOF_KNOWN_RED_MAX_AGE_S", 24 * 3600))
          KNOWN_RED = File.join(Master::ROOT, ".master", "proof_baselines")

          # What the last whole suite of a tree left red: its failing names and ratchet rows.
          Known = Data.define(:failing, :rows) do
            def new_failures(reading) = reading.failing.to_a - failing.to_a
            def worse_rows(reading) = reading.rows.select { |row, value| value > rows.fetch(row, 0) }.keys
          end

          module_function

          def enabled? = ENV["MASTER_PROOF_FULL"] != "1"
          def stored? = ENV["MASTER_PROOF_STORE"] != "0"

          def known_dir
            ENV["MASTER_PROOF_KNOWN_RED_DIR"] || File.join(ENV.fetch("MASTER_PROOF_STORE_DIR", KNOWN_RED), "known_red")
          end

          # Test files for these paths, relative to root, or nil when only the whole suite will do: a
          # change no test names is proved by all of them.
          def tests_for(paths, root: Master::ROOT)
            return if paths.empty? || paths.any? { |path| path.match?(WIDE) }

            tests = paths.flat_map { |path| naming_tests(path, root:) }.uniq.sort
            tests.empty? || tests.size > LIMIT ? nil : tests
          end

          def naming_tests(path, root:)
            return [path] if File.basename(path).start_with?("test_") && path.start_with?("test/")
            return [] unless path.end_with?(".rb") && path.start_with?("lib/")

            needles = [path.delete_prefix("lib/").delete_suffix(".rb"), constant_for(path)]
            args = needles.flat_map { |needle| ["-e", needle] }
            out, status = Master::Io::Exec.capture2("git", "grep", "-l", "-F", *args, "test/", chdir: root)
            status.success? ? out.split("\n").grep(%r{\Atest/.*test_[^/]+\.rb\z}) : []
          end

          def constant_for(path) = File.basename(path, ".rb").split("_").map(&:capitalize).join

          def known_red(tree)
            path = File.join(known_dir, "#{tree}.json")
            return unless stored? && File.file?(path)

            data = JSON.parse(File.read(path))
            stale = staleness(data)
            if stale
              Master::Trace::Dmesg.status("gate0", "known-red record #{stale}, proving whole")
              return
            end

            Known.new(failing: data.fetch("failing").to_set, rows: data.fetch("rows"))
          rescue JSON::ParserError, KeyError, SystemCallError, ArgumentError => e
            Master::Trace::Dmesg.status("gate0", "known-red record unreadable, proving whole: #{e.class}")
            nil
          end

          # Why a record no longer says what is red, or nil. A test another session broke after the
          # record was made would be blamed on the repair, so the record ages out, and a new Ruby or
          # lockfile changes what fails. No commit count: main moves dozens of commits a day.
          def staleness(data)
            return "made under another toolchain" unless data.fetch("toolchain", toolchain) == toolchain
            return "older than #{MAX_AGE_S / 3600}h" if Time.now.utc - Time.iso8601(data.fetch("at")) > MAX_AGE_S

            nil
          end

          def toolchain
            lock = File.join(Master::ROOT, "Gemfile.lock")
            [RUBY_VERSION, File.file?(lock) ? Digest::SHA256.file(lock).hexdigest[0, 16] : "none"].join(" ")
          end

          def note_known_red(tree, reading)
            return unless stored? && reading&.measured?

            FileUtils.mkdir_p(known_dir)
            data = { "failing" => reading.failing.to_a.sort, "rows" => reading.rows,
                     "at" => Time.now.utc.iso8601, "toolchain" => toolchain }
            File.write(File.join(known_dir, "#{tree}.json"), JSON.generate(data))
          end

          # Held when the run reached its summary, named no failure the tree did not already have, and
          # counted no ratchet row higher than the last whole suite did.
          def judge(reading, known)
            return [false, "proof: the tests did not reach their summary"] unless reading.finished.positive?

            fresh = known.new_failures(reading)
            worse = known.worse_rows(reading)
            return [true, "proof: no new failures, #{reading.failing.size} already red"] if fresh.empty? && worse.empty?

            [false, refusal(fresh, worse)]
          end

          def refusal(fresh, worse)
            line = "proof: #{fresh.size} new failure(s) #{fresh.first(8).join(", ")}"
            worse.empty? ? line : "#{line}; worse: #{worse.join(", ")}"
          end
        end
      end
    end
  end
end
