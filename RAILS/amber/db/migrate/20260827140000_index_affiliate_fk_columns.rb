# frozen_string_literal: true

class IndexAffiliateFkColumns < ActiveRecord::Migration[8.1]
  def change
    add_index :affiliate_conversions, :event_type_id
    add_index :affiliate_conversions, :program_id
    add_index :affiliate_conversions, :site_id
    add_index :affiliate_vouchers, :program_id
    add_index :affiliate_vouchers, :voucher_type_id
  end
end
