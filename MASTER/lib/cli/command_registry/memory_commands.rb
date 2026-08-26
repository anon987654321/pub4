# frozen_string_literal: true

require_relative "../../trace/session_capture"

module Master
  module CLI
    module CommandRegistry
      module_function

      def memory_commands(memory, agent, root: Master::ROOT)
        {
          "memory" => command(:dispatch_memory, memory),
          "dreams" => command(:dispatch_dreams, memory, agent),
          "capture" => command(:dispatch_capture, root),
        }
      end

      def dispatch_memory(memory, ctx: nil)
        arg = arg_for(ctx)
        case arg
        when /\Aforget (.+)/ then memory.forget($1.strip); "forgot: #{$1.strip}"
        when /\Aremember (.+)/ then handle_remember(memory, $1)
        when /\Asearch (.+)/ then memory_search(memory, $1.strip)
        when /\Atype (\S+)/ then list_by_type(memory, $1.strip)
        when "types"
          counts = memory.type_counts.map { |t, n| "#{t}: #{n}" }.join("\n")
          counts.empty? ? "(no memories)" : counts
        when ""
          (e = memory.all).empty? ? "(no memories)" : e.map { |k, v| "#{k}: #{v}" }.join("\n")
        else
          (r = memory.recall(arg)) ? "#{arg}: #{r}" : "(not found: #{arg})"
        end
      end

      def handle_remember(memory, rest)
        body, type = parse_remember(rest)
        key, value = body.split("=", 2).map(&:strip)
        return "usage: /memory remember [type=user|feedback|project|reference] key=value" unless value

        memory.remember(key, value, type:)
        "remembered [#{type}]: #{key}"
      end

      def dispatch_dreams(memory, agent, ctx: nil)
        arg = arg_for(ctx)
        if arg == "consolidate"
          memory.respond_to?(:consolidate!) ? memory.consolidate!(agent:) : "dreaming not available"
        else
          entries = memory.all
          archived = entries.count { |k, _| k.to_s.start_with?("archive/") }
          active = entries.count { |k, _| !k.to_s.start_with?("archive/") }
          summary = memory.recall("_consolidated_summary")
          lines = ["active: #{active} memories, archived: #{archived}"]
          lines << "last consolidation: #{summary}" if summary
          lines.join("\n")
        end
      end

      def parse_remember(text)
        return [text, "general"] unless text =~ /\Atype=(\S+)\s+(.+)/

        [$2, $1]
      end

      def list_by_type(memory, type)
        hits = memory.by_type(type)
        return "(no memories of type: #{type})" if hits.empty?
        hits.map { |k, v| "#{k}: #{v.is_a?(Hash) ? v["value"] : v}" }.join("\n")
      end

      def memory_search(memory, query)
        unless memory.respond_to?(:semantic_recall)
          hits = memory.all.select { |k, v| k.to_s.include?(query) || v.to_s.include?(query) }
          return hits.empty? ? "(no matches: #{query})" : hits.map { |k, v| "#{k}: #{v}" }.join("\n")
        end

        hits = memory.semantic_recall(query)
        return "(no matches: #{query})" if hits.empty?

        hits.map { |h| "#{h[:key]}: #{h[:value]}" }.join("\n")
      end

      def dispatch_capture(root, ctx: nil)
        text = arg_for(ctx)
        return capture_usage if text.empty?

        Master::Trace::SessionCapture.new(root:).call(text)
      end

      def capture_usage
        "usage: /capture summary techniques=... recurring_patterns=... automations=... prompts=... providers=... learned_behavior=..."
      end
    end
  end
end
