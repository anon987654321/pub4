module MASTER
  class Monitoring
    def self.track_tokens(in_tokens, out_tokens)
      puts "Tokens: #{in_tokens} in, #{out_tokens} out"
      Persistence.new("#{MASTER.root}/master.db").save_session({ type: 'tokens', in: in_tokens, out: out_tokens })
    end

    def self.track_cost(cost)
      puts "Cost: $#{cost}"
      Persistence.new("#{MASTER.root}/master.db").save_session({ type: 'cost', amount: cost })
    end
  end
end
