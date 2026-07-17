class AddSourceAndExternalIdToEntries < ActiveRecord::Migration[7.2]
  def up
    add_column :entries, :source, :string
    add_column :entries, :external_id, :string

    # Backfill: o Plaid ja guardava o id externo da transacao em `plaid_id`.
    # A fundacao generica passa a usar (external_id, source) como chave de
    # provider, entao migramos o dado existente para a coluna generica mantendo
    # `plaid_id` intacto (webhooks/investments/liabilities ainda o usam).
    execute <<~SQL
      UPDATE entries
      SET external_id = plaid_id, source = 'plaid'
      WHERE plaid_id IS NOT NULL
    SQL

    add_index :entries, [ :account_id, :external_id, :source ]
  end

  def down
    remove_index :entries, [ :account_id, :external_id, :source ]
    remove_column :entries, :external_id
    remove_column :entries, :source
  end
end
