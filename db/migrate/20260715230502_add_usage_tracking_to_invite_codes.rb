class AddUsageTrackingToInviteCodes < ActiveRecord::Migration[7.2]
  def change
    # O codigo era DESTRUIDO ao ser usado (InviteCode.claim! -> destroy!), o que
    # deixava o admin sem nenhuma informacao sobre quem entrou na instancia
    # dele: a tabela so tinha token/created_at/updated_at, e a linha sumia.
    #
    # Agora o uso e MARCADO. O codigo continua valendo uma vez so (o claim!
    # busca por used_at: nil), mas fica no historico com quem usou e quando.
    add_column :invite_codes, :used_at, :datetime
    add_reference :invite_codes, :used_by, type: :uuid, foreign_key: { to_table: :users }, null: true

    # A busca do claim! filtra por token + nao usado.
    add_index :invite_codes, [ :token, :used_at ]
  end
end
