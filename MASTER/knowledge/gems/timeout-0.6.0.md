require 'timeout'

begin
  result = Timeout.timeout(5) { long_running_task }
rescue Timeout::Error
  # Handle timeout
end
