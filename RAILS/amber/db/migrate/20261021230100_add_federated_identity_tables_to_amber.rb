# frozen_string_literal: true

# OAuth callbacks are shared by the host apps. Amber previously had no
# identity_providers or external_identities tables, so every callback lacked a
# durable provider-subject mapping. In particular, BankID supplies no email,
# and its synthetic placeholder address changed the callback from a login into
# a failed or duplicate account creation.
class AddFederatedIdentityTablesToAmber < ActiveRecord::Migration[8.1]
  def up
    create_table :identity_providers, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :issuer
      t.string :client_id
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :identity_providers, :slug, unique: true, if_not_exists: true

    create_table :external_identities, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :identity_provider, null: false, foreign_key: true
      t.string :subject, null: false
      t.string :email_address
      t.string :phone_number
      t.string :assurance_level, null: false, default: "account"
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :external_identities, %i[identity_provider_id subject], unique: true,
                                                                      name: "index_external_identities_on_provider_and_subject",
                                                                      if_not_exists: true
  end

  def down
    # Provider subjects are login credentials; never drop them as an automatic rollback.
  end
end
