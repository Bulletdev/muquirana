class CreateCoinstatsTables < ActiveRecord::Migration[7.2]
  def change
    create_table :coinstats_items, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.string :name, null: false
      # Chave OpenAPI do proprio usuario (colar), cifrada pelo mesmo mecanismo de
      # ActiveRecord Encryption usado em PlaidItem#access_token / BinanceItem#api_key.
      t.string :api_key
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

    add_index :coinstats_items, :family_id

    create_table :coinstats_accounts, id: :uuid do |t|
      t.uuid :coinstats_item_id, null: false
      t.string :name, null: false
      # Saldo agregado da carteira e importado em USD (CoinStats). A conversao para
      # a moeda da familia (BRL) acontece no CoinstatsAccount::Processor.
      t.string :currency, null: false, default: "USD"
      # account_id codifica a chain para nao colidir quando o mesmo endereco existe
      # em varias chains EVM (ex.: "wallet:ethereum:0xabc" vs "wallet:polygon:0xabc").
      t.string :account_id
      t.string :wallet_address
      t.string :blockchain
      t.decimal :current_balance, precision: 19, scale: 4
      t.jsonb :institution_metadata, default: {}
      t.jsonb :extra, default: {}
      t.jsonb :raw_payload, default: {}
      t.timestamps
    end

    add_index :coinstats_accounts, :coinstats_item_id
    add_index :coinstats_accounts,
              %i[coinstats_item_id account_id wallet_address],
              unique: true,
              name: "index_coinstats_accounts_on_item_account_wallet"

    add_foreign_key :coinstats_items, :families
    add_foreign_key :coinstats_accounts, :coinstats_items
  end
end
