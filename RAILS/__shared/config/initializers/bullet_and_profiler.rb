# frozen_string_literal: true

# Enable Bullet and Rack::MiniProfiler in development/test to catch N+1s.
#
# Both gems are declared `require: false`, so Bundler.require never loads them
# and `defined?(Bullet)` was nil in every environment — the guard was always
# false and neither tool could switch on. Requiring them here is what makes the
# rest of this file reachable; `require: false` stays, so production never loads
# either gem at all.
#
# rescue LoadError rather than assuming: these are development-group gems, and a
# production boot that has not installed them must not die on this file.
if Rails.env.development? || Rails.env.test?
  begin
    require "bullet"
  rescue LoadError
    nil
  end
  begin
    require "rack-mini-profiler"
  rescue LoadError
    nil
  end
end

if defined?(Bullet) && (Rails.env.development? || Rails.env.test?)
  Bullet.enable = true
  Bullet.bullet_logger = true
  Bullet.rails_logger = true
Bullet.add_footer = false
# Raising in test is what makes this a gate rather than a log nobody reads.
# strict_loading_by_default is development-only and set to :log, so before
# this line neither N+1 guard could fail anything in any environment.
Bullet.raise = true if Rails.env.test?
end

if defined?(Rack::MiniProfiler) && Rails.env.development?
  # Auto-inject the profiler in dev for quick page profiling.
  Rack::MiniProfiler.config.auto_inject = true
end
