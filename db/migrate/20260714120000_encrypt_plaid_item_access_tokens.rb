class EncryptPlaidItemAccessTokens < ActiveRecord::Migration[7.2]
  # PlaidItem#access_token passou a ser cifrado incondicionalmente. Antes, o
  # `encrypts` so era declarado quando a chave de encryption vinha de
  # Rails.credentials -- ou seja, qualquer instancia que configurasse a
  # encryption via config.active_record.encryption.* (self_hosted, e o proprio
  # ambiente de teste) gravou o token em TEXTO PLANO.
  #
  # Esta migration cifra o que ja esta gravado. Sem ela, ligar o `encrypts`
  # tornaria os registros existentes ilegiveis: o AR tentaria decifrar uma
  # string que nunca foi cifrada e levantaria Decryption error.
  #
  # `support_unencrypted_data` e ligado apenas durante a migration e restaurado
  # no ensure -- deixa-lo ligado permanentemente faria a aplicacao aceitar dados
  # nao cifrados para sempre, que e justamente o que estamos corrigindo.
  def up
    return unless table_exists?(:plaid_items)

    original = ActiveRecord::Encryption.config.support_unencrypted_data
    ActiveRecord::Encryption.config.support_unencrypted_data = true

    PlaidItem.reset_column_information

    migrated = 0
    PlaidItem.find_each do |item|
      # `encrypt` recifra todos os atributos cifrados do registro. E idempotente:
      # valores ja cifrados sao decifrados e recifrados com a mesma chave.
      item.encrypt
      migrated += 1
    end

    say "cifrados #{migrated} plaid_items.access_token"
  ensure
    ActiveRecord::Encryption.config.support_unencrypted_data = original
  end

  def down
    # Irreversivel de proposito: decifrar de volta para texto plano recriaria a
    # vulnerabilidade. Para reverter, remova o `encrypts` do model.
    raise ActiveRecord::IrreversibleMigration
  end
end
