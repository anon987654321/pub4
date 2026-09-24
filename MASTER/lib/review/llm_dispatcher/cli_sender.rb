# frozen_string_literal: true

require "open3"
require "tempfile"
require "timeout"

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
          Result.err("#{name}: timed out after #{CLI_LANE_TIMEOUT_S}s", category: :timeout)
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
  Result.err("agy: timed out after #{timeout_s}s", category: :timeout)
rescue StandardError => e
  Result.err("agy: #{e.message}", category: :provider_error)
end

      def find_agy_bin
        if ENV["AGY_BIN"] && File.file?(ENV["AGY_BIN"]) && File.executable?(ENV["AGY_BIN"])
          return ENV["AGY_BIN"]
        end
        home_bin = File.expand_path("~/.local/bin/agy")
        return home_bin if File.file?(home_bin) && File.executable?(home_bin)

        ENV["PATH"].to_s.split(File::PATH_SEPARATOR).each do |dir|
          candidate = File.join(dir, "agy")
          return candidate if File.file?(candidate) && File.executable?(candidate)
        end
        nil
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
      CLI_SLOTS = SizedQueue.new(2).tap { |queue| 2.times { queue << true } }

def send_claude_cli(model_alias, messages, sys:)
  return Result.err("claude-cli: no claude on PATH", category: :no_api_key) unless claude_on_path?

  with_cli_slot { claude_cli_call(model_alias, messages, sys) }
end

# The same reading of PATH that ModelRouter uses to keep an absent lane
# out of a chain, here so a dispatch reached any other way refuses too.
# MASTER_NO_CLAUDE_CLI=1 takes the lane out on a box that has the binary.
def claude_on_path?
  return false if ENV["MASTER_NO_CLAUDE_CLI"] == "1"
  return @claude_on_path unless @claude_on_path.nil?

  @claude_on_path = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
    exe = File.join(dir, "claude")
    File.file?(exe) && File.executable?(exe)
  end
end

# These two mark the parent as a Claude Code session, and a `claude --print`
# that inherits them from one hangs until killed; unset, it answers in about
# five seconds (measured 2026-09-24 from inside a session). Only these two:
# CLAUDE_CODE_OAUTH_TOKEN and the other CLAUDE_* names can carry the login.
CLAUDE_SESSION_ENV = { "CLAUDECODE" => nil, "CLAUDE_CODE_ENTRYPOINT" => nil }.freeze

# A lane answers in text and nothing else. Left its tools, `claude --print`
# edited files and ran git inside the /fix worktree on its own: it committed
# twice there, past the verifier, the proof and the pass transaction. No
# built-in tool and no MCP server; the dispatcher's caller does the writing.
CLAUDE_CLI_TEXT_ONLY = ["--tools", "", "--strict-mcp-config"].freeze

def claude_cli_call(model_alias, messages, sys)
  args = ["claude", "--print", "--model", model_alias, *CLAUDE_CLI_TEXT_ONLY]
  args += ["--system-prompt", sys] if sys && !sys.empty?
  timeout_s = claude_cli_timeout_s
  out, err, status = capture3_with_timeout(timeout_s, *args, stdin_data: text_prompt_for(messages), env: CLAUDE_SESSION_ENV)
  # A CLI that dies with nothing on either stream taught the operator nothing:
  # the 2026-09-16 /fix printed "claude-cli:" and a blank a hundred and
  # seventy-eight times. `claude --print` from inside a session hangs and is
  # killed, which is exit 124 and two empty streams.
  unless status.success?
    said = cli_lane_complaint(out, err) || "exited #{status.exitstatus} with nothing on either stream"
    return Result.err("claude-cli: #{said}", category: :provider_error)
  end

  Result.ok(out.strip)
rescue Timeout::Error
  Result.err("claude-cli: timed out after #{timeout_s}s", category: :timeout)
rescue StandardError => e
  Result.err("claude-cli: #{e.message}", category: :provider_error)
end

      def capture3_with_timeout(timeout_s, *cmd, stdin_data: nil, env: {})
        Open3.popen3(env, *cmd) do |stdin, stdout, stderr, wait_thr|
          stdin.write(stdin_data) if stdin_data
          stdin.close
          out_reader = Thread.new { stdout.read }
          err_reader = Thread.new { stderr.read }
          if wait_thr.join(timeout_s)
            [out_reader.value, err_reader.value, wait_thr.value]
          else
            terminate_subprocess(wait_thr)
            # Kill the readers before closing what they are reading. Closing
            # first left both threads inside IO#read on a closed handle, so each
            # terminated with "stream closed in another thread" and
            # report_on_exception printed a backtrace over the operator's
            # prompt — twice, on every timeout.
            [out_reader, err_reader].each { |reader| reader.kill.join }
            [stdout, stderr].each { |io| io.close unless io.closed? }
            raise Timeout::Error
          end
        end
      end

      def terminate_subprocess(wait_thr)
        return unless signal_process(wait_thr, "TERM")
        return if wait_thr.join(0.5)
        signal_process(wait_thr, "KILL", log_context: "LLMDispatcher.terminate_subprocess")
      end

      def signal_process(wait_thr, signal, log_context: nil)
        Process.kill(signal, wait_thr.pid)
        true
      rescue Errno::ESRCH => e
        Master::Ground::Swallow.log(e, context: log_context) if log_context
        false
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
