# frozen_string_literal: true

require "json"

module Master
  module Io
    # Extract the latest assistant reply from Grok/Cursor session JSONL files.
    module GrokTranscript
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

        state = { turn_best: "", last: "" }
        File.foreach(path, encoding: "UTF-8") do |line|
          line = line.strip
          next if line.empty?

          o = JSON.parse(line)
        rescue JSON::ParserError
          next
        else
          apply_chat_history_object(o, state)
        end

        state[:last] = state[:turn_best] if state[:turn_best].length > state[:last].length
        state[:last]
      end

      def apply_chat_history_object(o, state)
        if o["type"] == "user" || o["role"] == "user"
          state[:last] = state[:turn_best] if state[:turn_best].length > state[:last].length
          state[:turn_best] = ""
          return
        end

        text = assistant_text(o)
        return if text.nil? || text.empty?

        state[:turn_best] = text if text.length > state[:turn_best].length
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
          apply_update_object(o, turns, order)
        end

        return "" if order.empty?

        turns[order.last].to_s.strip
      end

      def apply_update_object(o, turns, order)
        return unless o["method"] == "session/update"

        update = o.dig("params", "update") || {}
        return unless update["sessionUpdate"] == "agent_message_chunk"

        content = update["content"] || {}
        return unless content["type"] == "text"

        chunk = (content["text"] || "").to_s
        return if chunk.empty?

        key = update.dig("_meta", "promptId") ||
              update.dig("_meta", "turnStartMs") ||
              o.dig("params", "sessionId") ||
              "default"

        turns[key] = (turns[key] || "") + chunk
        order << key unless order.include?(key)
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
      private_class_method :assistant_text, :apply_chat_history_object, :apply_update_object
    end
  end
end
