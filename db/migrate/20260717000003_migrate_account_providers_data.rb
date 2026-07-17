class MigrateAccountProvidersData < ActiveRecord::Migration[7.2]
  # Data-migration adaptada do Sure: cada Account hoje linkada a um PlaidAccount
  # via FK direta (accounts.plaid_account_id) passa a ter um registro no join
  # polimorfico account_providers. O `WHERE NOT EXISTS` torna a migracao
  # idempotente/re-executavel (usada tambem pelo teste da migracao).
  def up
    execute <<~SQL
      INSERT INTO account_providers (id, account_id, provider_type, provider_id, created_at, updated_at)
      SELECT
        gen_random_uuid(),
        accounts.id,
        'PlaidAccount',
        accounts.plaid_account_id,
        NOW(),
        NOW()
      FROM accounts
      WHERE accounts.plaid_account_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM account_providers ap
          WHERE ap.provider_type = 'PlaidAccount'
            AND ap.provider_id = accounts.plaid_account_id
        )
    SQL
  end

  def down
    execute "DELETE FROM account_providers WHERE provider_type = 'PlaidAccount'"
  end
end
