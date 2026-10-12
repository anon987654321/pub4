# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# boot/entrypoint.rb activates the lockfile's pinned default gems (json, date)
# before `require "time"` loads date. On vm23 (Ruby 3.4) the default date is
# older than the lock's, and Bundler.setup died on "already activated date
# 3.4.1" until the pin ran first (2026-10-12, tts-worker --selftest).
class TestBootEntrypointPins < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ENTRYPOINT = File.join(ROOT, "lib", "boot", "entrypoint.rb")

  def locked(name)
    File.read(File.join(ROOT, "Gemfile.lock"), encoding: "UTF-8")[/^    #{name} \(([\d.]+)\)$/, 1]
  end

  def test_the_locked_default_gems_are_the_ones_active_after_the_entrypoint_loads
    %w[json date].each do |name|
      pin = locked(name)
      next unless pin && Gem::Specification.find_all_by_name(name, pin).any?

      out, status = Open3.capture2e(RbConfig.ruby, "-e", "require #{ENTRYPOINT.inspect}; print Gem.loaded_specs[#{name.inspect}]&.version")
      assert_predicate status, :success?, out
      assert_equal pin, out.strip, "#{name} must be on the locked version before Bundler.setup"
    end
  end
end
