module MASTER
  module CLI
    COMMANDS = {}

    def self.register(name, &block)
      COMMANDS[name] = block
    end

    def self.run(input)
      cmd, *args = input.split
      handler = COMMANDS[cmd]

      if handler
        handler.call(args)
      else
        puts "unknown command: #{cmd}"
      end
    end
  end
end
