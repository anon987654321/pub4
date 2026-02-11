# frozen_string_literal: true

module MASTER
  # Shell: Modern zsh-inspired command parsing and execution
  # Supports: pipes, chains, globs, subshells, history, aliases
  module Shell
    extend self

    # Expand globs, execute chains, handle pipes
    def parse(input, ctx = {})
      return [] if input.nil? || input.strip.empty?

      # History expansion
      input = expand_history(input, ctx[:history] || [])

      # Split by && (chain) or ; (sequence)
      chains = input.split(/\s*(?:&&|;)\s*/)

      chains.map { |cmd| parse_single(cmd, ctx) }
    end

    def parse_single(cmd, ctx = {})
      # Handle pipes: cmd1 | cmd2 | cmd3
      if cmd.include?('|')
        parts = cmd.split(/\s*\|\s*/)
        return { type: :pipe, commands: parts.map { |p| parse_single(p, ctx) } }
      end

      # Handle subshell: $(cmd)
      cmd = expand_subshells(cmd, ctx)

      # Split into command and args
      tokens = tokenize(cmd)
      return nil if tokens.empty?

      command = tokens.shift
      args = tokens

      # Expand globs in args
      args = args.flat_map { |a| expand_glob(a, ctx[:cwd] || Dir.pwd) }

      { type: :command, cmd: command, args: args, raw: cmd }
    end

    def tokenize(input)
      # Handle quoted strings properly
      tokens = []
      current = ''
      in_quote = nil

      input.each_char do |c|
        if in_quote
          if c == in_quote
            in_quote = nil
          else
            current << c
          end
        elsif c == '"' || c == "'"
          in_quote = c
        elsif c == ' ' || c == "\t"
          tokens << current unless current.empty?
          current = ''
        else
          current << c
        end
      end
      tokens << current unless current.empty?
      tokens
    end

    def expand_glob(pattern, cwd)
      return [pattern] unless pattern.include?('*') || pattern.include?('?')

      full = File.expand_path(pattern, cwd)
      matches = Dir.glob(full)
      matches.empty? ? [pattern] : matches.map { |m| m.sub("#{cwd}/", '') }
    end

    def expand_history(input, history)
      return input if history.empty?

      input
        .gsub('!!', history.last.to_s)                    # !! = last command
        .gsub('!$', history.last.to_s.split.last.to_s)    # !$ = last arg
        .gsub(/!(-?\d+)/) { history[$1.to_i].to_s }       # !n = nth command
        .gsub(/!\?(.+?)\?/) do                            # !?str? = last containing str
          history.reverse.find { |h| h.include?($1) }.to_s
        end
    end

    def expand_subshells(cmd, ctx)
      cmd.gsub(/\$\(([^)]+)\)/) do
        subcmd = $1
        result = execute_single({ cmd: subcmd.split.first, args: subcmd.split[1..], type: :command }, ctx)
        result.to_s.strip
      end
    end

    def execute(parsed, ctx = {})
      results = []
      parsed.each do |p|
        result = execute_single(p, ctx)
        results << result
        break if result.is_a?(Hash) && result[:exit] != 0  # && chain stops on error
      end
      results
    end

    def execute_single(parsed, ctx = {})
      return nil unless parsed

      case parsed[:type]
      when :pipe
        execute_pipe(parsed[:commands], ctx)
      when :command
        execute_command(parsed, ctx)
      end
    end

    def execute_pipe(commands, ctx)
      output = nil
      commands.each do |cmd|
        cmd[:stdin] = output if output
        output = execute_command(cmd, ctx)
      end
      output
    end

    def execute_command(parsed, ctx = {})
      cmd = parsed[:cmd]
      args = parsed[:args] || []
      stdin = parsed[:stdin]

      # Built-in shell commands
      case cmd
      when 'cd'
        dir = args.first || ENV['HOME']
        Dir.chdir(File.expand_path(dir, ctx[:cwd] || Dir.pwd))
        ctx[:cwd] = Dir.pwd
        Dir.pwd
      when 'pwd'
        ctx[:cwd] || Dir.pwd
      when 'echo'
        args.join(' ')
      when 'cat'
        args.map { |f| File.read(File.expand_path(f, ctx[:cwd])) }.join
      when 'ls'
        dir = args.first || ctx[:cwd] || '.'
        Dir.entries(File.expand_path(dir, ctx[:cwd])).reject { |e| e.start_with?('.') }.sort.join("\n")
      when 'head'
        n = args.find { |a| a.start_with?('-') }&.sub('-', '')&.to_i || 10
        files = args.reject { |a| a.start_with?('-') }
        content = stdin || files.map { |f| File.read(File.expand_path(f, ctx[:cwd])) }.join
        content.lines.first(n).join
      when 'tail'
        n = args.find { |a| a.start_with?('-') }&.sub('-', '')&.to_i || 10
        files = args.reject { |a| a.start_with?('-') }
        content = stdin || files.map { |f| File.read(File.expand_path(f, ctx[:cwd])) }.join
        content.lines.last(n).join
      when 'grep'
        pattern = args.shift
        files = args.empty? ? [stdin] : args.map { |f| File.read(File.expand_path(f, ctx[:cwd])) }
        files.map { |f| f.to_s.lines.grep(/#{pattern}/i) }.flatten.join
      when 'wc'
        content = stdin || args.map { |f| File.read(File.expand_path(f, ctx[:cwd])) }.join
        lines = content.lines.size
        words = content.split.size
        chars = content.size
        "#{lines} #{words} #{chars}"
      when 'find'
        dir = args.first || '.'
        pattern = args.find { |a| a.start_with?('-name') }&.then { args[args.index('-name') + 1] } || '*'
        Dir.glob(File.join(File.expand_path(dir, ctx[:cwd]), '**', pattern)).join("\n")
      when 'tree'
        dir = args.first || ctx[:cwd] || '.'
        tree_output(File.expand_path(dir, ctx[:cwd]), 0, 3)
      else
        # Pass to system or return as MASTER command
        { type: :master_command, cmd: cmd, args: args, raw: parsed[:raw] }
      end
    rescue => e
      { error: e.message, exit: 1 }
    end

    def tree_output(dir, depth, max_depth)
      return '' if depth > max_depth

      entries = Dir.entries(dir).reject { |e| e.start_with?('.') }.sort
      entries.map do |e|
        full = File.join(dir, e)
        prefix = '  ' * depth
        if File.directory?(full)
          "#{prefix}#{e}/\n#{tree_output(full, depth + 1, max_depth)}"
        else
          "#{prefix}#{e}"
        end
      end.join("\n")
    end

    # Quick shortcuts
    ALIASES = {
      'll' => 'ls -la',
      'la' => 'ls -a',
      '..' => 'cd ..',
      '...' => 'cd ../..',
      'g' => 'git',
      'gs' => 'git status',
      'gd' => 'git diff',
      'gl' => 'git log --oneline -20',
      'gp' => 'git push',
      'gc' => 'git commit',
      'h' => 'history',
      'c' => 'clear',
      'q' => 'exit'
    }.freeze

    def expand_aliases(input)
      tokens = input.split(/\s+/, 2)
      if ALIASES[tokens.first]
        "#{ALIASES[tokens.first]} #{tokens[1]}".strip
      else
        input
      end
    end
  end
end
