require "test_helper"

class FamilyTest < ActiveSupport::TestCase
  include SyncableInterfaceTest

  def setup
    @syncable = families(:dylan_family)
  end

  test "demo? e true quando ha usuario no dominio reservado da demo" do
    family = families(:empty)
    family.users.create!(
      email: "ana@muquirana.local",
      first_name: "Ana",
      last_name: "Souza",
      password: "password",
      role: "member"
    )

    assert family.demo?
  end

  test "demo? e false para familia comum" do
    assert_not families(:dylan_family).demo?
  end
end
