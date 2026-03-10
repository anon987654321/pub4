module MASTER
  module UI
    def self.stream(text)
      text.each_char do |c|
        print c
        sleep 0.003
      end
      puts
    end
  end
end
