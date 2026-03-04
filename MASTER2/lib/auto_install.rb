# frozen_string_literal: true

require "open3"

module AutoInstall
  INSTALL_CMD = %w[bundle install].freeze
  BUNDLE_CHECK_CMD = %w[bundle check].freeze
  DEFAULT_GEMFILE = "Gemfile"
  BUNDLE_NOT_FOUND_EXIT_STATUS = 127

  class << self
    def call(gemfile: DEFAULT_GEMFILE, io: $stderr)
      return false unless should_run?(gemfile)

      return true if bundle_ok?(gemfile)

      install!(gemfile, io)
      bundle_ok?(gemfile)
    end

    private

    def should_run?(gemfile)
      return false if ENV["AUTO_INSTALL"] == "0"
      return false unless File.file?(gemfile)

      true
    end

    def bundle_ok?(gemfile)
      cmd = BUNDLE_CHECK_CMD + ["--gemfile", gemfile]
      system(*cmd, out: File::NULL, err: File::NULL)
    rescue Errno::ENOENT
      false
    end

    def install!(gemfile, io)
      cmd = INSTALL_CMD + ["--gemfile", gemfile]
      status, stdout, stderr = run(cmd)

      io.puts(stdout) unless stdout.empty?
      io.puts(stderr) unless stderr.empty?

      raise "auto_install failed (exit #{status.exitstatus})" unless status.success?
    rescue Errno::ENOENT
      raise "auto_install failed: bundler not found (exit #{BUNDLE_NOT_FOUND_EXIT_STATUS})"
    end

    def run(cmd)
      stdout, stderr, status = Open3.capture3(*cmd)
      [status, stdout.to_s, stderr.to_s]
    end
  end
end