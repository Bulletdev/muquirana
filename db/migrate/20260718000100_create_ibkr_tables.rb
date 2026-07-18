class CreateIbkrTables < ActiveRecord::Migration[7.2]
  def change
    create_table :ibkr_items, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.string :name, null: false
      # Credenciais da Flex Query do proprio usuario (colar), cifradas pelo mesmo
      # mecanismo de ActiveRecord Encryption usado em PlaidItem#access_token.
      t.string :query_id
      t.string :token
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

    add_index :ibkr_items, :family_id

    create_table :ibkr_accounts, id: :uuid do |t|
      t.uuid :ibkr_item_id, null: false
      # Identificador da conta IBKR dentro da Flex Query (ex.: "U1234567").
      t.string :ibkr_account_id
      t.string :name, null: false
      # Moeda base da conta na IBKR (o portfolio pode conter multiplas moedas; a
      # materializacao converte tudo para a moeda da familia).
      t.string :currency, null: false, default: "USD"
      t.decimal :current_balance, precision: 19, scale: 4
      t.decimal :cash_balance, precision: 19, scale: 4
      t.date :report_date
      t.jsonb :institution_metadata, default: {}
      t.jsonb :extra, default: {}
      # Posicoes e movimentacoes cruas do Flex, guardadas para reprocessamento.
      t.jsonb :raw_holdings_payload, default: []
      t.jsonb :raw_activities_payload, default: {}
      t.jsonb :raw_payload, default: {}
      t.timestamps
    end

    add_index :ibkr_accounts, :ibkr_item_id
    add_index :ibkr_accounts, [ :ibkr_item_id, :ibkr_account_id ], unique: true

    add_foreign_key :ibkr_items, :families
    add_foreign_key :ibkr_accounts, :ibkr_items
  end
end
