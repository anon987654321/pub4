# frozen_string_literal: true

# Loaded into every Ruby process of a snapshot render through RUBYOPT, and by
# nothing else. It records each external command the process starts -- system,
# spawn, backticks, IO.popen, Process.spawn, and Open3 through Process.spawn --
# as one JSON line: the process, its sequence number, and the command with
# everything that varies between two runs of the same code replaced by a token.
# See snap.rb for the procedure this serves.
require "json"
require "digest"
require "tmpdir"

module DillaSnapshot
  LOG = ENV.fetch("DILLA_SNAP_LOG")

  # The render's own directories and the checkout it runs from differ between a
  # baseline and the changed code, so each becomes a token. Both spellings of
  # each, because macOS reaches /tmp through /private/tmp and a path can arrive
  # either way.
  def self.spellings(path)
    return [] if path.to_s.empty?

    [File.expand_path(path), (File.realpath(path) if File.exist?(path))].compact.uniq
  end

  PLACES = {
    "<DIR>" => [ENV["DILLA_OUTPUT_DIR"], ENV["DILLA_SCRATCH_DIR"]].flat_map { |dir| spellings(dir) },
    "<REPO>" => spellings(ENV["DILLA_SNAP_REPO"]),
  }.freeze

  # A temp file carries a random name, so the whole path is the token, not only
  # its directory.
  TEMP_FILE = %r{/(?:private/)?(?:var/folders|tmp)/[^\s'",]+}

  PROCESS = Digest::SHA256.hexdigest(([$PROGRAM_NAME] + ARGV).join(" "))[0, 10]
  @sequence = 0

  # Longest path first, so a render directory inside the checkout is replaced
  # whole rather than as <REPO> followed by its tail. A pid and a run of digits
  # between separators are a process id and a scratch counter, and both change
  # every run.
  def self.normalise(text)
    line = text.to_s.dup
    PLACES.flat_map { |token, paths| paths.map { |path| [path, token] } }
          .sort_by { |path, _| -path.length }
          .each { |path, token| line = line.gsub(path, token) }
    line = line.gsub(TEMP_FILE, "<TMP>")
    line = line.gsub(/\b#{Process.pid}\b/, "<PID>")
    line.gsub(/(?<=[._-])\d{4,7}(?=[._-])/, "<N>")
  end

  def self.record(args)
    argv = args.flatten.reject { |arg| arg.is_a?(Hash) }.map(&:to_s)
    return if argv.empty?

    @sequence += 1
    File.open(LOG, "a") { |log| log.puts(JSON.generate([PROCESS, @sequence, "exec", normalise(argv.join(" "))])) }
  rescue StandardError => e
    warn "dilla snapshot hook: #{e.class}: #{e.message}"
  end
end

module Kernel
  alias_method :__snapshot_system, :system
  alias_method :__snapshot_spawn, :spawn
  alias_method :__snapshot_backtick, :`

  def system(*args, **opts)
    DillaSnapshot.record(args)
    __snapshot_system(*args, **opts)
  end

  def spawn(*args, **opts)
    DillaSnapshot.record(args)
    __snapshot_spawn(*args, **opts)
  end

  def `(command)
    DillaSnapshot.record([command])
    __snapshot_backtick(command)
  end

  module_function :system, :spawn, :`
end

class << IO
  alias_method :__snapshot_popen, :popen

  # The command only: a mode string ("rb", "wb") says how Ruby reads the pipe,
  # not what the tool is asked to do, and a call moved to Open3 drops it.
  def popen(*args, **opts, &block)
    DillaSnapshot.record(args.first.is_a?(Array) ? [args.first] : args)
    __snapshot_popen(*args, **opts, &block)
  end
end

module Process
  class << self
    alias_method :__snapshot_process_spawn, :spawn

    def spawn(*args, **opts)
      DillaSnapshot.record(args)
      __snapshot_process_spawn(*args, **opts)
    end
  end
end
