# frozen_string_literal: true

# SelfAwareness - MASTER knows itself
# Loads and caches MASTER's own codebase structure on startup

module MASTER
  module SelfAwareness
    CACHE_FILE = File.join(Paths.var, 'self_awareness.json')
    CACHE_TTL = 3600  # 1 hour
    
    class << self
      def load
        @data ||= build_or_load_cache
      end
      
      def summary
        data = load
        <<~SUMMARY
          MASTER Self-Awareness:
            Files: #{data[:file_count]}
            Lines: #{data[:total_lines]}
            Modules: #{data[:modules].size}
            Classes: #{data[:classes].size}
            Methods: #{data[:method_count]}
            Last analyzed: #{data[:analyzed_at]}
        SUMMARY
      end
      
      def files
        load[:files]
      end
      
      def modules
        load[:modules]
      end
      
      def classes
        load[:classes]
      end
      
      def structure
        load[:structure]
      end
      
      def find_file(name)
        files.find { |f| f[:path].include?(name) }
      end
      
      def find_class(name)
        classes.find { |c| c[:name].downcase.include?(name.downcase) }
      end
      
      def find_method(name)
        load[:methods].select { |m| m[:name].include?(name) }
      end
      
      def refresh!
        @data = nil
        FileUtils.rm_f(CACHE_FILE)
        load
      end
      
      # Inject self-knowledge into LLM context
      def context_for_llm
        data = load
        <<~CONTEXT
          You are MASTER, a self-modifying Ruby AI framework.
          
          Your codebase structure:
          - Root: #{Paths.root}
          - #{data[:file_count]} Ruby files, #{data[:total_lines]} lines
          - Key modules: #{data[:modules].map { |m| m[:name] }.take(10).join(', ')}
          - Key classes: #{data[:classes].map { |c| c[:name] }.take(10).join(', ')}
          
          Your core components:
          #{data[:structure].map { |dir, info| "- #{dir}/: #{info[:files]} files (#{info[:purpose]})" }.join("\n")}
          
          You can modify your own code. Use `cat lib/FILE.rb` to read, `edit FILE.rb` to modify.
          Your session persists in var/. Your config is in config/.
          
          Key files to know:
          - lib/cli.rb: Main CLI and REPL
          - lib/llm.rb: LLM API wrapper
          - lib/master.rb: Module autoloading
          - lib/paths.rb: Directory structure
        CONTEXT
      end
      
      private
      
      def build_or_load_cache
        if cache_valid?
          load_cache
        else
          build_cache
        end
      end
      
      def cache_valid?
        return false unless File.exist?(CACHE_FILE)
        
        data = JSON.parse(File.read(CACHE_FILE), symbolize_names: true)
        cached_at = Time.parse(data[:analyzed_at]) rescue Time.at(0)
        Time.now - cached_at < CACHE_TTL
      rescue
        false
      end
      
      def load_cache
        JSON.parse(File.read(CACHE_FILE), symbolize_names: true)
      rescue
        build_cache
      end
      
      def build_cache
        files = collect_files
        
        data = {
          analyzed_at: Time.now.iso8601,
          file_count: files.size,
          total_lines: 0,
          files: [],
          modules: [],
          classes: [],
          methods: [],
          method_count: 0,
          structure: {}
        }
        
        files.each do |path|
          file_data = analyze_file(path)
          data[:files] << file_data
          data[:total_lines] += file_data[:lines]
          data[:modules].concat(file_data[:modules])
          data[:classes].concat(file_data[:classes])
          data[:methods].concat(file_data[:methods])
        end
        
        data[:method_count] = data[:methods].size
        data[:modules].uniq! { |m| m[:name] }
        data[:classes].uniq! { |c| c[:name] }
        data[:structure] = analyze_structure
        
        # Save cache
        FileUtils.mkdir_p(File.dirname(CACHE_FILE))
        File.write(CACHE_FILE, JSON.pretty_generate(data))
        
        data
      end
      
      def collect_files
        Dir.glob(File.join(Paths.lib, '**', '*.rb'))
           .reject { |f| f.include?('/test/') || f.include?('/spec/') }
      end
      
      def analyze_file(path)
        content = File.read(path)
        relative = path.sub("#{Paths.root}/", '')
        
        {
          path: relative,
          lines: content.lines.size,
          modules: content.scan(/^\s*module\s+(\w+)/).map { |m| { name: m[0], file: relative } },
          classes: content.scan(/^\s*class\s+(\w+)/).map { |c| { name: c[0], file: relative } },
          methods: content.scan(/^\s*def\s+(\w+)/).map { |m| { name: m[0], file: relative } }
        }
      rescue => e
        { path: path, lines: 0, modules: [], classes: [], methods: [], error: e.message }
      end
      
      def analyze_structure
        {
          'lib/' => { files: Dir.glob("#{Paths.lib}/*.rb").size, purpose: 'Core modules' },
          'lib/core/' => { files: Dir.glob("#{Paths.lib}/core/*.rb").size, purpose: 'Internal components' },
          'lib/principles/' => { files: Dir.glob("#{Paths.principles}/*.yml").size, purpose: 'Constitutional principles' },
          'lib/personas/' => { files: Dir.glob("#{Paths.personas}/*.yml").size, purpose: 'AI personas' },
          'lib/dreams/' => { files: Dir.glob("#{Paths.lib}/dreams/*.rb").size, purpose: 'Aspirational features' },
          'var/' => { files: Dir.glob("#{Paths.var}/*").size, purpose: 'Runtime data' },
          'config/' => { files: Dir.glob("#{Paths.config}/*.yml").size, purpose: 'Configuration' }
        }
      end
    end
  end
end
