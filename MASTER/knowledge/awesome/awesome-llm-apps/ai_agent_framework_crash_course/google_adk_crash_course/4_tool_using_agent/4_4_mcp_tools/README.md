result = Master::Tools::WriteFile.call(
  path: "app/services/hello_service.rb",
  content: <<~RUBY
    # frozen_string_literal: true

    class HelloService
      def call(name)
        "Hello, #{name}!"
      end
    end
  RUBY
)

if result.is_a?(Master::Result::Ok)
  puts "File written successfully."
else
  warn "Failed to write file: #{result.error}"
end
