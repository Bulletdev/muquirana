class ChangeInviteCodesToMultiUse < ActiveRecord::Migration[7.2]
  def up
    # De uso unico para multi-uso com limite.
    #
    # used_at/used_by_id eram 1:1 e nao servem mais: varias pessoas usam o
    # mesmo codigo. Quem usou passa a ser rastreado do lado do usuario
    # (users.invite_code_id), que e onde a informacao naturalmente pertence --
    # cada conta veio de um convite.
    add_column :invite_codes, :max_uses, :integer, null: false, default: 1
    add_column :invite_codes, :uses_count, :integer, null: false, default: 0
    add_column :invite_codes, :revoked_at, :datetime

    add_reference :users, :invite_code, type: :uuid, null: true,
                  foreign_key: { on_delete: :nullify }

    # Preserva o que ja existe: codigo usado vira 1 de 1, e quem usou migra
    # para o novo lado da relacao.
    execute <<~SQL
      UPDATE users
         SET invite_code_id = ic.id
        FROM invite_codes ic
       WHERE ic.used_by_id = users.id
    SQL

    execute "UPDATE invite_codes SET uses_count = 1 WHERE used_at IS NOT NULL"

    remove_index :invite_codes, [ :token, :used_at ]
    remove_column :invite_codes, :used_at
    remove_reference :invite_codes, :used_by

    # A busca do claimable filtra por token + nao revogado.
    add_index :invite_codes, [ :token, :revoked_at ]
  end

  def down
    add_column :invite_codes, :used_at, :datetime
    add_reference :invite_codes, :used_by, type: :uuid, foreign_key: { to_table: :users }, null: true

    # So da para reverter fielmente o que coube em 1:1: o primeiro usuario de
    # cada codigo. Codigo com mais de um uso perde os demais -- por isso o
    # aviso, e nao um rollback silencioso que parece completo.
    say "ATENCAO: codigos com mais de um uso perdem os usos alem do primeiro."
    execute <<~SQL
      UPDATE invite_codes
         SET used_by_id = sub.user_id, used_at = sub.created_at
        FROM (
          SELECT DISTINCT ON (invite_code_id) invite_code_id, id AS user_id, created_at
            FROM users
           WHERE invite_code_id IS NOT NULL
           ORDER BY invite_code_id, created_at ASC
        ) sub
       WHERE invite_codes.id = sub.invite_code_id
    SQL

    remove_index :invite_codes, [ :token, :revoked_at ]
    remove_reference :users, :invite_code
    remove_column :invite_codes, :revoked_at
    remove_column :invite_codes, :uses_count
    remove_column :invite_codes, :max_uses

    add_index :invite_codes, [ :token, :used_at ]
  end
end
