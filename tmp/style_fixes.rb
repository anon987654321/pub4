ROOT = "/home/dev/pub4/MASTER/lib/master"

def patch(rel)
  path = File.join(ROOT, rel)
  src = File.read(path, encoding: "UTF-8")
  out = yield(src)
  if out == src; puts "SKIP: #{rel}"
  else; File.write(path, out); puts "PATCHED: #{rel}"
  end
end

# 1. result.rb — add Result.wrap class method
patch("result.rb") do |s|
  next s if s.include?("def self.wrap")
  s.sub(
    "    def self.ok(value)                      = Ok.new(value)\n    def self.err(msg, category: :unknown)   = Err.new(msg, category)",
    "    def self.ok(value)                      = Ok.new(value)\n    def self.err(msg, category: :unknown)   = Err.new(msg, category)\n    def self.wrap(val)                      = val.respond_to?(:ok?) ? val : Ok.new(val)"
  )
end

# 2. flatten.map -> flat_map
["heartbeat.rb", "routing/model_router.rb", "stages/council.rb"].each do |rel|
  patch(rel) do |s|
    s.gsub(".flatten.map { |m| m[\"id\"] }.compact",
           ".flat_map { |m| [m[\"id\"]] }.compact")
     .gsub(".flatten.map { |str| Regexp.new(str, Regexp::IGNORECASE) }",
           ".flat_map { |str| [Regexp.new(str, Regexp::IGNORECASE)] }")
  end
end

# Better: use flat_map directly
patch("heartbeat.rb") do |s|
  s.gsub("tiers.values.flatten.map { |m| m[\"id\"] }.compact",
         "tiers.values.flat_map { |m| m[\"id\"] ? [m[\"id\"]] : [] }")
end
patch("routing/model_router.rb") do |s|
  s.gsub(".fetch(\"models\", {}).values.flatten.map { |m| m[\"id\"] }.compact",
         ".fetch(\"models\", {}).values.flat_map { |m| m[\"id\"] ? [m[\"id\"]] : [] }")
end
patch("stages/council.rb") do |s|
  s.gsub("(data[\"dangerous\"] || []).flatten.map { |str| Regexp.new(str, Regexp::IGNORECASE) }",
         "(data[\"dangerous\"] || []).flat_map { |str| [Regexp.new(str, Regexp::IGNORECASE)] }")
end

# 3. Remove redundant .freeze from String constants in tool files (NAME, DESCRIPTION)
# frozen_string_literal: true makes string literals already frozen
Dir["#{ROOT}/tools/*.rb"].each do |path|
  rel = path.sub(ROOT + "/", "")
  patch(rel) do |s|
    next s unless s.start_with?("# frozen_string_literal: true")
    s.gsub(/^      (NAME|DESCRIPTION|SCRIPT) = ("(?:[^"\\]|\\.)*")\.freeze/) { "      #{$1} = #{$2}" }
  end
end

# 4. compact before uniq (convergence_loop)
patch("convergence_loop.rb") do |s|
  s.gsub(".uniq.compact", ".compact.uniq")
end

# 5. command_registry files: extract args helper
# Check if already defined
cr_path = "#{ROOT}/command_registry.rb"
cr = File.read(cr_path, encoding: "UTF-8")
unless cr.include?("def args(ctx)")
  out = cr.sub(
    "  class CommandRegistry\n",
    "  class CommandRegistry\n    def self.args(ctx) = ctx[:args].to_s.strip\n\n"
  )
  if out != cr
    File.write(cr_path, out)
    puts "PATCHED: command_registry.rb (added args helper)"
  end
end

puts "Done."
