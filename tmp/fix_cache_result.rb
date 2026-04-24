# encoding: utf-8
# frozen_string_literal: true
BASE = "/home/dev/pub4/MASTER"

# Fix 1: SemanticCache — unwrap Results before storing, re-wrap after reading
cache_path = File.join(BASE, "lib/master/semantic_cache.rb")
content = File.read(cache_path, encoding: "utf-8")

# Update write_entry to unwrap Result
content.sub!(
  '    def write_entry(path, value, key)',
  "    def write_entry(path, value, key)\n      # Unwrap Result objects for JSON serialization\n      value = value.value! if value.respond_to?(:ok?) && value.ok?"
)

# Update read_entry to return plain string (agent re-wraps it)
# No change needed — it already returns entry[:value] which will now be a string

File.write(cache_path, content)
puts "semantic_cache.rb: unwraps Results before JSON storage"

# Fix 2: agent.rb — handle cache returning plain strings
# The agent's _send_llm_request_with_cache_and_breaker uses cache.fetch
# The block returns Result.ok(text), but cache now stores text directly
# So cache hits return a string, not a Result
# We need to re-wrap cache hits as Results
agent_path = File.join(BASE, "lib/master/agent.rb")
content = File.read(agent_path, encoding: "utf-8")

old_cache_method = <<~'OLD'
    def _send_llm_request_with_cache_and_breaker(selected_model, messages, system: nil, stream: false, &blk)
      cache_key = cache_key_for(messages.last[:content], messages[0...-1])
      breaker_for(selected_model).call(estimate_cost(messages.last[:content])) {
        @cache.fetch(cache_key, selected_model) {
          _send_llm_request(selected_model, messages, system: system, stream: stream, &blk)
        }
      }
    rescue StandardError => err
      Result.err("llm_request: #{err.message}", category: :llm_call_failure)
    end
OLD

new_cache_method = <<~'NEW'
    def _send_llm_request_with_cache_and_breaker(selected_model, messages, system: nil, stream: false, &blk)
      cache_key = cache_key_for(messages.last[:content], messages[0...-1])
      breaker_for(selected_model).call(estimate_cost(messages.last[:content])) {
        cached = @cache.fetch(cache_key, selected_model) {
          _send_llm_request(selected_model, messages, system: system, stream: stream, &blk)
        }
        # Cache stores plain strings; re-wrap as Result if needed
        cached.respond_to?(:ok?) ? cached : Result.ok(cached.to_s)
      }
    rescue StandardError => err
      Result.err("llm_request: #{err.message}", category: :llm_call_failure)
    end
NEW

if content.include?("def _send_llm_request_with_cache_and_breaker")
  content.sub!(old_cache_method.strip, new_cache_method.strip)
  File.write(agent_path, content)
  puts "agent.rb: re-wraps cache hits as Results"
else
  puts "agent.rb: method not found"
end

puts "done"
