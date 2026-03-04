# frozen_string_literal: true

module Master
  ROOT_DIR = File.expand_path(__dir__)
  LIB_FILES_GLOB = File.join(ROOT_DIR, "**", "*.rb").freeze
  EXCLUDED_FILES = [File.expand_path(__FILE__)].freeze

  def self.require_all!
    Dir[LIB_FILES_GLOB].sort.each do |path|
      next if EXCLUDED_FILES.include?(File.expand_path(path))

      begin
        require path
      rescue LoadError => e
        raise e.class, "Failed to require #{path}: #{e.message}", e.backtrace
      end
    end
  end
end

Master.require_all!