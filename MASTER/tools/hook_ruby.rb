# frozen_string_literal: true

# Runs one of the Claude Code hooks in MASTER/tools under a modern Ruby: hook_ruby.rb <name> [args].
#
# A hook's `ruby` is whatever the hook process's PATH finds, and outside a login shell on this Mac that is
# /usr/bin/ruby 2.6. The hooks use Ruby 3 syntax, so under 2.6 they died parsing, a hook that dies does
# not block, and on 2026-10-23 a `tr` ran past the GNU-tools guard. This file stays 2.6-compatible: it
# finds a Ruby new enough and replaces itself with that, stdin and all. It runs before every tool call,
# so the running Ruby is used when it will do, and rbenv's are judged by their directory names.

MINIMUM = Gem::Version.new("3.3")
TOOLS = File.expand_path(__dir__)
FALLBACKS = ["/opt/homebrew/bin/ruby", "/usr/local/bin/ruby"].freeze

def version_of(ruby)
  Gem::Version.new(IO.popen([ruby, "-e", "print RUBY_VERSION"], err: File::NULL, &:read).to_s.strip)
rescue StandardError
  Gem::Version.new("0")
end

def rbenv_ruby
  paths = Dir.glob(File.join(ENV.fetch("HOME", ""), ".rbenv", "versions", "*", "bin", "ruby"))
  versions = paths.map do |path|
    name = File.basename(File.dirname(File.dirname(path)))
    [Gem::Version.new(name), path] if name.match?(/\A\d+(?:\.\d+)+\z/) && File.executable?(path)
  end
  newest = versions.compact.max
  newest[1] if newest && newest[0] >= MINIMUM
end

def modern_ruby
  return RbConfig.ruby if Gem::Version.new(RUBY_VERSION) >= MINIMUM

  rbenv_ruby || FALLBACKS.find { |path| File.executable?(path) && version_of(path) >= MINIMUM }
end

name = ARGV.shift.to_s
script = File.join(TOOLS, "#{name}.rb")
abort("hook_ruby: no hook named #{name.inspect}") unless name.match?(/\A[a-z_]+\z/) && File.file?(script)

ruby = modern_ruby
abort("hook_ruby: no Ruby >= #{MINIMUM} found for #{name}; the hook did not run") unless ruby

# The repo is UTF-8, and a hook process started without a locale reads it as US-ASCII and raises
# "invalid byte sequence" on laws.yml. A locale the caller set is kept; only its absence is filled.
locale = ENV.fetch("LC_ALL", ENV.fetch("LANG", "")).to_s.match?(/UTF-?8/i) ? {} : { "LC_ALL" => "C.UTF-8" }
exec(locale, ruby, script, *ARGV)
