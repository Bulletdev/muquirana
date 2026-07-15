require "test_helper"

class PlaidItemTest < ActiveSupport::TestCase
  include SyncableInterfaceTest

  setup do
    @plaid_item = @syncable = plaid_items(:one)
    @plaid_provider = mock
    Provider::Registry.stubs(:plaid_provider_for_region).returns(@plaid_provider)
  end

  # access_token e a credencial de acesso a conta bancaria real do usuario: quem
  # a tiver fala direto com a API da Plaid e le todo o historico financeiro da
  # familia. Precisa estar cifrada em repouso, sempre -- independente de a chave
  # de encryption vir de Rails.credentials ou de config.active_record.encryption.
  test "access_token is encrypted at rest" do
    secret = "access-production-#{SecureRandom.hex(8)}"

    item = families(:dylan_family).plaid_items.create!(
      name: "probe", plaid_id: "probe-#{SecureRandom.hex(4)}", access_token: secret
    )

    raw = ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql([ "SELECT access_token FROM plaid_items WHERE id = ?", item.id ])
    )

    assert_not_equal secret, raw, "access_token nao pode ser gravado em texto plano"
    assert_equal secret, item.reload.access_token, "e precisa continuar legivel pela aplicacao"
  end

  test "access_token is declared as an encrypted attribute" do
    assert_includes PlaidItem.encrypted_attributes.to_a, :access_token
  end

  test "removes plaid item when destroyed" do
    @plaid_provider.expects(:remove_item).with(@plaid_item.access_token).once

    assert_difference "PlaidItem.count", -1 do
      @plaid_item.destroy
    end
  end
end
