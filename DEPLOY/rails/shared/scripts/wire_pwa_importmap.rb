# frozen_string_literal: true

pins = <<~RUBY
pin "idb-keyval", to: "https://esm.sh/idb-keyval@6.2.1"
pin "pwa/offline_store", to: "pwa/offline_store.js"
pin "pwa/bootstrap", to: "pwa/bootstrap.js"
RUBY

%w[amber brgen baibl blognet bsdports hjerterom].each do |app|
  path = File.expand_path("../../#{app}/config/importmap.rb", __dir__)
  content = File.read(path)
  next if content.include?("pwa/bootstrap")

  File.write(path, content.rstrip + "\n" + pins)
  puts "wired importmap: #{app}"
end