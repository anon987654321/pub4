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
      when 'help', '?'
        Help.show(args)
        nil
      when 'status'
        Dashboard.new.render
        nil
      when 'budget'
        show_budget
        nil
      when 'clear'
        print "\e[2J\e[H"
        nil
      when 'history'
        show_history
        nil
      when 'refactor'
        refactor(args)
      when 'chamber'
        chamber(args)
      when 'evolve'
        evolve(args)
      when 'speak', 'say'
        speak(args)
        nil
      when 'exit', 'quit'
        :exit
      else
        # Pass to pipeline
        pipeline.call({ text: input })
      end
    end

    private

    def show_budget
      tier = LLM.tier
      remaining = LLM.remaining
      spent = LLM::BUDGET_LIMIT - remaining
      pct = (spent / LLM::BUDGET_LIMIT * 100).round(1)

      puts "\n  Budget Status"
      puts "  Tier:      #{tier}"
      puts "  Remaining: $#{'%.2f' % remaining}"
      puts "  Spent:     $#{'%.2f' % spent} (#{pct}%)"
      puts
    end

    def show_history
      costs = DB.connection.execute(
        "SELECT model, tokens_in, tokens_out, cost, created_at FROM costs ORDER BY id DESC LIMIT 10"
      ) rescue []

      if costs.empty?
        puts "\n  No history yet.\n"
      else
        puts "\n  Recent Queries"
        puts "  #{'-' * 50}"
        costs.each do |row|
          model = row['model'].split('/').last[0, 12]
          puts "  #{row['created_at'][0, 16]} | #{model.ljust(12)} | #{row['tokens_in']}→#{row['tokens_out']} | $#{'%.4f' % row['cost']}"
        end
        puts
      end
    end

    def refactor(file)
      return Result.err("Usage: refactor <file>") unless file

      path = File.expand_path(file)
      return Result.err("File not found: #{file}") unless File.exist?(path)

      code = File.read(path)
      chamber = Chamber.new
      result = chamber.deliberate(code, filename: File.basename(path))

      if result.ok? && result.value[:final]
        puts "\n  Proposals: #{result.value[:proposals].size}"
        puts "  Cost: $#{'%.4f' % result.value[:cost]}"
        puts "\n#{result.value[:final]}\n"
      end

      result
    end

    def chamber(file)
      refactor(file) # Same as refactor for now
    end

    def evolve(path)
      path ||= MASTER.root
      evolve = Evolve.new
      result = evolve.run(path: path, dry_run: true)

      puts "\n  Evolution Analysis (dry run)"
      puts "  Files processed: #{result[:files_processed]}"
      puts "  Improvements found: #{result[:improvements]}"
      puts "  Cost: $#{'%.4f' % result[:cost]}"
      puts

      Result.ok(result)
    end

    def speak(text)
      return puts "  Usage: speak <text>" unless text

      result = EdgeTTS.speak_and_play(text)
      if result.err?
        puts "  TTS Error: #{result.error}"
      end
    end
  end
end
