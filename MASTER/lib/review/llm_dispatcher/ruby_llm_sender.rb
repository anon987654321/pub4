# frozen_string_literal: true

require "base64"
require "securerandom"
require "tempfile"

module Master
  module Review
    class LLMDispatcher
      module RubyLLMSender
        ToolRoundLimit = Class.new(StandardError)

        private

        def send_ruby_llm(selected_model, messages, sys:, stream:, image: nil, temperature: nil, format: nil, &blk)
          chat_session = build_chat_session(selected_model, messages, sys:, image:, temperature:, format:)
          last_text = (messages.last || {})[:content].to_s
          ask_arg, temp_file = build_ask_arg(last_text, image)

          begin
            reply = if stream && blk
                      chat_session.ask(ask_arg) { |chunk| blk.call(chunk.content.to_s) if chunk.content }
                    else
                      chat_session.ask(ask_arg)
                    end
            record_usage(reply, selected_model)
            Result.ok(extract_response(reply))
          rescue ToolRoundLimit => e
            Result.err("#{selected_model}: #{e.message}", category: :llm_call_failure)
          ensure
            cleanup_temp_file(temp_file)
          end
        end

        def build_chat_session(selected_model, messages, sys:, image:, temperature: nil, format: nil)
          # A context copies the configuration, so the key this call sends is the key
          # it started with. KeyRotator swaps the global key under rule groups that
          # run in threads, and a shared config handed that swap to calls in flight.
          chat_session = RubyLLM.context.chat(model: selected_model)
          final_sys = build_final_system(selected_model, sys)
          chat_session.with_instructions(final_sys) if final_sys
          chat_session.with_temperature(temperature) if temperature && chat_session.respond_to?(:with_temperature)

          messages[0...-1].each do |message_entry|
            chat_session.add_message(role: message_entry[:role].to_s, content: message_entry[:content].to_s)
          end

          # The same contract the local tier holds a model to, wherever the
          # registry says the model can take it; elsewhere the caller's parser is
          # the only check, as it always was.
          chat_session.with_schema(format) if format && structured_output?(selected_model)
          available_tools = format ? [] : llm_tools(selected_model)
          unless available_tools.empty?
            chat_session.with_tools(*available_tools)
            cap_tool_rounds(chat_session)
          end
          chat_session
        end

        # The gem answers every tool call by asking again, with no limit; its
        # `calls:` option chooses one call or several per turn, not how many turns.
        # REACT_MAX_STEPS already bounds the emulated loop, so it bounds this one.
        def cap_tool_rounds(chat_session)
          rounds = 0
          # RubyLLM 1.15 renamed the hook and warns on the old name, a line that
          # lands in the middle of the prompt; 1.13 knows only the old one.
          count = lambda do |message|
            next unless message.respond_to?(:tool_call?) && message.tool_call?

            rounds += 1
            raise ToolRoundLimit, "tool calling passed #{REACT_MAX_STEPS} rounds" if rounds > REACT_MAX_STEPS
          end
          return chat_session.after_message(&count) if chat_session.respond_to?(:after_message)

          chat_session.on_end_message(&count)
        end

        def build_ask_arg(last_text, image)
          has_image = image && ((!image[:path].to_s.empty? && File.file?(image[:path])) || !image[:data].to_s.empty?)
          return [last_text, nil] unless has_image

          attachment, temp_file = build_image_attachment(image)
          content = RubyLLM::Content.new(text: last_text, attachments: [attachment])
          [content, temp_file]
        end

        def build_image_attachment(image)
          if !image[:path].to_s.empty? && File.file?(image[:path])
            return [RubyLLM::Attachment.new(image[:path], filename: (image[:name].to_s.empty? ? File.basename(image[:path]) : image[:name].to_s)), nil]
          end

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
          name = image[:name].to_s
          attachment = RubyLLM::Attachment.new(temp_file.path, filename: name.empty? ? "photo#{ext}" : name)
          [attachment, temp_file]
        end

        def cleanup_temp_file(temp_file)
          return unless temp_file

          temp_file.close unless temp_file.closed?
          temp_file.unlink if File.exist?(temp_file.path)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RubyLLMSender.cleanup_temp_file")
          nil
        end

        def record_usage(reply, model)
          return unless @session
          input = reply.respond_to?(:input_tokens) ? reply.input_tokens.to_i : 0
          output = reply.respond_to?(:output_tokens) ? reply.output_tokens.to_i : 0
          cached = reply.respond_to?(:cached_tokens) ? reply.cached_tokens.to_i : 0
          cache_write = reply.respond_to?(:cache_creation_tokens) ? reply.cache_creation_tokens.to_i : 0
          tokens = input + output
          return record_estimated_usage(reply, model) if tokens.zero? && reply.respond_to?(:content)
          return if tokens.zero?

          record_measured_usage(model, input:, output:, cached:, cache_write:, tokens:)
        rescue StandardError => e
          @bus&.publish("cost:record_error", error: e.message)
        end

        # ruby_llm's registry carries a real price for every model it knows, and
        # input and output are rarely the same number — Sonnet is $3 and $15 per
        # million. COST_PER_TOKEN is that $15, and charging it to both directions
        # of every model billed a free OpenRouter model — the ones KeyRotator
        # exists to rotate — at the most expensive rate in the catalogue. The
        # circuit breaker spends a dollar budget against this figure.
        #
        # A model the registry does not know keeps the flat rate. Pricing an
        # unknown model at zero would let it run until something else stopped it.
        # The registry carries no `:free` ids, so those are zero only where the
        # provider catalog's own row says zero — never on the suffix alone.
        def price_per_token(model, direction)
          per_million = listed_price_per_million(model, direction)
          return 0.0 if !per_million&.positive? && catalog_free?(model)
          return COST_PER_TOKEN unless per_million&.positive?

          per_million.to_f / 1_000_000
        end

        def listed_price_per_million(model, direction)
          info = Master::Review::LLMDispatcher.model_info(model)
          info && (direction == :output ? info.output_price_per_million : info.input_price_per_million)
        end

        # True when either direction fell to the flat rate, so the amount is a
        # ceiling charged to a model nobody priced rather than a bill.
        def flat_rate?(model)
          %i[input output].any? do |direction|
            !listed_price_per_million(model, direction)&.positive? && !catalog_free?(model)
          end
        end

        def catalog_free?(model)
          return false unless model.to_s.end_with?(":free")

          require_relative "../../io/catalog_index"
          Master::Io::CatalogIndex.verified_free?(model)
        end

        def record_estimated_usage(reply, model)
          tokens = Master::Trace::Session.estimate_tokens(reply.content)
          return if tokens.zero?

          cost = (tokens * price_per_token(model, :output)).round(6)
          approximate = flat_rate?(model)
          @session.record_cost(cost, model:, tokens:, approximate:)
          publish_llm_cost(model:, cost:, tokens:, tokens_in: tokens, tokens_out: 0, estimated: true, approximate:)
        end

        def record_measured_usage(model, input:, output:, cached:, cache_write:, tokens:)
          regular = [input - cached - cache_write, 0].max
          input_price = price_per_token(model, :input)
          cost = ((regular * input_price) +
                  (cached * input_price * CACHE_READ_RATIO) +
                  (cache_write * input_price * CACHE_WRITE_RATIO) +
                  (output * price_per_token(model, :output))).round(6)
          approximate = flat_rate?(model)
          @session.record_cost(cost, model:, tokens:, approximate:)
          @session.record_input_tokens(input) if @session.respond_to?(:record_input_tokens)
          publish_llm_cost(model:, cost:, tokens:, tokens_in: input, tokens_out: output, cached:, cache_write:, approximate:)
          Trace::CacheEfficiency.record(input:, cached:, cache_write:)
          @bus&.publish("cache:hit", model:, cached:, cache_write:) if cached.positive? || cache_write.positive?
        end

        def publish_llm_cost(model:, cost:, tokens:, tokens_in: 0, tokens_out: 0, cached: 0, cache_write: 0, estimated: false,
                             approximate: false)
          line = "[#{'~' if approximate}$#{format('%.4f', cost.to_f)}, #{tokens.to_i} tokens]"
          payload = { model:, cost:, tokens:, cached:, cache_write:, estimated:, approximate:, line: }
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

        def structured_output?(model)
          info = Master::Review::LLMDispatcher.model_info(model)
          info.respond_to?(:structured_output?) && info.structured_output?
        end

        # A schema-bound reply arrives parsed. Hash#to_s is Ruby's inspect, which
        # no JSON parser reads, so it goes back out as the JSON it came in as.
        def extract_response(reply)
          return reply.to_s unless reply.respond_to?(:content)
          content = reply.content
          content = content.is_a?(Hash) || content.is_a?(Array) ? JSON.generate(content) : content.to_s
          thinking = reply.respond_to?(:thinking) ? reply.thinking&.text.to_s.strip : ""
          # A reasoning model's working is not its answer: appended, it reached the
          # terminal verbatim, and every other reader had to strip it. The answer
          # stands alone, and the working speaks only when there is no answer.
          return thinking if content.empty? && !thinking.empty?

          content
        end

        def nemotron_system_prompt(selected_model, base = nil)
          sys = base || system_prompt
          return sys unless LLAMA_NEMOTRON_RE.match?(selected_model)
          directive = @config["reasoning_mode"] != "none" ? "detailed thinking on" : "detailed thinking off"
          [directive, sys].compact.join("\n\n")
        end

        # The static/dynamic split caches the persona prompt, so it applies only
        # when sys is that prompt. A caller's own system prompt is other text, and
        # sending the persona split in its place drops the caller's instructions.
        def build_final_system(selected_model, sys)
          return sys unless claude_model?(selected_model)
          raw = @system_prompt_proc.call
          if raw.is_a?(Hash) && raw[:static] && sys.to_s.start_with?(raw[:static])
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

      # How a provider failure is named, so the chain can tell a network that is
      # gone from a provider that refused.
      module ProviderFailure
        private

        # The machine cannot reach the provider at all: the name did not resolve
        # or no route exists. A refused connection is left out, because one
        # provider refusing says nothing about the network. The local sender
        # names its own failures and is not offline when its daemon is down.
        OFFLINE_SIGNS = ["getaddrinfo", "nodename nor servname", "name or service not known",
                         "temporary failure in name resolution", "network is unreachable",
                         "no route to host", "enetunreach", "ehostunreach"].freeze
        OFFLINE_RE = Regexp.new(OFFLINE_SIGNS.map { |sign| Regexp.escape(sign) }.join("|"), Regexp::IGNORECASE)

        def offline_error?(err)
          message = err.message.to_s
          !message.start_with?("ollama ") && message.match?(OFFLINE_RE)
        end

        def billing_error?(err)
          err.message.to_s.match?(/insufficient credits|credit balance|payment required|\b402\b|billing/i)
        end

        def rate_limit_error?(err)
          err.message.to_s.match?(/rate.?limit|too many requests|\b429\b/i)
        end

        def missing_key_error?(err)
          return false if Master.keyless_llm_enabled?
          error_message = err.message.to_s
          error_message.match?(/missing configuration/i) ||
            error_message.match?(/api[_\- ]?key/i) ||
            error_message.match?(/unauthorized/i) ||
            error_message.match?(/401/) ||
            !Master.any_api_key_present?
        end
      end
    end
  end
end
