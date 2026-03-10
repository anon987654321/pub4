require_relative "commands"

module MASTER
  module CLI
    CLI.register("tools") do |_|
      puts
      puts "TOOLS"
      puts
      MASTER::Tools.list.each do |t|
        puts " #{t}"
      end
      puts
    end
  end
end
