class CreateCoinbaseTables < ActiveRecord::Migration[7.2]
  def change
    create_table :coinbase_items, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.string :name, null: false
      # Credenciais CDP do proprio usuario (colar), cifradas pelo mesmo mecanismo
      # de ActiveRecord Encryption usado em PlaidItem#access_token.
      # api_key = ID/name da chave CDP; api_secret = PEM EC private key.
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

    add_index :coinbase_items, :family_id

    create_table :coinbase_accounts, id: :uuid do |t|
      t.uuid :coinbase_item_id, null: false
      t.string :name, null: false
      t.string :currency, null: false, default: "USD"
      t.string :account_type
      t.decimal :current_balance, precision: 19, scale: 4
      t.jsonb :institution_metadata, default: {}
      t.jsonb :extra, default: {}
      t.jsonb :raw_payload, default: {}
      t.timestamps
    end

    add_index :coinbase_accounts, :coinbase_item_id

    add_foreign_key :coinbase_items, :families
    add_foreign_key :coinbase_accounts, :coinbase_items
  end
end
