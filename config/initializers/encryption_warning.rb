# frozen_string_literal: true

# Avisa operadores self-hosted quando as chaves EXPLICITAS de Active Record
# Encryption NAO estao configuradas.
#
# ATENCAO: no Muquirana os dados sensiveis nunca ficam em plaintext - o
# initializer active_record_encryption.rb sempre criptografa, derivando as chaves
# do SECRET_KEY_BASE quando as chaves explicitas nao existem. O risco desse modo
# derivado e OUTRO: se o SECRET_KEY_BASE for girado sem antes fixar as chaves
# explicitas, os dados ja criptografados ficam ILEGIVEIS (perda de dados). Este
# aviso existe para alertar sobre isso antes que aconteca.
require Rails.root.join("lib/active_record_encryption_config").to_s

Rails.application.config.after_initialize do
  app_mode = Rails.application.config.app_mode
  if app_mode.self_hosted? && !ActiveRecordEncryptionConfig.explicitly_configured?
    Rails.logger.warn(<<~WARN)
      [SEGURANCA] As chaves explicitas de Active Record Encryption NAO estao
      configuradas. Seus dados continuam criptografados normalmente, porem as
      chaves estao sendo DERIVADAS do SECRET_KEY_BASE. Se voce girar o
      SECRET_KEY_BASE sem antes definir chaves explicitas, TODOS os dados
      criptografados (chaves de API, tokens de banco/provedores, segredos de MFA
      e PII) ficarao ILEGIVEIS de forma permanente.

      Para fixar as chaves e evitar perda de dados, defina nas credentials do
      Rails ou nas variaveis de ambiente:
        ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
        ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
        ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
      Gere um conjunto com: bin/rails db:encryption:init
    WARN
  end
end
