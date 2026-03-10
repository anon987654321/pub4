require_relative "commands"

module MASTER
  module CLI
    CLI.register("models") do |_|
      puts
      puts "MODEL ROUTER"
      puts
      puts " primary    deepseek-v3.1"
      puts " fallback   trinity-mini"
      puts
    end
  end
end
