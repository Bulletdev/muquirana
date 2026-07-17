class CreateGoals < ActiveRecord::Migration[7.2]
  def change
    create_table :goals, id: :uuid do |t|
      t.references :family, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      # Nucleo: uma meta liga a UMA conta e usa o saldo dela. Sem earmark/pool.
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false
      t.decimal :target_amount, precision: 19, scale: 4, null: false
      t.string :currency, null: false
      t.date :target_date
      t.string :color
      t.string :icon
      t.text :notes

      t.timestamps
    end

    add_index :goals, [ :family_id, :account_id ]
    add_check_constraint :goals, "char_length(name) <= 255", name: "chk_goals_name_length"
    add_check_constraint :goals, "target_amount > 0", name: "chk_goals_target_amount_positive"
  end
end
