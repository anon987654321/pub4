# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# Production's master container loads every law file at boot, and Law.define raises ArgumentError for a
# law that lacks bad, good or fix. A missing example takes the container down while a local boot
# smoke that loads them together can stay green, so each file loads in its own process here.
class TestLawFilesLoad < Minitest::Test
  LAW_DIR = File.expand_path("../law", __dir__)

  Dir[File.join(LAW_DIR, "*.rb")].sort.reject { |f| File.basename(f) == "definition.rb" }.each do |file|
    define_method("test_#{File.basename(file, ".rb")}_loads_without_error") do
      script = "require #{File.expand_path("../lib/master", __dir__).inspect}; " \
               "require #{File.join(LAW_DIR, "definition").inspect}; load #{file.inspect}"
      out, status = Open3.capture2e(RbConfig.ruby, "-W0", "-e", script)

      assert status.success?, "#{File.basename(file)} raised:\n#{out.lines.first(6).join}"
    end
  end
end
