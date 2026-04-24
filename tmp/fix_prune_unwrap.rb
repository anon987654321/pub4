# encoding: utf-8
# frozen_string_literal: true
BASE = "/home/dev/pub4/MASTER"
content = File.read(File.join(BASE, "lib/master/stages/prune.rb"), encoding: "utf-8")
lines = content.lines

# Replace lines 28-34 (the call method)
call_start = lines.index { |l| l.strip == "def call(ctx)" }
call_end = lines.index { |l| l.strip == "end" && lines.index(l) > call_start }
# Find the first "end" after call_start
call_end = nil
(call_start + 1...lines.size).each do |i|
  if lines[i].strip == "end"
    call_end = i
    break
  end
end

new_call = <<~'METHOD'
      def call(ctx)
        raw = ctx[:output]
        # Unwrap Result to get the actual text
        output = if raw.respond_to?(:ok?) && raw.ok?
                   raw.value!.to_s
                 elsif raw.is_a?(String)
                   raw
                 else
                   return Result.ok(ctx)
                 end
        return Result.ok(ctx) if output.empty?

        cleaned = prune_mixed(output)
        # Re-wrap as Result if original was a Result
        final = raw.respond_to?(:ok?) ? Result.ok(cleaned.strip) : cleaned.strip
        Result.ok(ctx.merge(output: final))
      end
METHOD

new_lines = lines[0...call_start] + new_call.lines + lines[(call_end + 1)..]
File.write(File.join(BASE, "lib/master/stages/prune.rb"), new_lines.join)
puts "fixed: Prune now unwraps Result objects"
