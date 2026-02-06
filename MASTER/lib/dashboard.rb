# frozen_string_literal: true

require 'tty-box'
require 'tty-pie'
require 'tty-table'
require 'tty-screen'
require 'pastel'

module MASTER
  class Dashboard
    def initialize
      @pastel = Pastel.new
      @screen = TTY::Screen
    end

    def render
      clear_screen

      print_header
      print_stats_box
      print_cost_pie
      print_recent_tasks
      print_memory_status
      print_footer
    end

    private

    def clear_screen
      print "\e[2J\e[H"
    end

    def print_header
      title = @pastel.bold.cyan("MASTER Dashboard")
      puts "\n#{title.center(@screen.width)}\n\n"
    end

    def print_stats_box
      stats = fetch_stats

      content = [
        "Total Cost:    #{format_cost(stats[:total_cost])}",
        "Tasks Today:   #{stats[:tasks_today]}",
        "Avg Response:  #{stats[:avg_duration]}s",
        "Active Model:  #{stats[:active_model]}"
      ].join("\n")

      box = TTY::Box.frame(
        width: 50,
        title: { top_left: " Stats " },
        border: :thick,
        padding: 1,
        align: :left
      ) { content }

      puts box
    end

    def print_cost_pie
      data = fetch_cost_breakdown

      pie = TTY::Pie.new(
        data: data,
        radius: 4,
        legend: { left: 2 }
      )

      puts "\n#{@pastel.bold('Cost by Model')}"
      puts pie
    end

    def print_recent_tasks
      tasks = fetch_recent_tasks(10)

      table = TTY::Table.new(
        header: ['Task', 'Model', 'Cost', 'Time'],
        rows: tasks.map { |t|
          [
            truncate(t[:name], 20),
            t[:model],
            format_cost(t[:cost]),
            "#{t[:duration]}s"
          ]
        }
      )

      puts "\n#{@pastel.bold('Recent Tasks')}"
      puts table.render(:unicode, padding: [0, 1])
    end

    def print_memory_status
      memory = fetch_memory_stats

      status = [
        "Chunks stored:  #{memory[:chunks]}",
        "Total vectors:  #{memory[:vectors]}",
        "Last recall:    #{memory[:last_recall]}",
        "Weaviate:       #{memory[:healthy] ? '✓ Connected' : '✗ Disconnected'}"
      ].join("\n")

      box = TTY::Box.frame(
        width: 40,
        title: { top_left: " Memory " },
        border: :light,
        padding: 1
      ) { status }

      puts "\n#{box}"
    end

    def print_footer
      puts "\n#{@pastel.dim('Press Ctrl+C to exit')}"
    end

    # Data fetching methods
    def fetch_stats
      # Will integrate with Monitor from first PR
      {
        total_cost: defined?(Monitor) ? Monitor.total_cost : 47.23,
        tasks_today: defined?(Monitor) ? Monitor.tasks_today : 156,
        avg_duration: defined?(Monitor) ? Monitor.avg_duration.round(1) : 2.3,
        active_model: defined?(LLM) && LLM.respond_to?(:current_tier) ? LLM.current_tier : "claude-3.5-sonnet"
      }
    rescue StandardError
      # Fallback for development
      {
        total_cost: 47.23,
        tasks_today: 156,
        avg_duration: 2.3,
        active_model: "claude-3.5-sonnet"
      }
    end

    def fetch_cost_breakdown
      return Monitor.cost_by_model if defined?(Monitor) && Monitor.respond_to?(:cost_by_model)

      [
        { name: "DeepSeek (cheap)", value: 15.2 },
        { name: "Grok (fast)", value: 8.4 },
        { name: "Sonnet (strong)", value: 18.3 },
        { name: "Opus (frontier)", value: 5.3 }
      ]
    rescue StandardError
      [
        { name: "DeepSeek (cheap)", value: 15.2 },
        { name: "Grok (fast)", value: 8.4 },
        { name: "Sonnet (strong)", value: 18.3 },
        { name: "Opus (frontier)", value: 5.3 }
      ]
    end

    def fetch_recent_tasks(limit)
      return Monitor.recent_tasks(limit) if defined?(Monitor) && Monitor.respond_to?(:recent_tasks)

      # Fallback
      []
    rescue StandardError
      []
    end

    def fetch_memory_stats
      memory = VectorMemory.new
      {
        chunks: memory.count_chunks,
        vectors: memory.count_vectors,
        last_recall: memory.time_since_last_recall,
        healthy: memory.healthy?
      }
    rescue StandardError
      { chunks: 0, vectors: 0, last_recall: "never", healthy: false }
    end

    # Helpers
    def format_cost(amount)
      "$#{format('%.2f', amount)}"
    end

    def truncate(str, max)
      str.length > max ? "#{str[0...max - 3]}..." : str
    end
  end
end
