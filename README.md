# Muquirana

App de finanças pessoais em português brasileiro.

> [!IMPORTANT]
> **Este é um fork do [Maybe Finance](https://github.com/maybe-finance/maybe).**
>
> O Muquirana **não é afiliado, mantido, patrocinado nem endossado pela Maybe
> Finance, Inc.** "Maybe" é marca registrada da Maybe Finance, Inc. e é citada
> aqui exclusivamente para atribuir a autoria do trabalho original — não como
> marca deste projeto. Nenhum asset de marca do projeto original é distribuído
> aqui.
>
> O projeto original foi arquivado em julho de 2025, na
> [versão v0.6.0](https://github.com/maybe-finance/maybe/releases/tag/v0.6.0).
> Este fork partiu do commit `77b5469` daquele repositório em **14/07/2026** e é
> mantido de forma independente. Defeitos, alterações e decisões daqui em diante
> são de responsabilidade deste projeto, não do original.
>
> Distribuído sob a [licença AGPLv3](LICENSE), preservada integralmente, nos
> mesmos termos do original.

## O que mudou em relação ao original

- **Segurança.** O upstream não publica mais correções, então elas passam a ser
  responsabilidade deste fork. Três vulnerabilidades críticas herdadas foram
  corrigidas: token OAuth revogado que continuava autenticando (toda revogação
  do app era inoperante), vazamento de dados entre famílias por chave
  estrangeira não validada, e token de acesso bancário gravado em texto plano.
  Auditoria de dependências roda no CI e diariamente.
- **Dependências.** Ruby 3.4.8 e Rails 7.2.3.1; 165 alertas de vulnerabilidade
  em gems foram zerados.
- **Marca.** Identidade visual, textos e domínios de exemplo próprios.
- **Idioma.** Internacionalização para pt-BR com BRL como moeda padrão
  *(em andamento)*.

## Rodando localmente

Requisitos: Ruby (ver `.ruby-version`), PostgreSQL e Redis.

```sh
cp .env.local.example .env.local
bin/setup
bin/dev

# opcional: dados de demonstração
bin/rails demo_data:default
```

Acesse http://localhost:3000. O seed cria o login `user@muquirana.local` com a
senha `password`.

## Hospedagem

Veja o [guia de Docker](docs/hosting/docker.md).

> [!WARNING]
> Antes de expor a instância na internet:
>
> - **Gere um `SECRET_KEY_BASE` próprio** (`openssl rand -hex 64`). Nunca use o
>   valor de exemplo do `compose.example.yml` — ele é público. Em modo
>   self-hosted esse mesmo segredo deriva as chaves de criptografia do banco:
>   quem o obtiver lê os tokens de acesso bancário e as chaves de API.
> - **Defina `SOURCE_CODE_URL`** apontando para o repositório desta instância.
>   A AGPLv3 (seção 13) exige que usuários que acessam o app pela rede possam
>   obter o código-fonte correspondente, incluindo suas modificações.

## Licença

Distribuído sob a [AGPLv3](LICENSE), herdada do Maybe Finance. Entre outras
coisas, isso significa que **se você hospedar este software como um serviço
acessível pela rede, precisa disponibilizar o código-fonte aos seus usuários**,
inclusive das modificações que fizer.
