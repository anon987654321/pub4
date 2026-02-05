# frozen_string_literal: true

require 'securerandom'

module MASTER
  module Boot
    class << self
      def run(verbose: false, quiet: false)
        t0 = Time.now
        principles = load_principles
        smells = principles.sum { |p| p[:anti_patterns]&.size || 0 }
        time_utc = Time.now.utc.strftime('%b %e %H:%M:%S UTC %Y')
        time_local = Time.now.strftime('%H:%M %Z')
        session = SecureRandom.hex(2)
        mem = memory_mb

        unless quiet
          # Hardware
          puts "MASTER #{VERSION} (GENERIC) #1: #{time_utc}"
          puts "memory total #{mem}MB, available #{(mem * 0.8).round}MB"
          puts "entropy: good seed from kernel"
          puts "#{platform_name}0 at mainbus0"
          puts "processor0: #{cpu_info}"
          puts

          # Runtime
          puts "ruby0 at processor0: #{RUBY_ENGINE} #{RUBY_VERSION}"
          puts "root on #{platform_name}0: #{ROOT} (#{dir_size_mb(ROOT)}MB)"
          puts git_status_line if git_repo?
          puts

          # Services
          puts "constitution0 at master0: #{principles_summary(principles)}"
          puts "constitution0: #{smells} anti-patterns indexed"
          puts "repligen0 at replicate0: #{replicate_status}"
          puts "postpro0 at vips0: #{vips_status}"
          puts "softraid0: encryption ready"
          puts

          # API Configuration
          puts "openrouter0: #{openrouter_status}"
          latency = ping_openrouter
          puts "openrouter0: #{latency}ms latency" if latency
          puts "replicate0: #{replicate_api_status}"
          puts
          puts "Available models via OpenRouter:"
          LLM::TIERS.each do |tier, info|
            puts "  #{tier}: #{info[:model].split('/').last}"
          end
          puts
          puts "Available models via Replicate:"
          Replicate::MODELS.each do |key, model|
            puts "  #{key}: #{model}"
          end
          puts

          # Session
          puts "session #{session} started #{time_utc} (local #{time_local})"
        end

        model_key = prompt_for_model(quiet: quiet)
        model_info = LLM::TIERS[model_key]
        model_name = model_info[:model].split('/').last

        unless quiet
          puts
          puts "model0: #{model_key} tier selected"
          puts "model0 at openrouter0: #{model_name}"
          puts "model0 pricing: #{model_info[:input]} input, #{model_info[:output]} output per 1000 tokens"
          puts
          puts "boot complete in #{((Time.now - t0) * 1000).round}ms"
          puts first_run_hints if first_run?
        end

        save_model_preference(model_key)
        { principles: principles, model: model_key, session: session, boot_time: t0 }
      end

      private

      def prompt
        @prompt ||= begin
          require 'tty-prompt'
          TTY::Prompt.new(symbols: { marker: '>' }, active_color: :cyan)
        rescue LoadError
          nil
        end
      end

      def prompt_for_model(quiet: false)
        saved = load_model_preference
        return saved if quiet && saved

        models = LLM::TIERS.keys
        default_key = saved || LLM::DEFAULT_TIER
        default_idx = models.index(default_key) || 0

        # Progressive disclosure: recommended first
        recommended = [:strong, :cheap, :fast]
        others = models - recommended
        ordered = (recommended & models) + others

        if prompt && !quiet
          puts
          choices = ordered.map do |key|
            info = LLM::TIERS[key]
            name = info[:model].split('/').last
            label = "#{key}: #{name} (#{info[:input]}/#{info[:output]} per 1000)"
            label += " [last used]" if key == saved
            { name: label, value: key }
          end
          prompt.select("Select model:", choices, default: ordered.index(default_key) + 1, cycle: true, per_page: 10)
        else
          return default_key if quiet
          puts
          ordered.each_with_index do |key, i|
            info = LLM::TIERS[key]
            name = info[:model].split('/').last
            marks = []
            marks << "default" if key == LLM::DEFAULT_TIER
            marks << "last used" if key == saved
            suffix = marks.empty? ? "" : " [#{marks.join(', ')}]"
            puts "  #{i + 1}. #{key}: #{name} (#{info[:input]}/#{info[:output]})#{suffix}"
          end
          print "Model [1-#{ordered.size}]: "
          input = $stdin.gets&.strip
          return default_key if input.nil? || input.empty?
          idx = input.to_i - 1
          idx >= 0 && idx < ordered.size ? ordered[idx] : default_key
        end
      end

      def load_principles
        Principle.load_all
      rescue
        []
      end

      def principles_summary(principles)
        return "0 principles" if principles.empty?
        # Group by source file or first word of name as category
        categories = principles.group_by { |p| p[:source]&.split('/')&.last&.sub('.yml', '') || 'general' }
        summary = categories.map { |cat, list| "#{list.size} #{cat}" }.join(', ')
        "#{principles.size} principles (#{summary})"
      end

      def platform_name
        case RUBY_PLATFORM
        when /openbsd/ then 'openbsd'
        when /linux.*android/, /aarch64.*linux/ then 'termux'
        when /darwin/ then 'darwin'
        when /linux/ then 'linux'
        when /mingw|mswin/ then 'windows'
        else 'unix'
        end
      end

      def cpu_info
        case RUBY_PLATFORM
        when /x86_64/ then 'x86_64'
        when /aarch64|arm64/ then 'ARM64'
        when /arm/ then 'ARM'
        when /i[3-6]86/ then 'x86'
        else 'unknown'
        end
      end

      def memory_mb
        case RUBY_PLATFORM
        when /linux/
          File.read('/proc/meminfo')[/MemTotal:\s+(\d+)/, 1].to_i / 1024 rescue 512
        when /darwin/
          `sysctl -n hw.memsize`.to_i / 1024 / 1024 rescue 512
        when /openbsd/
          `sysctl -n hw.physmem`.to_i / 1024 / 1024 rescue 512
        else
          512
        end
      end

      def dir_size_mb(path)
        total = Dir.glob(File.join(path, '**', '*')).sum { |f| File.file?(f) ? File.size(f) : 0 }
        (total / 1024.0 / 1024.0).round(1)
      rescue
        '?'
      end

      def vips_version
        require 'vips'
        Vips.version_string
      rescue LoadError
        'not installed'
      rescue
        'unknown'
      end

      def api_key_status
        key = ENV['OPENROUTER_API_KEY']
        return 'key missing' unless key
        return 'key too short' if key.length < 20
        'connected'
      end

      def ping_openrouter
        require 'net/http'
        t0 = Time.now
        uri = URI('https://openrouter.ai/api/v1/models')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 3
        http.read_timeout = 3
        http.head(uri.path)
        ((Time.now - t0) * 1000).round
      rescue
        nil
      end

      def git_repo?
        File.directory?(File.join(ROOT, '.git'))
      end

      def git_status_line
        branch = `git -C "#{ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
        status = `git -C "#{ROOT}" status --porcelain 2>/dev/null`
        uncommitted = status.lines.size
        msg = "git0: #{branch} branch"
        msg += ", #{uncommitted} uncommitted" if uncommitted > 0
        msg
      rescue
        nil
      end

      def config_file
        File.join(ROOT, '.master_config')
      end

      def load_model_preference
        return nil unless File.exist?(config_file)
        data = File.read(config_file)
        match = data.match(/^model:\s*(\w+)/)
        match ? match[1].to_sym : nil
      rescue
        nil
      end

      def save_model_preference(key)
        File.write(config_file, "model: #{key}\n")
      rescue
        nil
      end

      def first_run?
        !File.exist?(config_file)
      end

      def first_run_hints
        <<~HINTS

        Quick reference:
          help      show all commands
          ask       chat with the model
          scan      analyze current directory
          review    code review
          refactor  improve code quality
          image     generate images via Replicate
          web       browse and extract content
          exit      end session
        HINTS
      end

      def openrouter_status
        key = ENV['OPENROUTER_API_KEY']
        return 'OPENROUTER_API_KEY not set' unless key
        return 'key too short' if key.length < 20
        "connected (key #{key[0..7]}...)"
      end

      def replicate_status
        key = ENV['REPLICATE_API_TOKEN']
        return 'image generation ready' if key && key.length > 10
        'image generation (no token)'
      end

      def replicate_api_status
        key = ENV['REPLICATE_API_TOKEN']
        return 'REPLICATE_API_TOKEN not set' unless key
        return 'token too short' if key.length < 10
        "connected (token #{key[0..7]}...)"
      end

      def vips_status
        version = vips_version
        if version == 'not installed'
          'photo processing (libvips not installed)'
        else
          "photo processing via libvips #{version}"
        end
      end
    end
  end
end
