# frozen_string_literal: true

# Inspeciona se as chaves EXPLICITAS de Active Record Encryption estao
# configuradas (via variaveis de ambiente ou credentials do Rails).
#
# No Muquirana os dados sensiveis SEMPRE sao criptografados: quando o operador
# nao define chaves explicitas, o initializer active_record_encryption.rb deriva
# as chaves a partir do SECRET_KEY_BASE. O ponto de atencao e que, nesse modo
# derivado, girar o SECRET_KEY_BASE sem antes fixar as chaves explicitas torna os
# dados ja criptografados ILEGIVEIS. Por isso distinguimos "configurado
# explicitamente" de "derivado do SECRET_KEY_BASE".
module ActiveRecordEncryptionConfig
  ENV_KEYS = %w[
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
  ].freeze

  CONFIG_KEYS = %i[
    primary_key
    deterministic_key
    key_derivation_salt
  ].freeze

  module_function

  def complete_env?(env = ENV)
    ENV_KEYS.all? { |key| env_value_present?(env, key) }
  end

  def partial_env?(env = ENV)
    present_count = ENV_KEYS.count { |key| env_value_present?(env, key) }
    present_count.positive? && present_count < ENV_KEYS.count
  end

  def missing_env_keys(env = ENV)
    ENV_KEYS.reject { |key| env_value_present?(env, key) }
  end

  def credentials_configured?(credentials = Rails.application.credentials)
    credentials.active_record_encryption.present?
  rescue NoMethodError
    false
  end

  # Verdadeiro somente quando as chaves foram fixadas de forma EXPLICITA (env ou
  # credentials) - e nao apenas derivadas do SECRET_KEY_BASE.
  def explicitly_configured?
    complete_env? || credentials_configured?
  end

  def env_value_present?(env, key)
    env[key].present?
  end
end
