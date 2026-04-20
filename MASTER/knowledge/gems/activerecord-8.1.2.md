  class Firm < ActiveRecord::Base
    has_many   :clients
    has_one    :account
    belongs_to :conglomerate
  end  