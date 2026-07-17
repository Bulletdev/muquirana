require "test_helper"

class ActiveRecordEncryptionConfigTest < ActiveSupport::TestCase
  test "explicitly_configured? is true only when all ENV keys are present" do
    full_env = {
      "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "a",
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "b",
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => "c"
    }

    assert ActiveRecordEncryptionConfig.complete_env?(full_env)
  end

  test "complete_env? is false when a key is missing" do
    partial_env = {
      "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "a",
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "b"
    }

    assert_not ActiveRecordEncryptionConfig.complete_env?(partial_env)
    assert ActiveRecordEncryptionConfig.partial_env?(partial_env)
    assert_includes ActiveRecordEncryptionConfig.missing_env_keys(partial_env),
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"
  end

  test "blank ENV values are treated as absent" do
    blank_env = {
      "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "",
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "",
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => ""
    }

    assert_not ActiveRecordEncryptionConfig.complete_env?(blank_env)
  end
end
