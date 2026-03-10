module MASTER
  class Memory
    def initialize
      @entries = []
    end

    def store(input, response)
      @entries << { input: input, response: response }
    end
  end
end
