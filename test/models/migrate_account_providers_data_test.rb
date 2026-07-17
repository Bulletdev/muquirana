require "test_helper"
require Rails.root.join("db/migrate/20260717000003_migrate_account_providers_data.rb")

# Exercita a data-migration adaptada contra as fixtures de Plaid: cada Account
# ligada a um PlaidAccount pela FK legada (accounts.plaid_account_id) deve ganhar
# um registro no join polimorfico account_providers.
class MigrateAccountProvidersDataTest < ActiveSupport::TestCase
  setup do
    @migration = MigrateAccountProvidersData.new
  end

  test "cria account_providers para cada conta ligada a um PlaidAccount" do
    AccountProvider.delete_all

    account = accounts(:connected)
    assert account.plaid_account_id.present?, "fixture 'connected' deve estar ligada ao Plaid"

    @migration.suppress_messages { @migration.up }

    ap = AccountProvider.find_by(account: account, provider_type: "PlaidAccount")
    assert ap.present?, "esperava um AccountProvider para a conta ligada ao Plaid"
    assert_equal account.plaid_account_id, ap.provider_id
    assert_equal plaid_accounts(:one), ap.provider
  end

  test "e idempotente (nao duplica em reexecucao)" do
    AccountProvider.delete_all
    @migration.suppress_messages { @migration.up }

    assert_no_difference "AccountProvider.count" do
      @migration.suppress_messages { @migration.up }
    end
  end
end
