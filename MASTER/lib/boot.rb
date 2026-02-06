# frozen_string_literal: true

require 'securerandom'

module MASTER
  module Boot
    CHECKPOINT_MAX_AGE_HOURS = 24

    class << self
      def run(verbose: false, quiet: false)
        # Apply OpenBSD security restrictions on CLI startup (pledge/unveil)
        apply_openbsd_security if RUBY_PLATFORM =~ /openbsd/ && !ENV['MASTER_WEB_MODE']
        
        t0 = Time.now
        principles = load_principles
        smells = principles.sum { |p| p[:anti_patterns]&.size || 0 }
        time_utc = Time.now.utc.strftime('%a %b %e %H:%M:%S %Z %Y')
        session = SecureRandom.hex(2)
        mem = memory_mb
        avail = available_memory_mb

        unless quiet
          # Kernel banner (OpenBSD style)
          puts "#{CODENAME} #{VERSION} (GENERIC) #1: #{time_utc}"
          puts "    root@#{hostname}:#{ROOT}"

          # Mainbus and CPU
          puts "mainbus0 at root"
          puts "cpu0 at mainbus0: #{cpu_model}"
          puts "cpu0: #{cpu_features}" if verbose

          # Platform
          puts "#{platform_name}0 at mainbus0"

          # Ruby runtime as a device
          puts "ruby0 at #{platform_name}0: #{RUBY_ENGINE} #{RUBY_VERSION}"

          # Storage
          puts "softraid0 at root"
          puts "root on #{root_device}, #{dir_size_mb(ROOT)}MB"

          # Git as version control device
          if git_repo?
            branch, uncommitted = git_info
            puts "vcs0 at root: git, branch #{branch}, #{uncommitted} modified"
          end

          # Constitutional AI subsystem
          puts "const0 at mainbus0: constitutional ai, #{principles.size} principles, #{smells} anti-patterns"

          # LLM interface
          if openrouter_connected?
            latency = ping_openrouter
            tier_count = LLM::TIERS.size
            puts "llm0 at const0: openrouter, #{latency}ms, #{tier_count} tiers"
          else
            puts "llm0 at const0: openrouter (not connected)"
          end

          # Replicate
          if replicate_connected?
            model_count = Replicate::MODELS.size
            chain_count = defined?(Replicate::CHAINS) ? Replicate::CHAINS.size : 0
            puts "repligen0 at mainbus0: replicate, #{model_count} models, #{chain_count} chains"
          end

          # Image processing
          vips = vips_version
          puts "vips0 at mainbus0: libvips #{vips}" if vips != 'not installed'
          
          # Weaviate vector database
          if weaviate_connected?
            puts "weaviate0 at mainbus0: vector db, semantic memory"
          end

          # Scrutiny mode
          puts "scrutiny0 at const0: maximum, brutal honesty"
          puts "boot device: #{ROOT}"
          
          # Auto-install missing dependencies on first run
          check_dependencies(verbose) if first_run?
        end

        model_key = prompt_for_model(quiet: quiet)
        model_info = LLM::TIERS[model_key]
        model_name = model_info[:model].split('/').last

        unless quiet
          puts
          puts "llm0: #{model_key} tier, #{model_name}"
          boot_ms = ((Time.now - t0) * 1000).round
          puts "#{CODENAME}: boot complete, #{boot_ms}ms"
          puts first_run_hints if first_run?
        end

        save_model_preference(model_key)
        
        # Auto-resume last session if available
        recovered = try_auto_resume(quiet: quiet)
        
        { principles: principles, model: model_key, session: session, boot_time: t0, recovered: recovered }
      end

      def save_preferred_model(key)
        save_model_preference(key)
      end

      private

      def try_auto_resume(quiet: false)
        recovery = SessionRecovery.new
        checkpoint = recovery.latest
        return nil unless checkpoint
        
        age_hours = (Time.now.to_i - checkpoint[:timestamp]) / 3600.0
        return nil if age_hours > CHECKPOINT_MAX_AGE_HOURS
        
        unless quiet
          puts "session0: recovering from checkpoint (#{age_hours.round(1)}h ago)"
          puts "  task: #{checkpoint[:task]}"
          pending = checkpoint.dig(:files, :pending)&.size || 0
          completed = checkpoint.dig(:files, :completed)&.size || 0
          puts "  progress: #{completed} done, #{pending} pending" if pending > 0 || completed > 0
        end
        
        checkpoint
      rescue => e
        warn "session0: recovery failed: #{e.message}" unless quiet
        nil
      end

      def hostname
        `hostname`.strip rescue 'localhost'
      end

      def cpu_model
        case RUBY_PLATFORM
        when /darwin/
          `sysctl -n machdep.cpu.brand_string`.strip rescue cpu_arch
        when /linux/
          File.read('/proc/cpuinfo')[/model name\s*:\s*(.+)/, 1] rescue cpu_arch
        when /openbsd/
          `sysctl -n hw.model`.strip rescue cpu_arch
        else
          cpu_arch
        end
      end

      def cpu_arch
        case RUBY_PLATFORM
        when /x86_64/ then 'x86_64'
        when /aarch64|arm64/ then 'ARM64'
        when /arm/ then 'ARM'
        when /i[3-6]86/ then 'i386'
        else 'unknown'
        end
      end

      def cpu_features
        case RUBY_PLATFORM
        when /linux/
          flags = File.read('/proc/cpuinfo')[/flags\s*:\s*(.+)/, 1]
          flags&.split&.first(8)&.join(',') || ''
        else
          ''
        end
      rescue StandardError
        ''
      end

      def root_device
        case RUBY_PLATFORM
        when /openbsd/ then 'sd0a'
        when /darwin/ then 'disk0s2'
        when /linux/ then 'sda1'
        else 'wd0a'
        end
      end

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
        return saved if saved  # Skip prompt if already set

        models = LLM::TIERS.keys
        default_key = LLM::DEFAULT_TIER

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
            { name: label, value: key }
          end
          prompt.select("Select model:", choices, default: ordered.index(default_key) + 1, cycle: true, per_page: 10)
        else
          return default_key if quiet
          puts
          ordered.each_with_index do |key, i|
            info = LLM::TIERS[key]
            name = info[:model].split('/').last
            suffix = key == LLM::DEFAULT_TIER ? " [default]" : ""
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
      rescue StandardError
        []
      end

      def category_summary(principles)
        return nil if principles.empty?
        categories = principles.group_by { |p| p[:source]&.split('/')&.last&.sub('.yml', '') || 'general' }
        categories.map { |cat, list| "#{list.size} #{cat}" }.join(', ')
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

      def available_memory_mb
        case RUBY_PLATFORM
        when /linux/
          File.read('/proc/meminfo')[/MemAvailable:\s+(\d+)/, 1].to_i / 1024 rescue (memory_mb * 0.8).round
        when /darwin/, /openbsd/
          (memory_mb * 0.8).round
        else
          (memory_mb * 0.8).round
        end
      end

      def dir_size_mb(path)
        total = Dir.glob(File.join(path, '**', '*')).sum { |f| File.file?(f) ? File.size(f) : 0 }
        (total / 1024.0 / 1024.0).round(1)
      rescue StandardError
        '?'
      end

      def vips_version
        require 'vips'
        Vips.version_string
      rescue LoadError
        'not installed'
      rescue StandardError
        'unknown'
      end

      def openrouter_connected?
        key = ENV['OPENROUTER_API_KEY']
        key && key.length >= 20
      end

      def replicate_connected?
        key = ENV['REPLICATE_API_TOKEN']
        key && key.length >= 10
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
      rescue StandardError
        nil
      end

      def git_repo?
        File.directory?(File.join(ROOT, '.git'))
      end

      def weaviate_connected?
        require_relative 'weaviate'
        Weaviate.new.healthy?
      rescue StandardError
        false
      end

      def git_info
        branch = `git -C "#{ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
        status = `git -C "#{ROOT}" status --porcelain 2>/dev/null`
        uncommitted = status.lines.size
        [branch, uncommitted]
      rescue StandardError
        ['unknown', 0]
      end

      def config_file
        File.join(ROOT, '.master_config')
      end

      def load_model_preference
        return nil unless File.exist?(config_file)
        data = File.read(config_file)
        match = data.match(/^model:\s*(\w+)/)
        match ? match[1].to_sym : nil
      rescue StandardError
        nil
      end

      def save_model_preference(key)
        File.write(config_file, "model: #{key}\n")
      rescue StandardError
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
          refactor  improve code quality
          chamber   multi-model deliberation
          install   auto-install dependencies
          exit      end session
        HINTS
      end

      def check_dependencies(verbose = false)
        require_relative 'auto_install'
        missing = AutoInstall.missing
        total_missing = missing[:packages].size + missing[:gems].size + missing[:repos].size
        
        # Setup shell environment
        AutoInstall.setup_shell(verbose: verbose)
        
        return if total_missing == 0
        
        puts "deps0: #{total_missing} missing dependencies" if verbose
        
        # Auto-install on OpenBSD
        if RUBY_PLATFORM.include?('openbsd') && missing[:gems].any?
          puts "deps0: installing #{missing[:gems].size} gems..." if verbose
          AutoInstall.ensure_gems(verbose: false)
        end
      rescue StandardError
        # Don't block boot on install failures
      end

      def apply_openbsd_security
        begin
          require_relative 'openbsd_pledge'
          OpenBSDPledge.cli_profile
        rescue LoadError
          # Silently skip if not available
        rescue => e
          warn "Warning: Could not apply OpenBSD security: #{e.message}" unless ENV['MASTER_QUIET']
        end
      end
    end
  end
end
