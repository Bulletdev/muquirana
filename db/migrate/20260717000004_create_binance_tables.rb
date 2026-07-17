class CreateBinanceTables < ActiveRecord::Migration[7.2]
  def change
    create_table :binance_items, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.string :name, null: false
      # Credenciais da API do proprio usuario (colar), cifradas pelo mesmo
      # mecanismo de ActiveRecord Encryption usado em PlaidItem#access_token.
      t.string :api_key
      t.string :api_secret
      t.string :status, null: false, default: "good"
      t.string :last_error
      t.boolean :scheduled_for_deletion, null: false, default: false
      t.string :institution_name
      t.string :institution_domain
      t.string :institution_url
      t.string :institution_color
      t.jsonb :raw_payload, default: {}
      t.timestamps
    end

    add_index :binance_items, :family_id

    create_table :binance_accounts, id: :uuid do |t|
      t.uuid :binance_item_id, null: false
      t.string :name, null: false
      t.string :currency, null: false, default: "USD"
      t.string :account_type
      t.decimal :current_balance, precision: 19, scale: 4
      t.jsonb :institution_metadata, default: {}
      t.jsonb :extra, default: {}
      t.jsonb :raw_payload, default: {}
      t.timestamps
    end

    add_index :binance_accounts, :binance_item_id

    add_foreign_key :binance_items, :families
    add_foreign_key :binance_accounts, :binance_items
  end
end
