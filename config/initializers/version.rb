module Muquirana
  class << self
    def version
      Semver.new(semver)
    end

    def commit_sha
      if Rails.env.production?
        ENV["BUILD_COMMIT_SHA"]
      else
        `git rev-parse HEAD`.chomp
      end
    end

    private
      # 0.6.0 era a ultima versao publicada pelo maybe-finance/maybe, de onde
      # este fork saiu. A partir daqui o versionamento e proprio: 0.7.0 marcou o
      # rebranding para Muquirana e a traducao para pt-BR; 0.7.1 acumula os
      # provedores de conta (Coinbase/IBKR/CoinStats), a IA multi-provedor, o
      # dashboard de relatorios e os ajustes de UI.
      def semver
        "0.7.1"
      end
  end
end
