# frozen_string_literal: true

require "json"

module Master
  module Grok
    # Extract the latest assistant reply from Grok/Cursor session JSONL files.
    module Transcript
      module_function

      def extract(path)
        path = path.to_s
        return "" if path.empty?

        resolved = resolve_path(path)
        text =
          if resolved.end_with?("updates.jsonl")
            extract_updates(resolved)
          else
            extract_chat_history(resolved)
          end

        text = extract_updates(path) if text.empty? && path.end_with?("updates.jsonl")
        if text.empty?
          chat = File.join(File.dirname(path), "chat_history.jsonl")
          text = extract_chat_history(chat) if File.file?(chat)
        end

        text.to_s.strip
      end

      def resolve_path(path)
        return path unless File.file?(path)

        base = File.dirname(path)
        chat = File.join(base, "chat_history.jsonl")
        return chat if File.file?(chat) && File.size?(chat).to_i.positive?

        path
      end

      def extract_chat_history(path)
        return "" unless File.file?(path)

        turn_best = ""
        last = ""

        File.foreach(path, encoding: "UTF-8") do |line|
          line = line.strip
          next if line.empty?

          o = JSON.parse(line)
        rescue JSON::ParserError
          next
        else
          if o["type"] == "user" || o["role"] == "user"
            last = turn_best if turn_best.length > last.length
            turn_best = ""
            next
          end

          text = assistant_text(o)
          next if text.nil? || text.empty?

          turn_best = text if text.length > turn_best.length
        end

        last = turn_best if turn_best.length > last.length
        last
      end

      def extract_updates(path)
        return "" unless File.file?(path)

        turns = {}
        order = []

        File.foreach(path, encoding: "UTF-8") do |line|
          line = line.strip
          next if line.empty?

          o = JSON.parse(line)
        rescue JSON::ParserError
          next
        else
          next unless o["method"] == "session/update"

          update = o.dig("params", "update") || {}
          next unless update["sessionUpdate"] == "agent_message_chunk"

          content = update["content"] || {}
          next unless content["type"] == "text"

          chunk = (content["text"] || "").to_s
          next if chunk.empty?

          key = update.dig("_meta", "promptId") ||
                update.dig("_meta", "turnStartMs") ||
                o.dig("params", "sessionId") ||
                "default"

          turns[key] = (turns[key] || "") + chunk
          order << key unless order.include?(key)
        end

        return "" if order.empty?

        turns[order.last].to_s.strip
      end

      def assistant_text(obj)
        if obj["type"] == "assistant"
          (obj["content"] || "").strip
        elsif obj["role"] == "assistant"
          msg = obj["message"] || {}
          parts = (msg["content"] || []).filter_map do |block|
            next unless block.is_a?(Hash) && block["type"] == "text"

            t = (block["text"] || "").strip
            t unless t.empty?
          end
          parts.join("\n").strip unless parts.empty?
        end
      end
      private_class_method :assistant_text
    end
  end
end