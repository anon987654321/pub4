require_relative "commands"

module MASTER
  module CLI
    CLI.register("status") do |_|
      puts
      puts "SYSTEM"
      puts " uptime      #{MASTER.uptime}s"
      puts " tools       #{MASTER::Tools.list.size}"
      puts " analyzers   #{MASTER::Analyzer.list.size}"
      puts
      puts "ROUTER"
      puts " primary     deepseek-v3.1"
      puts " fallback    trinity-mini"
      puts
      puts "SECURITY"
      puts " pledge      enabled"
      puts
    end
  end
end
