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

        def cli_lanes
          @cli_lanes ||= Master.load_yaml(File.join(Master::ROOT, "data", "models.yml")).fetch("cli_lanes", {})
        end

      def send_agy_cli(model_alias, messages, sys:, stream: false, &blk)
        CLI_SLOTS.pop
        agy_bin = find_agy_bin
        prompt = text_prompt_for(messages)
        full_prompt = sys && !sys.empty? ? "#{sys}\n\n---\n\n#{prompt}" : prompt
        args = [agy_bin, "-p", full_prompt, "--output-format", "text"]
        if model_alias && !model_alias.empty? && model_alias != "auto" && model_alias != "agy"
          args += ["--model", model_alias]
        end
        timeout_s = agy_cli_timeout_s
        out, err, status = capture3_with_timeout(timeout_s, *args)
        return Result.err("agy: #{err.strip}", category: :provider_error) unless status.success?
        res = out.strip
        blk&.call(res) if stream && block_given?
        Result.ok(res)
      rescue Timeout::Error
        Result.err("agy: timed out after #{timeout_s}s", category: :timeout)
      rescue StandardError => e
        Result.err("agy: #{e.message}", category: :provider_error)
      ensure
        CLI_SLOTS << true
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
        "agy"
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
        CLI_SLOTS.pop
        args = ["claude", "--print", "--model", model_alias]
        args += ["--system-prompt", sys] if sys && !sys.empty?
        timeout_s = claude_cli_timeout_s
        out, err, status = capture3_with_timeout(timeout_s, *args, stdin_data: text_prompt_for(messages))
        return Result.err("claude-cli: #{err.strip}", category: :provider_error) unless status.success?
        Result.ok(out.strip)
      rescue Timeout::Error
        Result.err("claude-cli: timed out after #{timeout_s}s", category: :timeout)
      rescue StandardError => e
        Result.err("claude-cli: #{e.message}", category: :provider_error)
      ensure
        CLI_SLOTS << true
      end

      def capture3_with_timeout(timeout_s, *cmd, stdin_data: nil)
        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
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
