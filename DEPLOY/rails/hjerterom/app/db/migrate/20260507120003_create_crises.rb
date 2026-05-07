class CreateCrises < ActiveRecord::Migration[8.1]
  def change
    create_table :crises do |t|
      t.string :title
      t.text :description
      t.string :phone
      t.string :sms
      t.string :chat_url
      t.boolean :available_24h, default: false
      t.string :languages
      t.string :country
      t.timestamps
    end
  end
end
