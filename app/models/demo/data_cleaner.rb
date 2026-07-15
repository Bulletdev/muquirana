# SAFETY: destroi TODAS as familias do banco. Nao e "limpar a demo": e limpar
# o banco inteiro. Por isso so roda em development/test ou numa instancia que
# se declarou de demonstracao (DEMO_INSTANCE=true).
class Demo::DataCleaner
  SAFE_ENVIRONMENTS = %w[development test]

  def initialize
    ensure_safe_environment!
  end

  # Main entry point for destroying all demo data
  def destroy_everything!
    Family.destroy_all
    Setting.destroy_all
    InviteCode.destroy_all
    ExchangeRate.destroy_all
    Security.destroy_all
    Security::Price.destroy_all

    puts "Data cleared"
  end

  # A instancia se declarou de demonstracao?
  #
  # E uma variavel de ambiente e nao uma configuracao no banco de proposito: o
  # que esta no banco e justamente o que este objeto apaga, entao a permissao
  # nao pode morar la. Fica no deploy, que e onde se sabe qual instancia e qual.
  def self.demo_instance?
    ENV["DEMO_INSTANCE"] == "true"
  end

  private

    def ensure_safe_environment!
      return if SAFE_ENVIRONMENTS.include?(Rails.env)
      return if self.class.demo_instance?

      raise SecurityError,
        "Demo::DataCleaner apaga TODAS as familias do banco. Permitido em " \
        "#{SAFE_ENVIRONMENTS.join(', ')}, ou com DEMO_INSTANCE=true numa " \
        "instancia dedicada de demonstracao. Ambiente atual: #{Rails.env}. " \
        "Se voce esta vendo isto na instancia real, o bloqueio funcionou."
    end
end
