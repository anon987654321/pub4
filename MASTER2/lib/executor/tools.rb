# frozen_string_literal: true

require "fileutils"
require "open3"
require "timeout"
require "shellwords"

module Executor
  module Tools
    TOOL_DISPATCH = {
      "file_write" => :file_write,
      "file_edit_lines" => :file_edit_lines,
      "shell_command" => :shell_command,
      "code_execution" => :code_execution,
      "fix_code" => :fix_code,
      "verify_change" => :verify_change
    }.freeze

    DEFAULT_SHELL_TIMEOUT = 30
    DEFAULT_CODE_TIMEOUT = 30
    MAX_CAPTURED_OUTPUT_BYTES = 200_000
    STRING_PREVIEW_BYTES = 2_000
    DEFAULT_PERMISSIONS = 0o644

    module_function

    def dispatch_action(tool_action)
      tool_name = tool_action&.fetch("tool", nil) || tool_action&.fetch(:tool, nil)
      return error_result("missing_tool") unless tool_name

      method_name = TOOL_DISPATCH[tool_name.to_s]
      return error_result("unknown_tool", tool: tool_name) unless method_name

      arguments = tool_action.fetch("args", tool_action.fetch(:args, {}))
      return error_result("invalid_args", tool: tool_name) unless arguments.is_a?(Hash)

      public_send(method_name, **symbolize_keys(arguments))
    rescue KeyError => e
      error_result("missing_required_key", message: e.message, tool: tool_name)
    end

    def file_write(path:, content:, mode: "overwrite", permissions: DEFAULT_PERMISSIONS)
      normalized_path = normalize_path(path)
      return error_result("missing_path") if normalized_path.nil? || normalized_path.empty?

      content_string = content.to_s
      parent_dir = File.dirname(normalized_path)
      FileUtils.mkdir_p(parent_dir) unless parent_dir == "."

      write_mode = mode.to_s
      return error_result("invalid_mode", mode: write_mode) unless %w[overwrite append].include?(write_mode)

      bytes_written =
        if write_mode == "append"
          File.open(normalized_path, "ab") { |f| f.write(content_string) }
        else
          File.open(normalized_path, "wb") { |f| f.write(content_string) }
        end

      File.chmod(permissions, normalized_path) if permissions

      ok_result(
        path: normalized_path,
        mode: write_mode,
        bytes_written: bytes_written,
        preview: content_string.byteslice(0, STRING_PREVIEW_BYTES)
      )
    rescue Errno::EACCES, Errno::ENOENT, Errno::ENOTDIR, Errno::EISDIR => e
      error_result("file_write_failed", path: path, message: e.message)
    end

    def file_edit_lines(path:, edits:)
      normalized_path = normalize_path(path)
      return error_result("missing_path") if normalized_path.nil? || normalized_path.empty?
      return error_result("invalid_edits") unless edits.is_a?(Array) && edits.all?(Hash)

      original_lines = File.exist?(normalized_path) ? File.read(normalized_path).lines : []
      updated_lines = apply_line_edits(original_lines, edits)

      FileUtils.mkdir_p(File.dirname(normalized_path))
      File.open(normalized_path, "wb") { |f| f.write(updated_lines.join) }

      ok_result(
        path: normalized_path,
        original_line_count: original_lines.length,
        updated_line_count: updated_lines.length
      )
    rescue Errno::EACCES, Errno::ENOENT, Errno::ENOTDIR, Errno::EISDIR => e
      error_result("file_edit_failed", path: path, message: e.message)
    end

    def shell_command(command:, cwd: nil, env: {}, timeout: DEFAULT_SHELL_TIMEOUT)
      return error_result("missing_command") if command.to_s.strip.empty?

      result = run_command(command, cwd: cwd, env: env, timeout: timeout)
      ok_result(result)
    rescue Timeout::Error
      error_result("command_timeout", command: command.to_s, timeout: timeout.to_i)
    rescue Errno::ENOENT => e
      error_result("command_not_found", command: command.to_s, message: e.message)
    rescue StandardError => e
      error_result("command_failed", command: command.to_s, message: e.message)
    end

    def code_execution(language:, code:, timeout: DEFAULT_CODE_TIMEOUT, cwd: nil, env: {})
      language_name = language.to_s.downcase
      return error_result("unsupported_language", language: language_name) unless language_name == "ruby"

      ruby_code = code.to_s
      return error_result("missing_code") if ruby_code.strip.empty?

      command = [RbConfig.ruby, "-e", ruby_code]
      result = run_command(command, cwd: cwd, env: env, timeout: timeout)

      ok_result(result.merge(language: language_name))
    rescue Timeout::Error
      error_result("code_timeout", language: language.to_s, timeout: timeout.to_i)
    rescue StandardError => e
      error_result("code_execution_failed", language: language.to_s, message: e.message)
    end

    def fix_code(command: "bundle exec rubocop -A", cwd: nil, env: {}, timeout: DEFAULT_SHELL_TIMEOUT)
      result = run_command(command, cwd: cwd, env: env, timeout: timeout)
      ok_result(result.merge(tool: "fix_code"))
    rescue Timeout::Error
      error_result("fix_code_timeout", timeout: timeout.to_i)
    rescue StandardError => e
      error_result("fix_code_failed", message: e.message)
    end

    def verify_change(path:, expected_includes: nil, expected_excludes: nil)
      normalized_path = normalize_path(path)
      return error_result("missing_path") if normalized_path.nil? || normalized_path.empty?
      return error_result("file_not_found", path: normalized_path) unless File.exist?(normalized_path)

      content = File.read(normalized_path)

      includes_ok = expected_includes.nil? || content.include?(expected_includes.to_s)
      excludes_ok = expected_excludes.nil? || !content.include?(expected_excludes.to_s)

      return ok_result(path: normalized_path, verified: true) if includes_ok && excludes_ok

      error_result(
        "verification_failed",
        path: normalized_path,
        includes_ok: includes_ok,
        excludes_ok: excludes_ok
      )
    rescue Errno::EACCES => e
      error_result("verify_failed", path: path, message: e.message)
    end

    def normalize_path(path)
      raw_path = path.to_s
      return nil if raw_path.strip.empty?

      File.expand_path(raw_path)
    end
    private_class_method :normalize_path

    def run_command(command, cwd:, env:, timeout:)
      cmd = command.is_a?(Array) ? command : Shellwords.split(command.to_s)
      working_dir = cwd.to_s.strip.empty? ? nil : cwd.to_s

      Timeout.timeout(timeout.to_i) do
        stdout_str = +""
        stderr_str = +""
        status = nil

        Open3.popen3(env.transform_keys(&:to_s), *cmd, chdir: working_dir) do |stdin, stdout, stderr, wait_thr|
          stdin.close

          stdout_reader = Thread.new { stdout.read }
          stderr_reader = Thread.new { stderr.read }

          stdout_str = stdout_reader.value.to_s
          stderr_str = stderr_reader.value.to_s
          status = wait_thr.value
        end

        {
          command: cmd,
          cwd: working_dir,
          exit_status: status&.exitstatus,
          success: status&.success? || false,
          stdout: stdout_str.byteslice(0, MAX_CAPTURED_OUTPUT_BYTES),
          stderr: stderr_str.byteslice(0, MAX_CAPTURED_OUTPUT_BYTES)
        }
      end
    end
    private_class_method :run_command

    def apply_line_edits(original_lines, edits)
      edits_sorted = edits.map { |e| symbolize_keys(e) }.sort_by { |e| (e[:start_line] || 1).to_i }
      updated = original_lines.dup

      edits_sorted.reverse_each do |edit|
        start_line = (edit[:start_line] || 1).to_i
        end_line = (edit[:end_line] || start_line).to_i
        replacement = Array(edit[:replacement]).join

        start_index = [start_line - 1, 0].max
        end_index = [end_line - 1, start_index].max
        count = end_index - start_index + 1

        updated[start_index, count] = replacement.empty? ? [] : replacement.lines
      end

      updated
    end
    private_class_method :apply_line_edits

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(k, v), out|
        out[k.to_sym] = v
      end
    end
    private_class_method :symbolize_keys

    def ok_result(payload = {})
      { ok: true, **payload }
    end
    private_class_method :ok_result

    def error_result(code, payload = {})
      { ok: false, error: code, **payload }
    end
    private_class_method :error_result
  end
end