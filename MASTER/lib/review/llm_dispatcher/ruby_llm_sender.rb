# frozen_string_literal: true

require_relative "../../execution/contract"
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
          ask_arg, attachment, temp_file = build_ask_arg(last_text, image)

          begin
            reply = if attachment
                      if stream && blk
                        chat_session.ask(ask_arg, with: attachment) { |chunk| blk.call(chunk.content.to_s) if chunk.content }
                      else
                        chat_session.ask(ask_arg, with: attachment)
                      end
                    elsif stream && blk
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
          apply_system_instructions(chat_session, selected_model, sys)
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
          # RubyLLM 2 exposes after_message as the message callback; the old
          # on_end_message compatibility path is deliberately gone.
          count = lambda do |message|
            next unless message.respond_to?(:tool_call?) && message.tool_call?

            rounds += 1
            raise ToolRoundLimit, "tool calling passed #{REACT_MAX_STEPS} rounds" if rounds > REACT_MAX_STEPS
          end
          chat_session.after_message(&count)
        end

        def build_ask_arg(last_text, image)
          has_image = image && ((!image[:path].to_s.empty? && File.file?(image[:path])) || !image[:data].to_s.empty?)
          return [last_text, nil, nil] unless has_image

          attachment, temp_file = build_image_attachment(image)
          [last_text, with_extra_attachments(attachment, image), temp_file]
        end

        # image[:extra] holds further on-disk images; the gem takes a list.
        def with_extra_attachments(attachment, image)
          extras = Array(image[:extra]).filter_map do |extra|
            path = extra[:path].to_s
            next unless File.file?(path)

            RubyLLM::Attachment.new(path, filename: (extra[:name].to_s.empty? ? File.basename(path) : extra[:name].to_s))
          end
          extras.empty? ? attachment : [attachment, *extras]
        end

        def build_image_attachment(image)
          if !image[:path].to_s.empty? && File.file?(image[:path])
            return [RubyLLM::Attachment.new(image[:path], filename: (image[:name].to_s.empty? ? File.basename(image[:path]) : image[:name].to_s)), nil]
          end

          mime = image[:mime].to_s
          ext = if mime.match?(/png/i) then ".png"
                elsif mime.match?(/webp/i) then ".webp"
                else ".jpg"
                end
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

          usage = reply.respond_to?(:tokens) ? reply.tokens : nil
          input = usage&.input.to_i
          output = usage&.output.to_i
          cached = usage&.cache_read.to_i
          cache_write = usage&.cache_write.to_i
          total_tokens = input + cached + cache_write + output
          reported_cost = usage.reported_cost if usage&.respond_to?(:reported_cost)
          reported_cost = nonnegative_cost(reported_cost)
          return record_estimated_usage(reply, model, cost_override: reported_cost) if total_tokens.zero? && reply.respond_to?(:content)
          return if total_tokens.zero? && reported_cost.nil?

          cache_write_details = usage.respond_to?(:cache_write_by_ttl) ? usage.cache_write_by_ttl : nil
          cache_write_cost = cache_write_cost_from(reply, cache_write_details) if reported_cost.nil?
          server_tool_use = usage.server_tool_use if usage&.respond_to?(:server_tool_use)
          record_measured_usage(
            model, input:, output:, cached:, cache_write:, tokens: total_tokens,
            cost_override: reported_cost, cache_write_cost:, cache_write_details:, server_tool_use:,
          )
        rescue StandardError => e
          @bus&.publish("cost:record_error", error_class: e.class.name, **Master::Execution::Contract.diagnostic_fields(e.message))
        end

        # RubyLLM reports ordinary input separately from cache reads and writes.
        # Use cache-write lifetime pricing only when the provider reports the TTL
        # split and RubyLLM exposes the priced component; otherwise retain the
        # marked estimate below rather than guessing a provider-specific rate.
        def cache_write_cost_from(reply, cache_write_details)
          return if !cache_write_details.respond_to?(:empty?) || cache_write_details.empty?
          return unless reply.respond_to?(:cost)

          cost = reply.cost
          return unless cost.respond_to?(:cache_write)

          nonnegative_cost(cost.cache_write)
        rescue StandardError => e
          @bus&.publish("cost:cache_write_pricing_error", error_class: e.class.name, **Master::Execution::Contract.diagnostic_fields(e.message))
          nil
        end

        def nonnegative_cost(value)
          return unless value.is_a?(Numeric)

          amount = value.to_f
          amount if amount.finite? && amount >= 0
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
          info&.price(direction)
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

        def record_estimated_usage(reply, model, cost_override: nil)
          tokens = Master::Trace::Session.estimate_tokens(reply.content)
          return if tokens.zero? && cost_override.nil?

          cost = cost_override.nil? ? (tokens * price_per_token(model, :output)).round(6) : cost_override
          approximate = cost_override.nil? && flat_rate?(model)
          @session.record_cost(cost, model:, tokens:, approximate:)
          Master::Io::PaidTail.spend!(model, cost)
          publish_llm_cost(model:, cost:, tokens:, tokens_in: tokens, tokens_out: 0, estimated: true, approximate:)
        end

        def record_measured_usage(model, input:, output:, cached:, cache_write:, tokens:,
                                  cost_override: nil, cache_write_cost: nil, cache_write_details: nil,
                                  server_tool_use: nil)
          input_price = price_per_token(model, :input)
          write_cost = cache_write_cost.nil? ? cache_write * input_price * CACHE_WRITE_RATIO : cache_write_cost
          input_total = input + cached + cache_write
          cost = if cost_override.nil?
                   ((input * input_price) +
                    (cached * input_price * CACHE_READ_RATIO) +
                    write_cost +
                    (output * price_per_token(model, :output))).round(6)
                 else
                   cost_override
                 end
          lifetime_estimate = cache_write_details.respond_to?(:empty?) && !cache_write_details.empty? &&
                              cache_write_cost.nil? && cost_override.nil?
          unpriced_server_tools = server_tool_use.respond_to?(:empty?) && !server_tool_use.empty? && cost_override.nil?
          approximate = cost_override.nil? && (flat_rate?(model) || lifetime_estimate || unpriced_server_tools)
          @session.record_cost(cost, model:, tokens:, approximate:)
          Master::Io::PaidTail.spend!(model, cost)
          @session.record_input_tokens(input_total) if @session.respond_to?(:record_input_tokens)
          publish_llm_cost(model:, cost:, tokens:, tokens_in: input_total, tokens_out: output, cached:, cache_write:, approximate:)
          Trace::CacheEfficiency.record(input: input_total, cached:, cache_write:)
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
            cache_write:,
            cache_hit: cached.to_i.positive?)
          @bus&.publish("llm:transparency", model:, cost:, tokens:, estimated:, line:)
        end

        def structured_output?(model)
          info = Master::Review::LLMDispatcher.model_info(model)
          info&.respond_to?(:supports?) && info.supports?(:structured_output)
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
          return [] if sys.nil?

          unless claude_model?(selected_model)
            return [{ text: sys, append: false, cache_until_here: false }]
          end

          raw = @system_prompt_proc.call
          if raw.is_a?(Hash) && raw[:static] && sys.to_s.start_with?(raw[:static])
            blocks = [{ text: nemotron_system_prompt(selected_model, raw[:static]), append: false, cache_until_here: true }]
            blocks << { text: raw[:dynamic], append: true, cache_until_here: false } if raw[:dynamic]
            blocks
          else
            base = nemotron_system_prompt(selected_model, sys)
            return [] unless base.is_a?(String)

            [{ text: base, append: false, cache_until_here: true }]
          end
        end

        def apply_system_instructions(chat_session, selected_model, sys)
          build_final_system(selected_model, sys).each do |block|
            chat_session.with_instructions(
              block[:text],
              append: block[:append],
              cache_until_here: block[:cache_until_here],
            )
          end
        end
      end

      # How a provider failure is named, so the chain can tell a network that is
      # gone from a provider that refused.
      module ProviderFailure
        private

        # RubyLLM 2.1 normalizes provider HTTP failures into typed classes. Their
        # class is stronger evidence than provider-specific message wording; CLI,
        # gateway and older-provider errors still use the established text fallback.
        RUBY_LLM_ERROR_CATEGORIES = {
          "RubyLLM::PaymentRequiredError" => :budget,
          "RubyLLM::RateLimitError" => :rate_limit,
          "RubyLLM::OverloadedError" => :rate_limit,
          "RubyLLM::BadRequestError" => :invalid_request,
          "RubyLLM::ContextLengthExceededError" => :invalid_request,
          "RubyLLM::UnsupportedAttachmentError" => :invalid_request,
          "RubyLLM::ModelNotFoundError" => :model_missing,
          "RubyLLM::UnauthorizedError" => :auth_error,
          "RubyLLM::ForbiddenError" => :auth_error,
          "RubyLLM::ServerError" => :provider_error,
          "RubyLLM::ServiceUnavailableError" => :provider_error,
        }.freeze

        def ruby_llm_error_category(err)
          ancestors = err.class.ancestors.filter_map(&:name)
          RUBY_LLM_ERROR_CATEGORIES.each do |class_name, category|
            return category if ancestors.include?(class_name)
          end
          nil
        end

        # The lane cannot be reached at all: the name did not resolve, no route
        # exists, the connection was refused or the local daemon is down. Each is
        # an unreachable lane (LaneReply reads the same words), and the failover
        # chain moves on and answers a typed Offline only when no lane is left.
        OFFLINE_SIGNS = ["getaddrinfo", "nodename nor servname", "name or service not known",
                         "temporary failure in name resolution", "network is unreachable",
                         "no route to host", "enetunreach", "ehostunreach",
                         "connection refused", "ollama unreachable"].freeze
        OFFLINE_RE = Regexp.new(OFFLINE_SIGNS.map { |sign| Regexp.escape(sign) }.join("|"), Regexp::IGNORECASE)
        # A spent subscription reads as a spent balance: codex answers "You've
        # hit your usage limit" until its plan resets, and no retry cures that.
        BILLING_SIGNS = ["insufficient credits", "credit balance", "payment required", "402", "billing",
                         "usage limit", "quota reached", "quota exceeded"].freeze
        BILLING_RE = Regexp.union(BILLING_SIGNS.map { |sign| /\b#{Regexp.escape(sign)}/i }).freeze
        # An overloaded upstream is a rate limit in all but name: the free
        # nemotron answered "Service temporarily overloaded", and retrying it in
        # place slept the 30s and 60s backoff while other free models were idle.
        RATE_LIMIT_RE = /rate.?limit|too many requests|\b429\b|overloaded|at capacity/i.freeze

        INVALID_REQUEST_RE = /parameters requires a schema|invalid (?:request|parameter|argument)|malformed request|bad request/i.freeze

        def offline_error?(err)
          err.message.to_s.match?(OFFLINE_RE)
        end

        def billing_error?(err) = err.message.to_s.match?(BILLING_RE)

        def rate_limit_error?(err) = err.message.to_s.match?(RATE_LIMIT_RE)

        def invalid_request_error?(err) = err.message.to_s.match?(INVALID_REQUEST_RE)

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
