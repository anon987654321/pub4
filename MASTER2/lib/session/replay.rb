# frozen_string_literal: true

module MASTER
  # SessionReplay - Render conversation timelines with cost annotations and diffs
  # Enables auditing of self-runs and refactoring sessions
  module SessionReplay
    extend self

    # Replay a session by ID
    def replay(session_id, format: :terminal)
      data = Memory.load_session(session_id)
      return Result.err("Session not found: #{session_id}") unless data

      history = data[:history] || []
      return Result.err("Empty session.") if history.empty?

      case format
      when :terminal
        render_terminal(data, history)
      when :json
        render_json(data, history)
      when :markdown
        render_markdown(data, history)
      else
        Result.err("Unknown format: #{format}")
      end
    end

    # List sessions with summary info
    def list_with_summaries(limit: 20)
      sessions = Memory.list_sessions
      return Result.ok([]) if sessions.empty?

      summaries = sessions.last(limit).map do |id|
        data = Memory.load_session(id)
        next unless data

        history = data[:history] || []
        {
          id: id,
          short_id: UI.truncate_id(id),
          messages: history.size,
          cost: history.sum { |h| h[:cost] || 0 },
          created_at: data[:created_at],
          duration: calculate_duration(history),
          has_diffs: history.any? { |h| h.dig(:metadata, :contains_diff) || h[:type] == :diff },
          crashed: data.dig(:metadata, :crashed) || false,
          metadata: data[:metadata] || {}
        }
      end.compact

      Result.ok(summaries)
    end

    # Diff two sessions
    def diff_sessions(id_a, id_b)
      data_a = Memory.load_session(id_a)
      data_b = Memory.load_session(id_b)

      return Result.err("Session A not found: #{id_a}") unless data_a
      return Result.err("Session B not found: #{id_b}") unless data_b

      diff = {
        session_a: { id: id_a, messages: (data_a[:history] || []).size },
        session_b: { id: id_b, messages: (data_b[:history] || []).size },
        cost_diff: (data_b[:history] || []).sum { |h| h[:cost] || 0 } -
                   (data_a[:history] || []).sum { |h| h[:cost] || 0 },
      }

      Result.ok(diff)
    end

    private

    def render_terminal(data, history)
      output = []
      output << UI.bold("Session Replay: #{UI.truncate_id(data[:id])}")
      output << UI.dim("Created: #{data[:created_at]}")
      output << UI.dim("Messages: #{history.size}")
      output << ""

      total_cost = 0.0
      history.each_with_index do |msg, idx|
        role = (msg[:role] || "unknown").to_s
        content = msg[:content] || ""
        cost = msg[:cost] || 0
        model = msg[:model]
        timestamp = msg[:timestamp]
        total_cost += cost

        # Role indicator
        role_prefix = case role
                      when "user"
                        UI.cyan("> USER")
                      when "assistant"
                        UI.green("< ASSISTANT")
                      when "system"
                        UI.yellow("SYSTEM")
                      else
                        UI.dim("? #{role.upcase}")
                      end

        # Turn header
        turn_info = ["##{idx + 1}", role_prefix]
        turn_info << UI.dim("[#{model.split('/').last}]") if model
        turn_info << UI.dim(UI.currency_precise(cost)) if cost > 0
        turn_info << UI.dim(timestamp.to_s[11, 8]) if timestamp

        output << turn_info.join(" ")

        # Content (truncated for terminal display)
        preview = content.length > 500 ? content[0, 500] + "\n  #{UI.dim('... (truncated)')}" : content
        preview.each_line do |line|
          output << "  #{line.rstrip}"
        end

        output << ""
      end

      # Summary footer
      output << UI.bold("-" * 40)
      output << "  Total cost: #{UI.currency_precise(total_cost)}"
      output << "  Messages: #{history.size}"
      output << "  Duration: #{calculate_duration(history)}"

      puts output.join("\n")
      Result.ok(messages: history.size, cost: total_cost)
    end

    def render_json(data, history)
      Result.ok(data)
    end

    def render_markdown(data, history)
      lines = ["# Session #{UI.truncate_id(data[:id])}", ""]
      lines << "**Created:** #{data[:created_at]}"
      lines << "**Messages:** #{history.size}"
      lines << ""

      history.each_with_index do |msg, idx|
        role = (msg[:role] || "unknown").to_s
        content = msg[:content] || ""
        cost = msg[:cost]

        lines << "## Turn #{idx + 1} (#{role})"
        lines << "#{content}"
        lines << "*Cost: #{UI.currency_precise(cost)}*" if cost && cost > 0
        lines << ""
      end

      Result.ok(lines.join("\n"))
    end

    def calculate_duration(history)
      return "unknown" if history.empty?

      timestamps = history.map { |h| begin; Time.parse(h[:timestamp]); rescue ArgumentError, TypeError; nil; end }.compact
      return "unknown" if timestamps.size < 2

      seconds = (timestamps.last - timestamps.first).to_i
      if seconds > 3600
        "#{seconds / 3600}h #{(seconds % 3600) / 60}m"
      elsif seconds > 60
        "#{seconds / 60}m #{seconds % 60}s"
      else
        "#{seconds}s"
      end
    end
  end
end
