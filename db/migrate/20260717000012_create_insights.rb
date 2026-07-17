class CreateInsights < ActiveRecord::Migration[7.2]
  def change
    create_table :insights, id: :uuid do |t|
      # index: false -- todo indice composto abaixo comeca por family_id, entao
      # o indice de coluna unica que o Rails criaria seria overhead de escrita
      # redundante.
      t.references :family, null: false, type: :uuid, foreign_key: true, index: false
      t.string :insight_type, null: false
      t.string :priority, null: false, default: "medium"
      t.string :status, null: false, default: "active"
      t.string :title, null: false
      t.text :body, null: false
      t.jsonb :metadata, null: false, default: {}
      # Valores de exibicao (dinheiro formatado, datas localizadas) usados para
      # renderizar numeros-chave e links contextuais. Atualizados a cada
      # execucao -- diferente de `metadata`, que guarda so os sinais bucketizados
      # de deteccao de mudanca.
      t.jsonb :facts, null: false, default: {}
      t.string :currency, null: false, default: "BRL"
      t.date :period_start
      t.date :period_end
      t.datetime :generated_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :read_at
      t.datetime :dismissed_at
      # Embute o tipo do insight e o sujeito, ex.: "spending_anomaly:<category-id>:2026-07",
      # entao re-rodar o job noturno atualiza a linha existente em vez de duplicar.
      t.string :dedup_key, null: false

      t.timestamps
    end

    add_check_constraint :insights, "priority IN ('high', 'medium', 'low')", name: "chk_insights_priority"
    add_check_constraint :insights, "status IN ('active', 'read', 'dismissed', 'expired')", name: "chk_insights_status"

    add_index :insights, [ :family_id, :status ]
    add_index :insights, [ :family_id, :dedup_key ], unique: true
    add_index :insights, [ :family_id, :generated_at ]
  end
end
