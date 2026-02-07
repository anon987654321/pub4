module MASTER
  class Monitoring
    def self.track_tokens(in_tokens, out_tokens)
      puts "Tokens: #{in_tokens} in, #{out_tokens} out"
    end

    def self.track_cost(cost)
      puts "Cost: $#{cost}"
    end
  end
end
