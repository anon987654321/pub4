# frozen_string_literal: true

module MASTER
  # Commands - REPL command dispatcher
  module Commands
    extend self

    def dispatch(input, pipeline:)
      parts = input.strip.split(/\s+/, 2)
      cmd = parts[0]&.downcase
      args = parts[1]

      case cmd
      when "help", "?"
        Help.show(args)
        nil
      when "status"
        Dashboard.new.render
        nil
      when "budget"
        show_budget
        nil
      when "clear"
        print "\e[2J\e[H"
        nil
      when "history"
        show_history
        nil
      when "refactor"
        refactor(args)
      when "chamber"
        chamber(args)
      when "evolve"
        evolve(args)
      when "speak", "say"
        speak(args)
        nil
      when "exit", "quit"
        :exit
      else
        pipeline.call({ text: input })
      end
    end

    class << self
      private

      def show_budget
        tier = LLM.tier
        remaining = LLM.remaining
        spent = LLM::BUDGET_LIMIT - remaining
        pct = (spent / LLM::BUDGET_LIMIT * 100).round(1)

        puts "\n  Budget Status"
        puts "  Tier:      #{tier}"
        puts "  Remaining: $#{format('%.2f', remaining)}"
        puts "  Spent:     $#{format('%.2f', spent)} (#{pct}%)"
        puts
      end

      def show_history
        costs = DB.recent_costs(limit: 10)

        if costs.empty?
          puts "\n  No history yet.\n"
        else
          puts "\n  Recent Queries"
          puts "  #{'-' * 50}"
          costs.each do |row|
            model = (row["model"] || row[:model]).split("/").last[0, 12]
            tokens_in = row["tokens_in"] || row[:tokens_in]
            tokens_out = row["tokens_out"] || row[:tokens_out]
            cost = row["cost"] || row[:cost]
            created = row["created_at"] || row[:created_at]
            puts "  #{created[0, 16]} | #{model.ljust(12)} | #{tokens_in}→#{tokens_out} | $#{format('%.4f', cost)}"
          end
          puts
        end
      end

      def refactor(file)
        return Result.err("Usage: refactor <file>") unless file

        path = File.expand_path(file)
        return Result.err("File not found: #{file}") unless File.exist?(path)

        code = File.read(path)
        chamber_instance = Chamber.new
        result = chamber_instance.deliberate(code, filename: File.basename(path))

        if result.ok? && result.value[:final]
          puts "\n  Proposals: #{result.value[:proposals].size}"
          puts "  Cost: $#{format('%.4f', result.value[:cost])}"
          puts "\n#{result.value[:final]}\n"
        end

        result
      end

      def chamber(file)
        refactor(file)
      end

      def evolve(path)
        path ||= MASTER.root
        evolve_instance = Evolve.new
        result = evolve_instance.run(path: path, dry_run: true)

        puts "\n  Evolution Analysis (dry run)"
        puts "  Files processed: #{result[:files_processed]}"
        puts "  Improvements found: #{result[:improvements]}"
        puts "  Cost: $#{format('%.4f', result[:cost])}"
        puts

        Result.ok(result)
      end

      def speak(text)
        return puts "  Usage: speak <text>" unless text

        result = EdgeTTS.speak_and_play(text)
        puts "  TTS Error: #{result.error}" if result.err?
      end
    end
  end
end
