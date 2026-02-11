module MASTER
  class Monitoring
    @@persistence = Persistence.new("#{MASTER.root}/monitor.db")

    def self.track_tokens(in_tokens, out_tokens)
      puts "Tokens: #{in_tokens} in, #{out_tokens} out"
      @@persistence.save_session({ type: 'tokens', in: in_tokens, out: out_tokens, timestamp: Time.now })
    end

    def self.track_cost(cost)
      puts "Cost: $#{cost}"
      @@persistence.save_session({ type: 'cost', amount: cost, timestamp: Time.now })
    end

    def self.get_stats
      @@persistence.load_session('stats') || { total_tokens: 0, total_cost: 0 }
    end
  end
end
