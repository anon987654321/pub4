# frozen_string_literal: true

apps = %w[amber brgen baibl blognet bsdports hjerterom]
snippet = <<~RUBY
  get "offline" => "offline#show", as: :offline
RUBY

apps.each do |app|
  path = File.expand_path("../../#{app}/config/routes.rb", __dir__)
  content = File.read(path)
  next if content.include?("offline#show")

  content = content.sub(
    /get "manifest"/,
    "#{snippet.strip}\n  get \"manifest\""
  )
  File.write(path, content)
  puts "wired offline route: #{app}"
end