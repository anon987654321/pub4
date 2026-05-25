# frozen_string_literal: true

module Shared
  class BootValidator
    def self.verify!(app_name, root_path)
      gemfile = File.read(File.join(root_path, "Gemfile")) rescue ""
      readme = File.read(File.join(root_path, "README.md")) rescue ""
      routes = File.read(File.join(root_path, "config/routes.rb")) rescue ""

      if gemfile.include?('gem "sqlite3"') && readme.match?(/Rails 8, PostgreSQL/)
        warn "Configuration discrepancy in #{app_name}: Gemfile uses SQLite; README references PostgreSQL."
      end
      if gemfile.include?("/home/amber/.bundle/gems") && app_name != "amber"
        raise SecurityError, "Hardcoded path leak detected: #{app_name} references amber bundle path."
      end
      unless routes.include?("rails/health#show")
        raise "#{app_name}: missing health check route (rails/health#show)"
      end
    end
  end
end
