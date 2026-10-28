# frozen_string_literal: true

require "digest"
require "json"
require "prism"
require "yaml"
require "fileutils"
require "tmpdir"

module Master
  module Fix
    # The one place that decides whether a deterministic autofix may touch a
    # file, and whether what it wrote may stay. Two runs on 2026-10-12 changed
    # 105 and 108 files before any model was asked: RuboCop rewrote a nested
    # ternary in cli/face/ascii.rb into an `if` with unindented branches (the
    # golden-frame test went red), and the universal whitespace transforms edited
    # laws.yml and tokens.yml. Every deterministic writer (MechanicalAutofix and
    # the RuboCop pass) asks this module before it opens a file and after it
    # writes one.
    #
    # State is per process, which is per run: one /fix is one process.
    module AutofixGuard
      MODES = %w[off dry on].freeze
      DEFAULT_MAX_FILES = 15
      TEST_TIMEOUT_S = 120
      DATA_EXTENSIONS = %w[.yml .yaml .json .tsv .csv .toml .conf].freeze

      # Rendered or irreplaceable output, matched against the absolute path.
      # laws.yml and soul.yml are sacred paths soul.yml declares and are refused
      # by protected_reason; tokens.yml is not sacred, so it is named here.
      PROTECTED = [
        %r{/MASTER/data/tokens\.yml\z},
        %r{/MASTER/lib/cli/face/},
        %r{/MASTER/lib/cli/face\.rb\z},
        %r{/MASTER/lib/voice/},
        %r{/MASTER/(?:lib|test|data)/.*(?:tts|voice)[^/]*\.(?:rb|yml)\z}i,
        %r{/STUDIO/dilla/},
        %r{/STUDIO/postpro/},
        %r{/golden[^/]*/}i,
        %r{golden[^/]*\.(?:txt|json|ya?ml|rb|png|wav|mp4)\z}i,
      ].freeze

      Record = Struct.new(:path, :reason, keyword_init: true)

      @mutex = Mutex.new
      @mode = nil
      @written = []
      @written_digests = {}
      @originals = {}
      @refused = []
      @capped = []
      @patch = nil

      class << self
        # off, dry or on. A flag (--autofix=) sets it; the environment is the default.
        def mode
          @mode || ENV.fetch("MASTER_AUTOFIX_MODE", "on").downcase.then { |m| MODES.include?(m) ? m : "on" }
        end

        # The explicit override belongs to one CLI operation, not the whole
        # interactive session. nil means use the environment default next time.
        def explicit_mode_override
          @mode
        end

        def restore_mode_override(value)
          @mutex.synchronize { @mode = value }
        end

        def mode=(value)
          value = value.to_s.downcase
          raise ArgumentError, "--autofix expects #{MODES.join("|")}, got #{value.inspect}" unless MODES.include?(value)

          @mode = value
        end

        def max_files
          Integer(ENV.fetch("MASTER_AUTOFIX_MAX_FILES", DEFAULT_MAX_FILES.to_s), exception: false) || DEFAULT_MAX_FILES
        end

        def reset!
          @mutex.synchronize do
            @mode = nil
            @written = []
            @written_digests = {}
            @originals = {}
            @refused = []
            @capped = []
            @patch = nil
          end
        end

        # The reason a path may not be opened, or nil. Read-only: the sacred
        # paths come from soul.yml and are never written through here.
        def protected_reason(path, root: nil)
          absolute = File.expand_path(path.to_s)
          hit = PROTECTED.find { |pattern| absolute.match?(pattern) }
          return "protected path (#{pattern_name(hit)})" if hit
          if (sacred = Master::Core::Constitution::Paths.write_refusal(absolute, root:))
            return "protected path (#{sacred})"
          end

          nil
        end

        # nil when the file may be opened for an autofix, else the reason.
        # Cap and off are the run's budget, not the file's fault, so they are
        # recorded apart from refusals.
        def admit(path, root: nil)
          return "autofix is off" if mode == "off"

          if (why = protected_reason(path, root:))
            note_refused(path, why)
            return why
          end
          return unless capped?(path)

          note_capped(path)
          "per-run cap of #{max_files} files reached"
        end

        def capped?(path)
          @mutex.synchronize { !@written.include?(path.to_s) && @written.size >= max_files }
        end

        # A candidate that must not be written, or nil: it does not parse, or it
        # only moves whitespace in a data file.
        def candidate_reason(path, before, after)
          return "no change" if before == after
          return "whitespace-only edit to data file" if data_file?(path) && squeezed(before) == squeezed(after)

          failure = parse_failure(path, after)
          failure && "does not parse: #{failure}"
        end

        # After the write: the file's mapped test, test_<stem>.rb in the nearest
        # test/ directory above it. nil when it passes or there is none.
        def test_reason(path)
          test = mapped_test(path)
          return unless test

          suite = File.dirname(File.dirname(test))
          out, status = Master::Io::Exec.capture2e(RbConfig.ruby, "-Ilib", "-Itest", test, chdir: suite, timeout: TEST_TIMEOUT_S)
          status&.success? ? nil : "#{File.basename(test)} failed: #{out.to_s.lines.last(3).join.strip}"
        rescue StandardError => e
          "#{File.basename(test.to_s)} could not run: #{e.class}: #{e.message[0, 120]}"
        end

        def mapped_test(path)
          stem = File.basename(path.to_s, ".*")
          dir = File.dirname(File.expand_path(path.to_s))
          loop do
            candidate = File.join(dir, "test", "test_#{stem}.rb")
            return candidate if File.file?(candidate)

            parent = File.dirname(dir)
            return if parent == dir

            dir = parent
          end
        end

        def note_capped(path)
          @mutex.synchronize { @capped << path.to_s unless @capped.include?(path.to_s) }
        end

        # Each written file's content is kept as its digest, so delivery can tell this run's bytes
        # from another writer's later save to the same path. before is what the file held ahead of
        # the run's first write to it, kept so a run that ends unproven can put it back.
        def note_written(path, before: nil)
          digest = content_digest(path)
          absolute = File.expand_path(path.to_s)
          @mutex.synchronize do
            @written << path.to_s unless @written.include?(path.to_s)
            @written_digests[absolute] = digest
            @originals[absolute] = before.b unless before.nil? || @originals.key?(absolute)
          end
        end

        # Puts back what each written file among paths held before the run wrote it, when the file
        # still holds exactly the run's bytes. A file changed since is another writer's and is left.
        # Answers [reverted, left], absolute paths.
        def revert_written!(paths)
          wanted = Array(paths).map { |path| File.expand_path(path.to_s) }
          ours = written.map { |path| File.expand_path(path) } & wanted
          reverted, left = ours.partition { |path| original(path) && still_as_written?(path) }

          reverted.each { |path| put_back(path) }
          [reverted, left]
        end

        def original(path) = @mutex.synchronize { @originals[File.expand_path(path.to_s)] }

        # The file still holds exactly what the autofix wrote.
        def still_as_written?(path)
          expected = @mutex.synchronize { @written_digests[File.expand_path(path.to_s)] }
          !expected.nil? && expected == content_digest(path)
        end

        def content_digest(path) = File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil

        def note_refused(path, reason)
          @mutex.synchronize { @refused << Record.new(path: path.to_s, reason:) }
        end

        # dry mode: the diff a write would have made, appended to one patch file.
        def record_patch(path, before, after, root:)
          patch = diff(before, after, label: path.to_s.delete_prefix("#{root}/"))
          return if patch.empty?

          file = patch_path(root)
          FileUtils.mkdir_p(File.dirname(file))
          File.write(file, patch, mode: "a")
          file
        end

        def patch_path(root)
          @patch ||= File.join(root.to_s, ".master", "autofix-#{Time.now.strftime("%Y%m%d-%H%M%S")}.patch")
        end

        def written = @mutex.synchronize { @written.dup }
        def refused = @mutex.synchronize { @refused.dup }
        def capped = @mutex.synchronize { @capped.dup }

        # The run's account, one line per fact, for the pass summary.
        def summary_lines
          lines = ["fix0: autofix mode=#{mode} wrote #{written.size} file(s), refused #{refused.size}, held back by the cap #{capped.size}"]
          refused.first(10).each { |row| lines << "fix0: autofix refused #{row.path}: #{row.reason}"[0, 220] }
          capped.first(10).each { |path| lines << "fix0: autofix held back (cap), #{path}" }
          lines
        end

        # Changed paths in the working tree that sit on the protected list.
        def protected_changes(root)
          out, status = Master::Io::Exec.capture2e("git", "-C", root.to_s, "diff", "--name-only", timeout: 30)
          return [] unless status&.success?

          top, = Master::Io::Exec.capture2e("git", "-C", root.to_s, "rev-parse", "--show-toplevel", timeout: 15)
          base = top.to_s.strip
          out.lines.map(&:strip).reject(&:empty?).select { |rel| protected_reason(File.join(base, rel), root:) }
        end

        private

        def put_back(path)
          File.binwrite(path, original(path))
          @mutex.synchronize do
            @written.reject! { |item| File.expand_path(item) == path }
            @written_digests.delete(path)
            @originals.delete(path)
          end
        end

        def pattern_name(pattern) = pattern.source[0, 40]

        def data_file?(path) = DATA_EXTENSIONS.include?(File.extname(path.to_s).downcase)

        def squeezed(text) = text.to_s.gsub(/\s+/, "")

        def parse_failure(path, content)
          case File.extname(path.to_s).downcase
          when ".rb"
            result = Prism.parse(content)
            result.failure? ? result.errors.first.message : nil
          when ".yml", ".yaml"
            YAML.parse(content)
            nil
          when ".json"
            JSON.parse(content)
            nil
          end
        rescue Psych::SyntaxError, JSON::ParserError => e
          e.message[0, 120]
        end

        def diff(before, after, label:)
          Dir.mktmpdir("autofix") do |dir|
            a = File.join(dir, "a")
            b = File.join(dir, "b")
            File.write(a, before)
            File.write(b, after)
            out, = Master::Io::Exec.capture2e("git", "diff", "--no-index", "--no-color", a, b, timeout: 30)
            out.gsub(a, "a/#{label}").gsub(b, "b/#{label}")
          end
        end
      end
    end
  end
end
