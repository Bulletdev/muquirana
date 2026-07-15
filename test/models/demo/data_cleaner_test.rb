require "test_helper"

class Demo::DataCleanerTest < ActiveSupport::TestCase
  # Este objeto apaga TODAS as familias do banco. O teste existe para o dia em
  # que alguem relaxar o guarda sem perceber o que ele protege.
  test "refuses to run in production without DEMO_INSTANCE" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

    erro = assert_raises(SecurityError) { Demo::DataCleaner.new }
    assert_match(/DEMO_INSTANCE/, erro.message)
  end

  test "runs in production when the instance declares itself a demo" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

    with_env_overrides DEMO_INSTANCE: "true" do
      assert_nothing_raised { Demo::DataCleaner.new }
    end
  end

  # "true" e so a string exata: DEMO_INSTANCE=1 ou =yes nao valem, para um
  # valor digitado errado falhar fechado em vez de liberar o apagamento.
  test "only the exact string true unlocks production" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

    [ "1", "yes", "TRUE", "" ].each do |valor|
      with_env_overrides DEMO_INSTANCE: valor do
        assert_raises(SecurityError, "DEMO_INSTANCE=#{valor.inspect} nao devia liberar") do
          Demo::DataCleaner.new
        end
      end
    end
  end

  test "runs in test environment as before" do
    assert_nothing_raised { Demo::DataCleaner.new }
  end
end
