require 'timeout'

# Abort if the block runs longer than 5 seconds.
begin
  result = Timeout.timeout(5) { long_running_task }
rescue Timeout::Error => e
  # The block exceeded the limit.
  # Insert fallback, cleanup, or alerting logic here.
  warn "Task timed out: #{e.message}"
end
