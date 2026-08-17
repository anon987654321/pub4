# frozen_string_literal: true

# Enable Bullet and Rack::MiniProfiler in development/test to catch N+1s
if defined?(Bullet) && (Rails.env.development? || Rails.env.test?)
  Bullet.enable = true
  Bullet.bullet_logger = true
  Bullet.rails_logger = true
  Bullet.add_footer = false
end

if defined?(Rack::MiniProfiler) && Rails.env.development?
  # Auto-inject the profiler in dev for quick page profiling.
  Rack::MiniProfiler.config.auto_inject = true
end
