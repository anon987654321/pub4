module MASTER
  module Performance
    SHORTCUTS = {
      'Ctrl+N' => 'New file', 'Ctrl+O' => 'Open file', 'Ctrl+S' => 'Save',
      'Ctrl+Z' => 'Undo', 'Ctrl+F' => 'Search', '/' => 'Quick search'
    }.freeze
    
    def self.shortcuts_help
      SHORTCUTS.map { |key, desc| "#{key.ljust(8)} #{desc}" }.join("\n")
    end
    
    def self.smart_default(context, options = {})
      case context
      when :filename then Time.now.strftime("%Y%m%d_%H%M%S")
      when :directory then Dir.pwd
      else options[:default]
      end
    end
    
    def self.cache_status(hit = false)
      hit ? "⚡ cached" : "⟳ loading"
    end
  end
end
