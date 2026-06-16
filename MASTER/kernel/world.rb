# frozen_string_literal: true

require "fileutils"
require "open3"
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
    def initialize(root:, ask: nil, git: method(:shell_git))
      @root = File.expand_path(root)
      @ask = ask
      @git = git
    end

    def verbs = Master::VERBS

    def perform(effect)
      send("do_#{effect.verb}", **effect.args)
    rescue StandardError => e
      Observation.no("#{e.class}: #{e.message}")
    end

    # One commit per admitted, successful turn: the working tree is the audit log.
    def commit(message) = @git.call(@root, "commit", message)

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

    def do_exec(command:, **)
      out, status = Open3.capture2e(command, chdir: @root)
      status.success? ? Observation.ok(out.strip) : Observation.no(out.strip)
    end

    def do_git(operation:, message: nil, **)
      Observation.ok(@git.call(@root, operation, message))
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

    def self.shell_git(root, operation, message = nil)
      args = operation == "commit" ? ["commit", "-am", message.to_s] : operation.split
      out, _ = Open3.capture2e("git", "-C", root, *args)
      out.strip
    end
  end
end
