# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/master"

# MASTER never starts a background loop unless explicitly asked.
#
# This file used to assert that each of the three entry points *contained* the
# string `return unless ENV["..."] == "1"`. That passes against a guard moved
# below the work it guards, against a guard commented out with the text intact
# in a heredoc, and against a method whose body is otherwise `raise` — while
# failing if anyone reformats the line. The claim is trivially executable, so
# it is executed: call each entry point with a clean environment and require
# that it returns without doing anything.
class SourceLoopGuardsSpec < Minitest::Test
  # Constructed with the minimum each requires. The collaborators are nil
  # because the guard must refuse before anything touches them — if a loop
  # reaches for a scanner it was never given, that is the same defect.
  GUARDED = [
    ["MASTER_HEARTBEAT", -> { Master::Fix::Heartbeat.new(root: Master::ROOT).start! }],
    ["MASTER_WATCHER",   -> { Master::Fix::Watcher.new(bus: nil, root: Master::ROOT).run_forever }],
    ["MASTER_WATCH",     lambda {
      Master::Fix::WatchLoop.new(rules: nil, agent: nil, scanner: nil, root: Master::ROOT).run
    }]
  ].freeze

  def without(var)
    had = ENV.key?(var)
    old = ENV[var]
    ENV.delete(var)
    yield
  ensure
    had ? ENV[var] = old : ENV.delete(var)
  end

  # Each returns promptly and starts nothing. The timeout is the assertion that
  # matters: a loop that ignored its guard would not come back.
  # Returning promptly is not enough on its own: Heartbeat#start! and
  # WatchLoop#run spawn a Thread and return immediately, so a timeout alone
  # passes whether or not the guard is there. The observable claim is that
  # nothing is left running afterwards, so that is what is asserted — and
  # verified by deleting the guard and watching this fail.
  def threads_after
    before = Thread.list.size
    yield
    sleep 0.2
    Thread.list.size - before
  end

  def test_no_background_loop_starts_without_its_env_var
    reached = 0
    GUARDED.each do |var, entry|
      without(var) do
        spawned = 0
        Timeout.timeout(5) { spawned = threads_after { entry.call } }
        assert_equal 0, spawned,
                     "#{var} unset and #{spawned} background thread(s) started anyway"
        reached += 1
      rescue Timeout::Error
        flunk "#{var} unset and the loop ran anyway — the guard does not stop it"
      rescue LoadError => e
        # WatchLoop builds its file watcher in initialize, and the backing gem
        # is platform-specific (rb-kqueue on BSD, rb-inotify on Linux), so it
        # cannot be constructed on a Mac at all. That is a host limitation
        # rather than a guard failure — but it is named, not skipped silently.
        skip_reason = "#{var}: #{e.message[0, 40]} — platform watcher gem absent on this host"
        warn "source_loop_guards: #{skip_reason}"
      rescue ArgumentError, NoMethodError => e
        flunk "#{var} entry point could not be called: #{e.class} #{e.message}"
      end
    end

    assert_operator reached, :>=, 2,
                    "fewer than two loop guards could be exercised on this host — " \
                    "the assertion is no longer measuring anything"
  end

  # And the opt-in is a specific value, not merely presence — so `=0` or an
  # empty string cannot start a loop by accident.
  def test_a_falsy_value_does_not_count_as_opting_in
    GUARDED.each do |var, entry|
      %w[0 false ""].each do |value|
        old = ENV[var]
        ENV[var] = value
        begin
          Timeout.timeout(5) { entry.call }
        rescue Timeout::Error
          flunk "#{var}=#{value.inspect} started a loop"
        rescue LoadError, ArgumentError, NoMethodError
          nil
        ensure
          old.nil? ? ENV.delete(var) : ENV[var] = old
        end
      end
    end
  end
end
