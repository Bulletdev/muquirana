class CreateAccountProviders < ActiveRecord::Migration[7.2]
  def change
    create_table :account_providers, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.string :provider_type, null: false
      t.uuid :provider_id, null: false

      t.timestamps
    end

    add_index :account_providers, :account_id
    add_index :account_providers, [ :provider_type, :provider_id ], unique: true
    add_index :account_providers, [ :account_id, :provider_type ], unique: true
  end
end
