# frozen_string_literal: true

class NormalizeNvdAdvisoryPortsAndThrottle < ActiveRecord::Migration[8.1]
  def up
    create_table :security_advisory_ports do |t|
      t.references :security_advisory, null: false, foreign_key: true
      t.references :port, null: false, foreign_key: true
      t.timestamps
    end
    add_index :security_advisory_ports, [ :security_advisory_id, :port_id ],
              unique: true, name: "index_security_advisory_ports_on_advisory_and_port"

    # Preserve every existing advisory-to-port association before removing
    # the old single-port column.
    execute <<~SQL
      INSERT INTO security_advisory_ports
        (security_advisory_id, port_id, created_at, updated_at)
      SELECT id, port_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM security_advisories
      WHERE port_id IS NOT NULL
    SQL

    remove_reference :security_advisories, :port, foreign_key: true, index: true

    create_table :nvd_rate_limits do |t|
      t.string :name, null: false
      t.datetime :next_allowed_at
      t.timestamps
    end
    add_index :nvd_rate_limits, :name, unique: true
  end

  def down
    drop_table :nvd_rate_limits

    add_reference :security_advisories, :port, null: true, foreign_key: true
    execute <<~SQL
      UPDATE security_advisories
      SET port_id = (
        SELECT port_id FROM security_advisory_ports
        WHERE security_advisory_ports.security_advisory_id = security_advisories.id
        ORDER BY port_id LIMIT 1
      )
    SQL
    drop_table :security_advisory_ports
  end
end
