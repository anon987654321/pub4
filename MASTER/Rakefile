require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "lib" << "test"
  t.pattern = "test/test_*.rb"
end

task default: :test
