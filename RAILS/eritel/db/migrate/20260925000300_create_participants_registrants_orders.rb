class CreateParticipantsRegistrantsOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :participants do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.string :external_id
      t.text :metadata, null: false, default: "{}"
      t.timestamps
    end

    add_index :participants, :external_id, unique: true
    add_index :participants, :kind
    add_index :participants, :status

    create_table :registrants do |t|
      t.string :email, null: false
      t.string :legal_name
      t.string :country_code, null: false
      t.string :verification_status, null: false, default: "pending"
      t.string :external_id
      t.timestamps
    end

    add_index :registrants, :email, unique: true
    add_index :registrants, :external_id, unique: true
    add_index :registrants, :verification_status

    create_table :orders do |t|
      t.references :domain, null: false, foreign_key: true
      t.references :registrant, null: false, foreign_key: true
      t.references :participant, foreign_key: true
      t.string :operation, null: false
      t.string :state, null: false, default: "pending"
      t.string :idempotency_key, null: false
      t.integer :amount_cents, null: false, default: 0
      t.string :currency, null: false, default: "EUR"
      t.string :registry_request_id
      t.timestamps
    end

    add_index :orders, :idempotency_key, unique: true
    add_index :orders, :registry_request_id, unique: true
    add_index :orders, :state
    add_index :orders, :operation

    create_table :registry_operations do |t|
      t.references :order, null: false, foreign_key: true
      t.string :operation, null: false
      t.string :state, null: false, default: "pending"
      t.string :request_id, null: false
      t.string :response_code
      t.string :error_code
      t.string :payload_digest
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :registry_operations, :request_id, unique: true
    add_index :registry_operations, :state
    add_index :registry_operations, :operation
  end
end
