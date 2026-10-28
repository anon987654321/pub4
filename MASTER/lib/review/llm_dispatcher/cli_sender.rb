# frozen_string_literal: true

require "base64"
require "json"
require "tempfile"
require "timeout"
require_relative "../../io/exec"
require_relative "claude_stream"

module Master
  module Review
    class LLMDispatcher
      # The lanes that answer through a signed-in command-line client rather
      # than an HTTP API: agy, claude, and the ones models.yml cli_lanes
      # declares (codex, grok). Each is asked one question in a subprocess and
      # answers with text.
      module CliSender
        CLI_LANE_TIMEOUT_S = 300

        private

        def cli_lane_model?(model_id) = cli_lanes.key?(model_id.to_s.split(":", 2).first)

        # A lane from models.yml: its ask arguments with the prompt and reply
        # file filled in, the model flag unless the model is auto, the prompt on
        # stdin when the arguments do not carry it, and the reply read from the
        # file when the CLI wrote one.
        def send_cli_lane(selected_model, messages, sys:)
          name, model = selected_model.to_s.split(":", 2)
          prompt = [sys.to_s, text_prompt_for(messages)].reject(&:empty?).join("\n\n---\n\n")
          Tempfile.create(["master_#{name}", ".txt"]) do |reply_file|
            ask_cli_lane(name, model, prompt, reply_file.path)
          end
        end

        def ask_cli_lane(name, model, prompt, reply_path)
          lane = cli_lanes.fetch(name)
          out, err, status = with_cli_slot do
            capture3_with_timeout(CLI_LANE_TIMEOUT_S, cli_binary(lane["binary"]),
                                  *cli_lane_args(lane, model, prompt, reply_path),
                                  stdin_data: cli_lane_stdin(lane, prompt))
          end
          cli_lane_result(name, out, err, status, reply_path)
        rescue Timeout::Error
          Result.err("#{name}: timed out after #{PassClock.call_deadline(CLI_LANE_TIMEOUT_S)}s", category: :timeout)
        rescue StandardError => e
          Result.err("#{name}: #{e.message}", category: :provider_error)
        end

        def cli_lane_args(lane, model, prompt, reply_path)
          args = Array(lane["ask"]).map { |arg| arg.to_s.gsub("%{prompt}", prompt).gsub("%{reply_file}", reply_path) }
          lane["model_flag"] && model.to_s != "auto" ? args + [lane["model_flag"], model] : args
        end

        def cli_lane_stdin(lane, prompt)
          Array(lane["ask"]).any? { |arg| arg.to_s.include?("%{prompt}") } ? nil : prompt
        end

        # A failure carries the CLI's last words, which is where codex and grok
        # say a plan is spent or a session signed out.
        def cli_lane_result(name, out, err, status, reply_path)
          reply = File.file?(reply_path) ? File.read(reply_path).strip : ""
          reply = out.to_s.strip if reply.empty?
          return Result.ok(reply) if status.success? && !reply.empty?

          said = cli_lane_complaint(out, err) || "exit #{status.exitstatus}"
          Result.err("#{name}: #{said}", category: :provider_error)
        end

        def cli_lane_complaint(out, err)
          said = [err, out].map { |text| text.to_s.strip }.reject(&:empty?).last
          said&.lines&.last(2)&.join&.strip
        end

        def with_cli_slot
          CLI_SLOTS.pop
          yield
        ensure
          CLI_SLOTS << true
        end

        def cli_binary(binary)
          home = File.expand_path("~/.local/bin/#{binary}")
          File.executable?(home) ? home : binary.to_s
        end

        def cli_lanes = Master.cli_lanes

        # A lane whose program is not installed refuses at once rather than
        # failing inside a subprocess that never starts: ENOENT reads as a
        # provider error, and the chain slept through its backoff before
        # walking on. Absent is permanent, so the chain walks on at once.
        def send_agy_cli(model_alias, messages, sys:, stream: false, &blk)
          agy_bin = find_agy_bin
          return Result.err("agy: no agy on PATH", category: :no_api_key) unless agy_bin

          with_cli_slot { agy_cli_call(agy_bin, model_alias, messages, sys, stream, &blk) }
        end

        def agy_cli_call(agy_bin, model_alias, messages, sys, stream, &blk)
          prompt = text_prompt_for(messages)
          full_prompt = sys && !sys.empty? ? "#{sys}\n\n---\n\n#{prompt}" : prompt
          args = [agy_bin, "-p", full_prompt, "--output-format", "text"]
          args += ["--model", model_alias] if model_alias && !["", "auto", "agy"].include?(model_alias)
          timeout_s = agy_cli_timeout_s
          out, err, status = capture3_with_timeout(timeout_s, *args)
          return Result.err("agy: #{err.strip}", category: :provider_error) unless status.success?

          out.strip.tap { |said| blk&.call(said) if stream && block_given? }.then { |said| Result.ok(said) }
        rescue Timeout::Error
          Result.err("agy: timed out after #{PassClock.call_deadline(timeout_s)}s", category: :timeout)
        rescue StandardError => e
          Result.err("agy: #{e.message}", category: :provider_error)
        end

        def find_agy_bin
          configured = ENV["AGY_BIN"]
          return configured if configured && File.file?(configured) && File.executable?(configured)

          Master::Io::Exec.which("agy", prefer: [File.expand_path("~/.local/bin")])
        end

        def agy_cli_timeout_s
          Integer(ENV.fetch("MASTER_AGY_CLI_TIMEOUT", AGY_CLI_TIMEOUT_S.to_s))
        rescue ArgumentError
          AGY_CLI_TIMEOUT_S
        end

        # At most two claude subprocesses at once, process-wide. The latency
        # table above CLAUDE_CLI_TIMEOUT_S measured it: two concurrent finish
        # together, four roughly double per-call latency for the same total
        # throughput — and the fix loop runs rule groups in threads, so the
        # 2026-08-20 proof run showed CLI calls dying empty-stderr under
        # four-way contention, opening the circuit. Callers block for a slot;
        # waiting beats thrashing.
        CLI_SLOTS = Integer(ENV.fetch("MASTER_CLI_SLOTS", 2)).then { |n| SizedQueue.new(n).tap { |queue| n.times { queue << true } } }

        # With a block the reply streams: its text reaches the block as the model writes it (see ClaudeStream), and
        # the result is still the whole reply.
        def send_claude_cli(model_alias, messages, **request, &on_text)
          return Result.err("claude-cli: no claude on PATH", category: :no_api_key) unless claude_on_path?

          run = claude_request(model_alias, messages, **request)
          run = run.streaming(&on_text) if on_text
          with_cli_slot { claude_execute(run) }
        end

        # The images a request carries, as the content blocks `claude --print` takes on
        # stream-json input: the primary image (a path or base64 data) then image[:extra].
        # The plain-text lane drops images, and a vision model that never saw the
        # screenshot judges a layout from numbers alone.
        def claude_image_blocks(image)
          return [] unless image.respond_to?(:[])

          entries = [image, *Array(image[:extra])]
          entries.filter_map do |entry|
            path = entry[:path].to_s
            data = if !path.empty? && File.file?(path)
              Base64.strict_encode64(File.binread(path))
            elsif !entry[:data].to_s.empty?
              entry[:data].to_s
            end
            next unless data

            mime = entry[:mime].to_s
            mime = { ".png" => "image/png", ".webp" => "image/webp", ".gif" => "image/gif" }.fetch(File.extname(path).downcase, "image/jpeg") if mime.empty?
            { type: "image", source: { type: "base64", media_type: mime, data: } }
          end
        end

        # The reply of a stream-json run: the final `result` event's text.
        def claude_stream_reply(out)
          event = out.lines.filter_map { |line| JSON.parse(line) rescue nil }.reverse.find { |e| e["type"] == "result" }
          return nil unless event

          event["is_error"] ? nil : event["result"].to_s
        end

        # The same reading of PATH that ModelRouter uses to keep an absent lane
        # out of a chain, here so a dispatch reached any other way refuses too.
        # MASTER_NO_CLAUDE_CLI=1 takes the lane out on a box that has the binary.
        def claude_on_path?
          return false if ENV["MASTER_NO_CLAUDE_CLI"] == "1"
          return @claude_on_path unless @claude_on_path.nil?

          @claude_on_path = !claude_binary.nil?
        end

        def claude_binary = (@claude_binary ||= Master::Io::Exec.cli_binary("claude"))

        # The first two mark the parent as a Claude Code session, and a `claude --print`
        # that inherits them from one hangs until killed. The second two are keys MASTER
        # loads for its API lanes: `claude` prefers a key to its own subscription login
        # and exits 1 when the key has no credit, so this keyless lane starts without
        # them. CLAUDE_CODE_OAUTH_TOKEN and the other CLAUDE_* names can carry the
        # login, so they stay.
        CLAUDE_SESSION_ENV = {
          "CLAUDECODE" => nil, "CLAUDE_CODE_ENTRYPOINT" => nil,
          "ANTHROPIC_API_KEY" => nil, "ANTHROPIC_AUTH_TOKEN" => nil
        }.freeze

        # A lane answers in text and nothing else. Left its tools, `claude --print`
        # edited files and ran git inside the /fix worktree on its own: it committed
        # twice there, past the verifier, the proof and the pass transaction. No
        # built-in tool and no MCP server; the dispatcher's caller does the writing.
        # The operator's Claude Code hooks are not MASTER's: in the 2026-10-22 trial a user Stop hook demanding
        # evidence of vps-deploy fired on every lane call, and each reply to a personal question opened by
        # explaining that no deploy had run.
        CLAUDE_CLI_TEXT_ONLY = ["--tools", "", "--strict-mcp-config", "--settings", '{"disableAllHooks":true}'].freeze

        # The subscription's own limit answers on stdout and exits 0. Taken as the
        # model's reply, "You've hit your session limit · resets 4:30pm" was proposed
        # as a fix or a verdict two hundred times in one /fix run, until someone read
        # the recordings. It is a quota, and the lane stands down like one.
        CLAUDE_CLI_LIMIT = /\A\s*(?:You've hit your \w*\s*limit|Claude (?:AI )?usage limit reached)/i

        def claude_cli_call(model_alias, messages, sys, image = nil)
          claude_execute(claude_request(model_alias, messages, sys:, image:))
        end

        CLAUDE_IMAGE_FLAGS = ["--input-format", "stream-json", "--output-format", "stream-json", "--verbose"].freeze
        CLAUDE_STREAM_FLAGS = ["--output-format", "stream-json", "--verbose", "--include-partial-messages"].freeze

        # One `claude --print` run: its arguments, its stdin, the stream reader when it streams, and whether its
        # stdout is stream-json events rather than the reply itself.
        ClaudeRun = Data.define(:args, :stdin, :stream, :json) do
          # The same run, its reply passed to the block as it is written. An image run already speaks stream-json
          # on stdin and is left whole.
          def streaming(&on_text)
            return self if json

            with(args: args + CLAUDE_STREAM_FLAGS, stream: ClaudeStream.new(&on_text), json: true)
          end
        end

        def claude_execute(run)
          out, err, status = claude_capture(run)
          return claude_cli_failure(out, err, status:) unless status.success?

          run.stream&.finish
          claude_cli_reply(run.json ? claude_stream_reply(out).to_s : out, json: run.json)
        rescue Timeout::Error
          Result.err("claude-cli: timed out after #{PassClock.call_deadline(claude_cli_timeout_s)}s", category: :timeout)
        rescue StandardError => e
          Result.err("claude-cli: #{e.message}", category: :provider_error)
        end

        def claude_capture(run)
          capture3_with_timeout(claude_cli_timeout_s, *run.args, stdin_data: run.stdin, env: CLAUDE_SESSION_ENV,
                                                                 on_stdout: run.stream&.method(:feed))
        end

        # Images ride stream-json input; plain text goes on stdin as it is.
        def claude_request(model_alias, messages, sys: nil, image: nil)
          args = [claude_binary || "claude", "--print", "--model", model_alias, *CLAUDE_CLI_TEXT_ONLY]
          args += ["--system-prompt", sys] if sys && !sys.empty?
          text = text_prompt_for(messages)
          blocks = claude_image_blocks(image)
          return ClaudeRun.new(args:, stdin: text, stream: nil, json: false) if blocks.empty?

          content = [*blocks, { type: "text", text: }]
          stdin = "#{JSON.generate(type: "user", message: { role: "user", content: })}\n"
          ClaudeRun.new(args: args + CLAUDE_IMAGE_FLAGS, stdin:, stream: nil, json: true)
        end

        # A CLI that dies with nothing on either stream taught the operator nothing:
        # the 2026-09-16 /fix printed "claude-cli:" and a blank a hundred and
        # seventy-eight times. `claude --print` from inside a session hangs and is
        # killed, which is exit 124 and two empty streams.
        def claude_cli_failure(out, err, status:)
          said = cli_lane_complaint(out, err) || "exited #{status.exitstatus} with nothing on either stream"
          Result.err("claude-cli: #{said}", category: :provider_error)
        end

        def claude_cli_reply(out, json:)
          reply = out.strip
          return Result.err("claude-cli: #{reply.lines.first.strip}", category: :exhausted) if reply.match?(CLAUDE_CLI_LIMIT)
          return Result.err("claude-cli: no reply on stream-json output", category: :provider_error) if json && reply.empty?

          Result.ok(reply)
        end

        # The lane's own bound, under a /fix run's call cap (PassClock.call_deadline): the child dies by
        # its own bounded wait, and the call fails as a timeout before the stall window closes.

        # Keep the dispatcher-specific timeout contract, but let the sanctioned
        # runner own stream draining, child tracking and process-group cleanup.
        # Exec reads the pipes as bytes. A lane replies in UTF-8 text, and left BINARY its reply broke the
        # first regex that met a non-ASCII letter: the "å" of a Norwegian greeting killed the CLI turn.
        def capture3_with_timeout(timeout_s, *cmd, env: {}, **opts)
          opts.delete(:on_stdout) if opts[:on_stdout].nil?
          timeout_s = PassClock.call_deadline(timeout_s)
          out, err, status = Master::Io::Exec.capture3(env, *cmd, timeout: timeout_s, raise_on_timeout: true, **opts)
          [out.to_s.dup.force_encoding(Encoding::UTF_8).scrub, err.to_s.dup.force_encoding(Encoding::UTF_8).scrub, status]
        rescue Master::Io::Exec::TimeoutError
          raise Timeout::Error
        end

        def claude_cli_timeout_s
          Integer(ENV.fetch("MASTER_CLAUDE_CLI_TIMEOUT", CLAUDE_CLI_TIMEOUT_S.to_s))
        rescue ArgumentError
          CLAUDE_CLI_TIMEOUT_S
        end
      end
    end
  end
end
