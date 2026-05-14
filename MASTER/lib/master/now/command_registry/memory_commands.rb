# frozen_string_literal: true

module Master
  module Now
  module CommandRegistry
    module_function

    def memory_commands(memory, agent)
      {
        "memory" => ->(ctx) { dispatch_memory(memory, ctx[:args].to_s.strip) },
        "dreams" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "consolidate"
            memory.respond_to?(:consolidate!) ? memory.consolidate!(agent:) : "dreaming not available"
          else
            entries  = memory.all
            archived = entries.count { |k, _| k.to_s.start_with?("archive/") }
            active   = entries.count { |k, _| !k.to_s.start_with?("archive/") }
            summary  = memory.recall("_consolidated_summary")
            lines    = ["active: #{active} memories, archived: #{archived}"]
            lines << "last consolidation: #{summary}" if summary
            lines.join("\n")
          end
        }
      }
    end

    def dispatch_memory(memory, arg)
      case arg
      when /\Aforget (.+)/  then memory.forget($1.strip); "forgot: #{$1.strip}"
      when /\Aremember (.+)/
        body, type = parse_remember($1)
        key, value = body.split("=", 2).map(&:strip)
        value ? (memory.remember(key, value, type:); "remembered [#{type}]: #{key}") : "usage: /memory remember [type=user|feedback|project|reference] key=value"
      when /\Asearch (.+)/ then memory_search(memory, $1.strip)
      when /\Atype (\S+)/  then list_by_type(memory, $1.strip)
      when "types"         then memory.type_counts.map { |t, n| "#{t}: #{n}" }.join("\n").then { |s| s.empty? ? "(no memories)" : s }
      when ""
        (e = memory.all).empty? ? "(no memories)" : e.map { |k, v| "#{k}: #{v}" }.join("\n")
      else
        (r = memory.recall(arg)) ? "#{arg}: #{r}" : "(not found: #{arg})"
      end
    end

    def parse_remember(text)
      if text =~ /\Atype=(\S+)\s+(.+)/
        [$2, $1]
      else
        [text, "general"]
      end
    end

    def list_by_type(memory, type)
      hits = memory.by_type(type)
      hits.empty? ? "(no memories of type: #{type})" : hits.map { |k, v| "#{k}: #{v.is_a?(Hash) ? v["value"] : v}" }.join("\n")
    end

    def memory_search(memory, query)
      if memory.respond_to?(:semantic_recall)
        hits = memory.semantic_recall(query)
        return "(no matches: #{query})" if hits.empty?
        hits.map { |h| "#{h[:key]}: #{h[:value]}" }.join("\n")
      else
        hits = memory.all.select { |k, v| k.to_s.include?(query) || v.to_s.include?(query) }
        hits.empty? ? "(no matches: #{query})" : hits.map { |k, v| "#{k}: #{v}" }.join("\n")
      end
    end
  end
  end
end
