class CreateMercadoBitcoinTables < ActiveRecord::Migration[7.2]
  def change
    create_table :mercado_bitcoin_items, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.string :name, null: false
      # Credenciais da TAPI do proprio usuario (colar), cifradas pelo mesmo
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

    add_index :mercado_bitcoin_items, :family_id

    create_table :mercado_bitcoin_accounts, id: :uuid do |t|
      t.uuid :mercado_bitcoin_item_id, null: false
      t.string :name, null: false
      # Exchange 100% brasileira: saldo ja vem em BRL nativamente.
      t.string :currency, null: false, default: "BRL"
      t.string :account_type
      t.decimal :current_balance, precision: 19, scale: 4
      t.jsonb :institution_metadata, default: {}
      t.jsonb :extra, default: {}
      t.jsonb :raw_payload, default: {}
      t.timestamps
    end

    add_index :mercado_bitcoin_accounts, :mercado_bitcoin_item_id

    add_foreign_key :mercado_bitcoin_items, :families
    add_foreign_key :mercado_bitcoin_accounts, :mercado_bitcoin_items
  end
end
