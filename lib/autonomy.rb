module MASTER
  class Autonomy
    def decide(action, risk)
      case risk
      when 'low' then :apply
      when 'medium' then :preview
      when 'high' then :ask
      end
    end
  end
end
