# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"
require "timeout"
require "time"

module Master
  # World — the only thing that touches the outside. Each verb is one handler;
  # the set is closed (Master::VERBS), so the blast radius of the agent is the
  # surface of this file and nothing else. The Constitution has already admitted
  # whatever arrives here, so handlers do the IO plainly — their only added duty
  # is reversibility (back up before overwriting) and honest reporting.
  #
  # This is where the old reach/ (git, web, fs), ops/, and tools/ collapse to.
  class World
    def initialize(root:, ask: nil)
      @root = File.expand_path(root)
      @ask = ask
    end

    def verbs = Master::VERBS

    def perform(effect)
      send("do_#{effect.verb}", **effect.args)
    rescue StandardError => e
      Observation.no("#{e.class}: #{e.message}")
    end

    def checkpoint
      {
        id: SecureRandom.hex(8),
        patch: git_capture("diff", "--binary"),
        staged: git_capture("diff", "--cached", "--binary")
      }
    end

    def rollback(checkpoint)
      git_capture("reset", "--hard")
      git_capture("clean", "-fd")
      apply_patch(checkpoint[:patch]) unless checkpoint[:patch].to_s.empty?
      Observation.ok("rolled back #{checkpoint[:id]}")
    rescue StandardError => e
      Observation.no("rollback failed: #{e.class}: #{e.message}")
    end

    private

    def do_read(path:, **)
      Observation.ok(File.read(within(path), encoding: "UTF-8").scrub)
    end

    def do_write(path:, content:, **)
      abs = within(path)
      backup(abs)
      FileUtils.mkdir_p(File.dirname(abs))
      File.write(abs, content)
      Observation.ok("wrote #{path} (#{content.bytesize}b)")
    end

    def do_exec(argv:, timeout: 60, env: {}, **)
      raise ArgumentError, "argv must be an array" unless argv.is_a?(Array)
      raise ArgumentError, "argv cannot be empty" if argv.empty?
      raise ArgumentError, "argv entries must be strings" unless argv.all? { |arg| arg.is_a?(String) }

      out = nil
      status = nil
      Timeout.timeout(Integer(timeout)) do
        out, status = Open3.capture2e(env.transform_keys(&:to_s), *argv, chdir: @root)
      end
      status.success? ? Observation.ok(out.strip) : Observation.no(out.strip)
    end

    def do_git(operation:, paths: [], message: nil, **)
      case operation.to_sym
      when :diff then Observation.ok(git_capture("diff"))
      when :stage then Observation.ok(git_capture("add", "--", *Array(paths)))
      when :commit then Observation.ok(git_capture("commit", "-m", message.to_s))
      else Observation.no("unknown git operation: #{operation}")
      end
    end

    def do_ask(prompt:, options: nil, **)
      return Observation.no("no surface to ask") unless @ask

      Observation.ok(@ask.call(prompt:, options:))
    end

    def do_note(**) = Observation.ok # the Memory keeps the note; nothing to do here

    # Paths are sandboxed to root; nothing escapes the workspace.
    def within(path)
      abs = File.expand_path(path, @root)
      raise "path escapes workspace: #{path}" unless abs == @root || abs.start_with?(@root + File::SEPARATOR)

      abs
    end

    def backup(abs)
      return unless File.exist?(abs)

      FileUtils.cp(abs, "#{abs}.#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}.bak")
    end

    def git_capture(*args)
      out, status = Open3.capture2e("git", "-C", @root, *args)
      raise out.strip unless status.success?

      out.strip
    end

    def apply_patch(patch)
      out, status = Open3.capture2e("git", "-C", @root, "apply", "--binary", "-", stdin_data: patch)
      raise out.strip unless status.success?
    end

    def self.shell_git(root, operation, message = nil)
      args = operation == "commit" ? ["commit", "-m", message.to_s] : operation.split
      out, _ = Open3.capture2e("git", "-C", root, *args)
      out.strip
    end
  end
end