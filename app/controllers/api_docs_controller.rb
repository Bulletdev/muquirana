# Renderiza a documentacao da API v1 a partir do API.md na raiz do repo -- fonte
# unica: a mesma doc que aparece no GitHub aparece no app, sem dessincronizar.
# O placeholder SEU-HOST vira o host real da instancia, deixando os exemplos de
# curl prontos para copiar e colar.
class ApiDocsController < ApplicationController
  def show
    raw = File.read(Rails.root.join("API.md"))
    @api_doc = raw.gsub("https://SEU-HOST", request.base_url)
  rescue Errno::ENOENT
    @api_doc = nil
  end
end
