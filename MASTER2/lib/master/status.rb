module MASTER
  START_TIME ||= Time.now

  def self.uptime
    (Time.now - START_TIME).to_i
  end
end
