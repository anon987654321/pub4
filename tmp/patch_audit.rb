root = File.expand_path("~/pub4/MASTER")

# 1. Fix ask_once: return "" on error instead of error message string
agent_path = "#{root}/lib/master/agent.rb"
src = File.read(agent_path, encoding: "UTF-8")
src.sub!(
  "      send_with_cache(model || self.model, [{ role: \"user\", content: prompt.to_s }], system: system, stream: false).to_s",
  "      result = send_with_cache(model || self.model, [{ role: \"user\", content: prompt.to_s }], system: system, stream: false)\n" \
  "      result.respond_to?(:ok?) && result.ok? ? result.to_s : \"\""
)
File.write(agent_path, src)
puts "agent.rb: ask_once fixed"

# 2. Fix skills.rb: correct doc comment
skills_path = "#{root}/lib/master/skills.rb"
src = File.read(skills_path, encoding: "UTF-8")
src.sub!(
  "  # Skills discovered at boot are registered as tools in the agent.",
  "  # Skills discovered at boot are available via /skills; tool registration is pending."
)
File.write(skills_path, src)
puts "skills.rb: doc comment fixed"

# 3. Fix decision_engine.rb: correct doc comment
de_path = "#{root}/lib/master/decision_engine.rb"
if File.exist?(de_path)
  src = File.read(de_path, encoding: "UTF-8")
  src.sub!(
    /# DecisionEngine.*universal priority scorer.*\n(.*\n)*?module DecisionEngine/m
  ) { |m|
    "# DecisionEngine — universal priority scorer. Used by ModelRouter for tier selection.\n  module DecisionEngine"
  }
  File.write(de_path, src)
  puts "decision_engine.rb: doc fixed"
end

# 4. Delete convergence_loop.rb
cl_path = "#{root}/lib/master/convergence_loop.rb"
if File.exist?(cl_path)
  File.delete(cl_path)
  puts "convergence_loop.rb: deleted"
end

puts "done"
