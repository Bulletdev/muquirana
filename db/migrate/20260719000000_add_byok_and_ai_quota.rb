class AddByokAndAiQuota < ActiveRecord::Migration[7.2]
  def change
    # BYOK (bring your own key): cada usuario pode usar a PROPRIA chave de LLM em
    # vez da chave da instancia. Criptografadas no model (encrypts).
    add_column :users, :openai_access_token, :string
    add_column :users, :anthropic_access_token, :string

    # Uso de LLM por USUARIO (antes so por familia) -- base da quota por membro.
    add_column :llm_usages, :user_id, :uuid
    add_index :llm_usages, [ :user_id, :created_at ]
    add_foreign_key :llm_usages, :users, column: :user_id, on_delete: :nullify
  end
end
