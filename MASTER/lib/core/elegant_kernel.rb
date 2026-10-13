# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tempfile"
require "yaml"

module Master
  module Core
    # One execution spine for Law, Observation and Repair. Existing scanners,
    # staged repairs and release gates remain adapters until behavioral parity is
    # demonstrated; this kernel does not bypass them or delete them.
    module ElegantKernel
      ZERO_HASH = "0" * 64
      TREE_NAMES = %w[MASTER RAILS OPENBSD STUDIO].freeze
      MAX_FILES = 10_000
      MAX_FILE_BYTES = 2 * 1024 * 1024
      MAX_TREE_BYTES = 40 * 1024 * 1024
      EXCLUDED_PARTS = %w[.git .master vendor tmp node_modules].freeze

      Error = Class.new(StandardError)
      BoundaryError = Class.new(Error)
      ObservationLimitError = Class.new(Error)
      IntegrityError = Class.new(Error)

      Law = Data.define(:name, :sacred, :auto, :check, :repair) do
        def initialize(name:, sacred: false, auto: false, check:, repair: nil)
          raise ArgumentError, "law name must not be empty" if name.to_s.strip.empty?
          raise ArgumentError, "law check must be callable" unless check.respond_to?(:call)
          raise ArgumentError, "automatic law needs a repair callable" if auto && !sacred && !repair.respond_to?(:call)
          super(name: name.to_s.freeze, sacred: !!sacred, auto: !!auto, check:, repair:)
        end
      end

      Observation = Data.define(:command, :output, :hash, :path, :root, :files, :excluded) do
        def file(name)
          text = name.to_s
          absolute = File.expand_path(text, root)
          candidates = [
            text,
            absolute.delete_prefix("#{root}#{File::SEPARATOR}"),
            File.join(path, text).sub(%r{\A\./}, "")
          ].uniq
          key = candidates.find { |candidate| files.key?(candidate) }
          key ? files.fetch(key) : nil
        end

        def content_hash(name = path)
          text = file(name)
          text && Digest::SHA256.hexdigest(text)
        end

        def deleted = []
      end

      Repair = Data.define(:path, :before_hash, :after_hash, :diff, :content) do
        def to_h
          { "path" => path, "before_hash" => before_hash, "after_hash" => after_hash, "diff" => diff }
        end
      end

      Result = Data.define(:state, :iterations, :law, :message, :observation, :repair) do
        def converged? = state == :converged
        def escalated? = state == :escalated
        def failed? = state == :failed
      end

      # Every cross-tree read or write consults the target tree's .pub4 first.
      class Boundary
        PERMISSIONS = %w[none read write read_write].freeze

        def initialize(root:, actor: "master")
          @root = File.expand_path(root)
          @actor = actor.to_s.downcase
          raise ArgumentError, "actor must not be empty" if @actor.empty?
        end

        def authorize!(path, access:)
          absolute = safe_absolute(path)
          manifest_path, tree_root = manifest_for(absolute)
          manifest = read_manifest(manifest_path)
          permission = manifest.fetch("allows", {}).fetch(@actor, "none").to_s
          allowed = case access.to_sym
                    when :read then %w[read write read_write].include?(permission)
                    when :write then %w[write read_write].include?(permission)
                    else raise ArgumentError, "unknown access: #{access}"
                    end
          raise BoundaryError, "#{@actor} #{access} denied by #{relative_path(manifest_path)}" unless allowed

          reject_symlink_path!(absolute, tree_root)
          absolute
        end

        def validate!
          paths = if File.file?(File.join(@root, ".pub4"))
                    [File.join(@root, ".pub4")]
                  else
                    TREE_NAMES.map { |tree| File.join(@root, tree, ".pub4") }
                  end
          paths.each do |path|
            data = read_manifest(path)
            Array(data["adapters"]).each do |adapter|
              adapter_path = File.expand_path(adapter.to_s, @root)
              unless inside?(@root, adapter_path) && File.file?(adapter_path)
                raise BoundaryError, "missing boundary adapter #{adapter}"
              end
            end
          end
          true
        end

        private

        def safe_absolute(path)
          absolute = File.expand_path(path.to_s, @root)
          raise BoundaryError, "path outside workspace" unless inside?(@root, absolute)
          absolute
        rescue ArgumentError, TypeError => e
          raise BoundaryError, "invalid target path: #{e.message}"
        end

        def manifest_for(absolute)
          root_manifest = File.join(@root, ".pub4")
          return [root_manifest, @root] if File.file?(root_manifest)

          relative = relative_path(absolute)
          tree = relative.split(File::SEPARATOR).first
          raise BoundaryError, "path has no declared tree boundary" unless TREE_NAMES.include?(tree)

          tree_root = File.join(@root, tree)
          manifest_path = File.join(tree_root, ".pub4")
          raise BoundaryError, "missing #{relative_path(manifest_path)}" unless File.file?(manifest_path)
          [manifest_path, tree_root]
        end

        def read_manifest(path)
          raise BoundaryError, "missing boundary manifest #{relative_path(path)}" unless File.file?(path)
          raise BoundaryError, "symlink boundary manifest #{relative_path(path)}" if File.symlink?(path)

          data = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
          raise BoundaryError, "boundary manifest must be a mapping" unless data.is_a?(Hash)
          raise BoundaryError, "unsupported boundary schema in #{relative_path(path)}" unless data["schema"] == 1
          raise BoundaryError, "boundary tree is missing in #{relative_path(path)}" if data["tree"].to_s.empty?
          unless data["allows"].is_a?(Hash) && data["allows"].values.all? { |value| PERMISSIONS.include?(value.to_s) }
            raise BoundaryError, "invalid permissions in #{relative_path(path)}"
          end
          data
        rescue Psych::Exception => e
          raise BoundaryError, "invalid #{relative_path(path)}: #{e.message}"
        end

        def reject_symlink_path!(absolute, tree_root)
          cursor = absolute
          while inside?(tree_root, cursor)
            raise BoundaryError, "symlink path refused: #{relative_path(cursor)}" if File.symlink?(cursor)
            break if cursor == tree_root
            cursor = File.dirname(cursor)
          end
        end

        def inside?(parent, path)
          path == parent || path.start_with?("#{parent}#{File::SEPARATOR}")
        end

        def relative_path(path)
          path.to_s.delete_prefix("#{@root}#{File::SEPARATOR}").delete_prefix(@root)
        end
      end

      # Append-only JSONL. Each row commits to its sequence, predecessor and payload.
      class AuditLog
        attr_reader :path

        def initialize(root:, path: nil)
          @root = File.expand_path(root)
          @path = File.expand_path(path || File.join(@root, ".master", "log.jsonl"))
        end

        def append(event:, data: {})
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, File::RDWR | File::CREAT, 0o600) do |io|
            io.flock(File::LOCK_EX)
            begin
              io.rewind
              rows = decode_and_verify(io.read)
              previous = rows.last
              body = {
                "seq" => previous ? previous.fetch("seq") + 1 : 1,
                "prev_hash" => previous ? previous.fetch("hash") : ZERO_HASH,
                "event" => event.to_s,
                "data" => normalize(data)
              }
              record = body.merge("hash" => Digest::SHA256.hexdigest(JSON.generate(body)))
              io.seek(0, IO::SEEK_END)
              io.write(JSON.generate(record) << "\n")
              io.flush
              io.fsync
              record
            ensure
              io.flock(File::LOCK_UN) rescue nil
            end
          end
        end

        def records
          return [] unless File.file?(path)
          decode_and_verify(File.binread(path))
        end

        def replay(sequence = nil)
          rows = records
          return rows if sequence.nil?
          number = Integer(sequence)
          raise ArgumentError, "sequence must be positive" unless number.positive?
          row = rows.find { |entry| entry.fetch("seq") == number }
          raise ArgumentError, "sequence #{number} does not exist" unless row
          [row]
        end

        private

        def decode_and_verify(raw)
          return [] if raw.empty?
          rows = raw.lines.map do |line|
            raise IntegrityError, "audit log has an incomplete final row" unless line.end_with?("\n")
            JSON.parse(line)
          rescue JSON::ParserError => e
            raise IntegrityError, "audit log contains invalid JSON: #{e.message}"
          end
          previous = ZERO_HASH
          rows.each_with_index do |row, index|
            expected_sequence = index + 1
            unless row["seq"] == expected_sequence && row["prev_hash"] == previous
              raise IntegrityError, "audit chain sequence or predecessor mismatch at #{expected_sequence}"
            end
            body = row.reject { |key, _| key == "hash" }
            expected_hash = Digest::SHA256.hexdigest(JSON.generate(body))
            raise IntegrityError, "audit chain hash mismatch at #{expected_sequence}" unless row["hash"] == expected_hash
            previous = row.fetch("hash")
          end
          rows
        end

        def normalize(value)
          case value
          when Hash then value.transform_keys(&:to_s).transform_values { |entry| normalize(entry) }
          when Array then value.map { |entry| normalize(entry) }
          when Symbol then value.to_s
          when String, Numeric, true, false, NilClass then value
          else value.respond_to?(:to_h) ? normalize(value.to_h) : value.to_s
          end
        end
      end

      class Kernel
        attr_reader :root, :log

        def initialize(root:, laws:, actor: "master", log_path: nil, max_iterations: 20)
          @root = File.expand_path(root)
          @laws = Array(laws).freeze
          raise ArgumentError, "every law must be an ElegantKernel::Law" unless @laws.all? { |law| law.is_a?(Law) }
          @boundary = Boundary.new(root:, actor:)
          @log = AuditLog.new(root:, path: log_path)
          @max_iterations = Integer(max_iterations)
          raise ArgumentError, "max_iterations must be positive" unless @max_iterations.positive?
        end

        def validate_boundaries! = @boundary.validate!

        def observe(path)
          absolute = @boundary.authorize!(path, access: :read)
          relative = relative_path(absolute)
          contents = {}
          excluded = []
          bytes = 0

          if File.file?(absolute)
            excluded << { "path" => relative, "reason" => "binary" } unless read_observed_file(absolute, relative, contents)
          elsif File.directory?(absolute)
            Dir.glob(File.join(absolute, "**", "*"), File::FNM_DOTMATCH).sort.each do |candidate|
              next if candidate == absolute
              rel = relative_path(candidate)
              parts = rel.split(File::SEPARATOR)
              if parts.any? { |part| EXCLUDED_PARTS.include?(part) }
                excluded << { "path" => rel, "reason" => "excluded_directory" } if File.directory?(candidate)
                next
              end
              next if %w[. ..].include?(File.basename(candidate))
              if File.symlink?(candidate)
                excluded << { "path" => rel, "reason" => "symlink" }
                next
              end
              next unless File.file?(candidate)
              size = File.size(candidate)
              raise ObservationLimitError, "file exceeds observation limit: #{rel}" if size > MAX_FILE_BYTES
              bytes += size
              raise ObservationLimitError, "tree exceeds observation byte limit" if bytes > MAX_TREE_BYTES
              excluded << { "path" => rel, "reason" => "binary" } unless read_observed_file(candidate, rel, contents)
              raise ObservationLimitError, "too many observed files" if contents.size > MAX_FILES
            end
          else
            raise Error, "observation target does not exist: #{relative}"
          end

          output = JSON.generate({
            "path" => relative,
            "files" => contents.map { |key, value| { "path" => key, "sha256" => Digest::SHA256.hexdigest(value), "bytes" => value.bytesize } },
            "excluded" => excluded
          })
          observation = Observation.new(
            command: "snapshot #{relative}", output:, hash: Digest::SHA256.hexdigest(output),
            path: relative, root:, files: contents.freeze, excluded: excluded.freeze
          )
          log.append(event: "observation", data: { command: observation.command, output: observation.output, hash: observation.hash, path: relative })
          observation
        end

        def repair(observation, path, content)
          raise ArgumentError, "content must be a string" unless content.is_a?(String)
          raise ObservationLimitError, "repair exceeds file limit" if content.bytesize > MAX_FILE_BYTES
          absolute = @boundary.authorize!(path, access: :write)
          raise Error, "repair target must be an existing regular file" unless File.file?(absolute) && !File.symlink?(absolute)
          relative = relative_path(absolute)
          before = observation.files[relative]
          raise IntegrityError, "repair source was not present in observation #{observation.hash}" unless before
          current = File.binread(absolute)
          raise IntegrityError, "target changed since observation: #{relative}" unless Digest::SHA256.hexdigest(current) == Digest::SHA256.hexdigest(before)

          Repair.new(
            path: relative,
            before_hash: Digest::SHA256.hexdigest(before),
            after_hash: Digest::SHA256.hexdigest(content),
            diff: unified_diff(relative, before, content),
            content: content.dup
          )
        end

        def apply(repair)
          raise ArgumentError, "invalid repair tuple" unless repair.is_a?(Repair)
          absolute = @boundary.authorize!(repair.path, access: :write)
          current = File.binread(absolute)
          raise IntegrityError, "repair before hash mismatch: #{repair.path}" unless Digest::SHA256.hexdigest(current) == repair.before_hash
          raise IntegrityError, "repair after hash does not match its content" unless Digest::SHA256.hexdigest(repair.content) == repair.after_hash
          raise IntegrityError, "repair diff does not match its content" unless unified_diff(repair.path, current, repair.content) == repair.diff
          raise IntegrityError, "repair has no change: #{repair.path}" if repair.before_hash == repair.after_hash

          log.append(event: "repair", data: repair.to_h)
          mode = File.stat(absolute).mode & 0o777
          Tempfile.create([".pub4-repair-", ".tmp"], File.dirname(absolute)) do |temp|
            temp.binmode
            temp.chmod(mode)
            temp.write(repair.content)
            temp.flush
            temp.fsync
            temp.close
            File.rename(temp.path, absolute)
          end
          log.append(event: "apply", data: { path: repair.path, before_hash: repair.before_hash, after_hash: repair.after_hash })
          repair.after_hash
        end

        def verify(path, repair)
          observation = observe(path)
          current = observation.content_hash(repair.path)
          ok = current == repair.after_hash
          log.append(event: "verify", data: { path: repair.path, observed_hash: current, expected_hash: repair.after_hash, ok: ok })
          ok
        end

        # A law predicate returns true when it detects a violation. Sacred and
        # non-automatic laws escalate before any repair can be applied.
        def fix(path)
          iterations = 0
          loop do
            observation = observe(path)
            law = @laws.find { |candidate| candidate.check.call(observation) }
            unless law
              log.append(event: "terminal", data: { state: "converged", iterations:, path: relative_path(File.expand_path(path, root)) })
              return Result.new(state: :converged, iterations:, law: nil, message: "no law fires", observation:, repair: nil)
            end

            log.append(event: "law", data: { name: law.name, sacred: law.sacred, auto: law.auto, observation_hash: observation.hash })
            if law.sacred || !law.auto
              log.append(event: "escalation", data: { law: law.name, path: observation.path, reason: "human authority required" })
              return Result.new(state: :escalated, iterations:, law: law.name, message: "law requires human decision", observation:, repair: nil)
            end
            if iterations >= @max_iterations
              log.append(event: "terminal", data: { state: "failed", iterations:, reason: "iteration limit reached", path: observation.path })
              return Result.new(state: :failed, iterations:, law: law.name, message: "iteration limit reached", observation:, repair: nil)
            end

            repair = law.repair.call(observation)
            unless repair.is_a?(Repair)
              log.append(event: "terminal", data: { state: "failed", law: law.name, reason: "repair did not return a Repair tuple" })
              return Result.new(state: :failed, iterations:, law: law.name, message: "repair did not return a Repair tuple", observation:, repair: nil)
            end

            begin
              apply(repair)
              verified = verify(path, repair)
              unless verified
                log.append(event: "terminal", data: { state: "failed", law: law.name, reason: "repair verification failed" })
                return Result.new(state: :failed, iterations:, law: law.name, message: "repair verification failed", observation:, repair:)
              end
            rescue StandardError => e
              log.append(event: "terminal", data: { state: "failed", law: law.name, error: "#{e.class}: #{e.message}" })
              return Result.new(state: :failed, iterations:, law: law.name, message: e.message, observation:, repair:)
            end
            iterations += 1
          end
        rescue StandardError => e
          begin
            log.append(event: "terminal", data: { state: "failed", iterations: iterations || 0, error: "#{e.class}: #{e.message}" })
          rescue StandardError
            # Preserve the original error when the log itself cannot be extended.
          end
          Result.new(state: :failed, iterations: iterations || 0, law: nil, message: "#{e.class}: #{e.message}", observation: nil, repair: nil)
        end

        private

        def read_observed_file(absolute, relative, contents)
          size = File.size(absolute)
          raise ObservationLimitError, "file exceeds observation limit: #{relative}" if size > MAX_FILE_BYTES
          data = File.binread(absolute)
          return false if data.include?("\0")
          data.force_encoding(Encoding::UTF_8)
          raise Error, "invalid UTF-8 in observed file: #{relative}" unless data.valid_encoding?
          contents[relative] = data
          true
        end

        def relative_path(path)
          absolute = File.expand_path(path, root)
          raise BoundaryError, "path outside workspace" unless absolute == root || absolute.start_with?("#{root}#{File::SEPARATOR}")
          absolute.delete_prefix("#{root}#{File::SEPARATOR}").delete_prefix(root).sub(%r{\A/}, "")
        end

        def unified_diff(path, before, after)
          old_lines = before.lines
          new_lines = after.lines
          old_rows = old_lines.map { |line| "-#{line.end_with?("\n") ? line : "#{line}\n"}" }
          new_rows = new_lines.map { |line| "+#{line.end_with?("\n") ? line : "#{line}\n"}" }
          ["--- a/#{path}\n", "+++ b/#{path}\n", "@@ -1,#{old_lines.length} +1,#{new_lines.length} @@\n", *old_rows, *new_rows].join
        end
      end
    end
  end
end
