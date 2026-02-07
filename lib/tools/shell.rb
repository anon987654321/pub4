module MASTER
  module Tools
    class Shell
      def execute(command)
        IO.popen(command, :err=>[:child, :out]) { |io| io.read }
      end
    end
  end
end
