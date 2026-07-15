class Provider::Github
  attr_reader :name, :owner, :branch

  # O repositorio era fixo em maybe-finance/maybe. Isso fazia a tela "Novidades"
  # exibir as notas de versao do projeto original -- com o avatar e o usuario
  # deles -- como se fossem as deste app.
  #
  # Agora vem de env. Sem configuracao, nenhuma chamada e feita e o metodo
  # devolve nil: melhor nao exibir novidade alguma do que exibir a de outro
  # projeto.
  def initialize
    @name = ENV["GITHUB_REPO_NAME"]
    @owner = ENV["GITHUB_REPO_OWNER"]
    @branch = ENV.fetch("GITHUB_REPO_BRANCH", "main")
  end

  def configured?
    owner.present? && name.present?
  end

  def fetch_latest_release_notes
    return nil unless configured?

    begin
      Rails.cache.fetch("latest_github_release_notes", expires_in: 2.hours) do
        release = Octokit.releases(repo).first
        if release
          {
            avatar: release.author.avatar_url,
            # this is the username, it would be nice to get the full name
            username: release.author.login,
            name: release.name,
            published_at: release.published_at,
            body: Octokit.markdown(release.body, mode: "gfm", context: repo)
          }
        else
          nil
        end
      end
    rescue => e
      Rails.logger.error "Failed to fetch latest GitHub release notes: #{e.message}"
      nil
    end
  end

  private
    def repo
      "#{owner}/#{name}"
    end
end
