# encoding: utf-8
# frozen_string_literal: true
BASE = "/home/dev/pub4/MASTER"

# Fix 1: agent.rb — handle Ferrum Err in _send_llm_request
agent_path = File.join(BASE, "lib/master/agent.rb")
content = File.read(agent_path, encoding: "utf-8")
old_line = 'return Result.ok(response.respond_to?(:value!) ? response.value! : response.to_s)'
new_line = 'return response if response.respond_to?(:err?) && response.err?; return Result.ok(response.respond_to?(:ok?) && response.ok? ? response.value! : response.to_s)'
content.sub!(old_line, new_line)
File.write(agent_path, content)
puts "agent.rb: handle Ferrum Err properly"

# Fix 2: Remove ferrum from fallback models in models.yml
models_path = File.join(BASE, "data/models.yml")
content = File.read(models_path, encoding: "utf-8")
# Remove the ferrum_web_chat sections
content.gsub!(/^ferrum_web_chat:\n\s+free_latest:\n\s+- ferrum:webchat:[^\n]+\n/, "")
File.write(models_path, content)
puts "models.yml: removed ferrum from fallback chain"

puts "done"
