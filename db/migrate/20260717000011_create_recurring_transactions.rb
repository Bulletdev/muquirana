class CreateRecurringTransactions < ActiveRecord::Migration[7.2]
  # Condensa as 7 migrations incrementais do Sure em uma so: cria a tabela ja
  # com merchant/name opcionais, account opcional, manual e a faixa de variacao
  # de valor. O porte do Muquirana NAO inclui recurring transfers
  # (destination_account) nem controle de acesso por usuario.
  def change
    create_table :recurring_transactions, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, foreign_key: true, type: :uuid
      t.references :merchant, foreign_key: { to_table: :merchants }, type: :uuid
      t.string :name
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :currency, null: false
      t.integer :expected_day_of_month, null: false
      t.date :last_occurrence_date, null: false
      t.date :next_expected_date, null: false
      t.string :status, default: "active", null: false
      t.integer :occurrence_count, default: 0, null: false
      t.boolean :manual, default: false, null: false
      t.decimal :expected_amount_min, precision: 19, scale: 4
      t.decimal :expected_amount_max, precision: 19, scale: 4
      t.decimal :expected_amount_avg, precision: 19, scale: 4

      t.timestamps
    end

    # Uma linha automatica por padrao (merchant/name + valor + moeda + conta).
    add_index :recurring_transactions,
              [ :family_id, :account_id, :merchant_id, :name, :amount, :currency ],
              unique: true,
              name: "idx_recurring_txns_unique_pattern"
    add_index :recurring_transactions, [ :family_id, :status ]
    add_index :recurring_transactions, :next_expected_date
  end
end
