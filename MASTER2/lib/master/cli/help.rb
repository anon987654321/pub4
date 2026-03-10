require_relative "commands"

module MASTER
  module CLI
    CLI.register("help") do |_|
      puts
      puts "MASTER COMMANDS"
      puts
      puts " status        system overview"
      puts " models        show model routing"
      puts " tools         list tools"
      puts " analyze       run analyzer"
      puts " doctor        system diagnostics"
      puts " clear         clear screen"
      puts " exit"
      puts
    end
  end
end
