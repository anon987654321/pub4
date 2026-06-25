# frozen_string_literal: true

require "base64"
require "securerandom"
require "tempfile"

module Master
  module Judge
    class LLMDispatcher
      module RubyLLMSender
        private

        def send_ruby_llm(selected_model, messages, sys:, stream:, image: nil, &blk)
          chat_session = RubyLLM.chat(model: selected_model)
          final_sys = build_final_system(selected_model, sys)
          chat_session.with_instructions(final_sys) if final_sys

          messages[0...-1].each do |message_entry|
            chat_session.add_message(role: message_entry[:role].to_s, content: message_entry[:content].to_s)
          end

          last_entry = messages.last || {}
          last_text = last_entry[:content].to_s

          available_tools = llm_tools(selected_model)
          chat_session.with_tools(*available_tools) unless available_tools.empty?

          ask_arg = last_text
          temp_file = nil
          if image && ((!image[:path].to_s.empty? && File.file?(image[:path])) || !image[:data].to_s.empty?)
            if !image[:path].to_s.empty? && File.file?(image[:path])
              attachment = RubyLLM::Attachment.new(image[:path], filename: (image[:name].to_s.empty? ? File.basename(image[:path]) : image[:name].to_s))
            else
              ext = (if image[:mime].to_s =~ /png/i
".png"
else
(image[:mime].to_s =~ /webp/i ? ".webp" : ".jpg")
end)
              temp_file = Tempfile.new(["master_vision_#{SecureRandom.hex(4)}", ext])
              temp_file.binmode
              temp_file.write(Base64.strict_decode64(image[:data]))
              temp_file.rewind
              temp_file.close
              attachment = RubyLLM::Attachment.new(temp_file.path, filename: (image[:name].to_s.presence || "photo#{ext}"))
            end
            content = RubyLLM::Content.new(text: last_text, attachments: [attachment])
            ask_arg = content
          end

          begin
            reply = if stream && blk
                      chat_session.ask(ask_arg) { |chunk| blk.call(chunk.content.to_s) if chunk.content }
                    else
                      chat_session.ask(ask_arg)
                    end
            record_usage(reply, selected_model)
            Result.ok(extract_response(reply, selected_model))
          ensure
            if temp_file
              begin
                temp_file.close unless temp_file.closed?
                temp_file.unlink if File.exist?(temp_file.path)
              rescue StandardError
                nil
              end
            end
          end
        end

        def record_usage(reply, model)
          return unless @session
          input = reply.respond_to?(:input_tokens) ? reply.input_tokens.to_i : 0
          output = reply.respond_to?(:output_tokens) ? reply.output_tokens.to_i : 0
          cached = reply.respond_to?(:cached_tokens) ? reply.cached_tokens.to_i : 0
          cache_write = reply.respond_to?(:cache_creation_tokens) ? reply.cache_creation_tokens.to_i : 0
          tokens = input + output
          if tokens.zero? && reply.respond_to?(:content)
            tokens = Master::Trace::Session.estimate_tokens(reply.content)
            return if tokens.zero?
            cost = (tokens * COST_PER_TOKEN).round(6)
            @session.record_cost(cost, model:, tokens:)
            publish_llm_cost(model:, cost:, tokens:, tokens_in: tokens, tokens_out: 0, estimated: true)
            return
          end
          return if tokens.zero?
          regular = [input - cached - cache_write, 0].max
          cost = ((regular * COST_PER_TOKEN) +
                  (cached * COST_PER_TOKEN * CACHE_READ_RATIO) +
                  (cache_write * COST_PER_TOKEN * CACHE_WRITE_RATIO) +
                  (output * COST_PER_TOKEN)).round(6)
          @session.record_cost(cost, model:, tokens:)
          publish_llm_cost(model:, cost:, tokens:, tokens_in: input, tokens_out: output, cached:, cache_write:)
          Trace::CacheEfficiency.record(input:, cached:, cache_write:)
          @bus&.publish("cache:hit", model:, cached:, cache_write:) if cached.positive? || cache_write.positive?
        rescue StandardError => e
          @bus&.publish("cost:record_error", error: e.message)
        end

        def publish_llm_cost(model:, cost:, tokens:, tokens_in: 0, tokens_out: 0, cached: 0, cache_write: 0, estimated: false)
          line = "[$#{format('%.4f', cost.to_f)}, #{tokens.to_i} tokens]"
          payload = { model:, cost:, tokens:, cached:, cache_write:, estimated:, line: }
          @bus&.publish("llm:cost", **payload)
          @bus&.publish("llm:call_complete",
            model:,
            tokens_in:,
            tokens_out:,
            cost_usd: cost,
            estimated:,
            cached:,
            cache_write:)
          @bus&.publish("llm:transparency", model:, cost:, tokens:, estimated:, line:)
        end

        def extract_response(reply, selected_model)
          return reply.to_s unless reply.respond_to?(:content)
          content = reply.content.to_s
          thinking = reply.respond_to?(:thinking) ? reply.thinking&.text.to_s.strip : ""
          if NEMOTRON3_RE.match?(selected_model) && !thinking.empty?
            return content.empty? ? thinking : "#{content}\n\n<think>\n#{thinking}\n</think>"
          end
          content.empty? && !thinking.empty? ? thinking : content
        end

        def nemotron_system_prompt(selected_model, base = nil)
          sys = base || system_prompt
          return sys unless LLAMA_NEMOTRON_RE.match?(selected_model)
          directive = @config["reasoning_mode"] != "none" ? "detailed thinking on" : "detailed thinking off"
          [directive, sys].compact.join("\n\n")
        end

        def build_final_system(selected_model, sys)
          return sys unless claude_model?(selected_model)
          raw = @system_prompt_proc.call
          if raw.is_a?(Hash) && raw[:static]
            static_text = nemotron_system_prompt(selected_model, raw[:static])
            blocks = [{ type: "text", text: static_text, cache_control: { type: "ephemeral" } }]
            blocks << { type: "text", text: raw[:dynamic] } if raw[:dynamic]
            RubyLLM::Content::Raw.new(blocks)
          else
            base = nemotron_system_prompt(selected_model, sys)
            return base unless base.is_a?(String)
            RubyLLM::Content::Raw.new([{ type: "text", text: base, cache_control: { type: "ephemeral" } }])
          end
        end
      end
    end
  end
end
