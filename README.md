```
███╗   ███╗██╗   ██╗ ██████╗ ██╗   ██╗██╗██████╗  █████╗ ███╗   ██╗ █████╗ 
████╗ ████║██║   ██║██╔═══██╗██║   ██║██║██╔══██╗██╔══██╗████╗  ██║██╔══██╗
██╔████╔██║██║   ██║██║   ██║██║   ██║██║██████╔╝███████║██╔██╗ ██║███████║
██║╚██╔╝██║██║   ██║██║▄▄ ██║██║   ██║██║██╔══██╗██╔══██║██║╚██╗██║██╔══██║
██║ ╚═╝ ██║╚██████╔╝╚██████╔╝╚██████╔╝██║██║  ██║██║  ██║██║ ╚████║██║  ██║
╚═╝     ╚═╝ ╚═════╝  ╚══▀▀═╝  ╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝
              Finanças pessoais em português - muquirana.com
```

<div align="center">

[![Security Audit](https://github.com/Bulletdev/muquirana/actions/workflows/security.yml/badge.svg)](https://github.com/Bulletdev/muquirana/actions/workflows/security.yml)
[![Version](https://img.shields.io/badge/version-0.7.0-B91C1C)](https://github.com/Bulletdev/muquirana/releases/tag/v0.7.0)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/9ff898d73e5048f681dc483bf3ae0edf)](https://app.codacy.com/gh/Bulletdev/muquirana/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)

[![Ruby Version](https://img.shields.io/badge/ruby-3.4.8-CC342D?logo=ruby)](https://www.ruby-lang.org/)
[![Rails Version](https://img.shields.io/badge/rails-7.2.3.1-CC342D?logo=rubyonrails)](https://rubyonrails.org/)
[![Hotwire](https://img.shields.io/badge/Hotwire-Turbo%20%2B%20Stimulus-5CD8E5?logo=hotwire)](https://hotwired.dev/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16+-blue.svg?logo=postgresql)](https://www.postgresql.org/)
[![Redis](https://img.shields.io/badge/Redis-7-DC382D?logo=redis)](https://redis.io/)
[![PWA](https://img.shields.io/badge/PWA-installable-5A0FC8?logo=pwa)](https://web.dev/progressive-web-apps/)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

</div>

---

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  MUQUIRANA - Ruby on Rails 7.2 · Hotwire · PWA                               ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  App de finanças pessoais em pt-BR, self-hosted.                             ║
║  Monolito server-side · Sem CORS · Sem build de front · Instalável no celular║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

<details>
<summary><kbd>▶ Funcionalidades (clique para expandir)</kbd></summary>

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  [■] Contas               - Corrente, poupança, cartão, investimento, cripto│
│  [■] Patrimônio           - Série histórica de saldos e evolução no tempo   │
│  [■] Transações           - Categorias, etiquetas, estabelecimentos e regras│
│  [■] Orçamento            - Metas por categoria e acompanhamento mensal     │
│  [■] Investimentos        - Posições, negociações e cotação de ativos       │
│  [■] Importação CSV       - Mapeamento de colunas por arquivo               │
│  [■] Multi-família        - Contas compartilhadas com escopo por família    │
│  [■] Multi-moeda          - Conversão com taxas históricas                  │
│  [■] Sincronização Plaid  - Bancos US/EU (opcional; não atende banco BR)    │
│  [■] Assistente de IA     - Conversa sobre as finanças (chave OpenAI sua)   │
│  [■] PWA                  - Instalável na tela inicial, sem loja de apps    │
│  [■] API v1               - OAuth2 (Doorkeeper) + API keys com escopo       │
└─────────────────────────────────────────────────────────────────────────────┘
```

</details>

---

## Table of Contents

```
┌──────────────────────────────────────────────────────┐
│  01 · Quick Start                                    │
│  02 · Technology Stack                               │
│  03 · Arquitetura                                    │
│  04 · Configuração                                   │
│  05 · Deploy                                         │
│  06 · Segurança                                      │
│  07 · Development                                    │
└──────────────────────────────────────────────────────┘
```

---

## 01 · Quick Start

Requisitos: Ruby (ver `.ruby-version`) e Docker (para subir Postgres + Redis).
Prefere rodar Postgres/Redis próprio? Veja "Sem Docker" abaixo.

```sh
cp .env.local.example .env.local
bin/setup   # instala gems, sobe Postgres+Redis, prepara o banco e popula a demo
bin/dev     # sobe os serviços (se preciso) e a aplicação
```

Pronto: **http://localhost:3000**. Na primeira vez o `bin/dev` popula dados de
demonstração automaticamente — entre com **`user@muquirana.local` / `password`**,
ou use **http://localhost:3000/demo** (login sem senha).

O `bin/dev` cuida de tudo: sobe o Postgres e o Redis (`compose.dev.yml`, portas
dedicadas 5434/6380 para não colidir com outros projetos), roda as migrations e,
só na primeira vez (banco vazio), gera os dados de demonstração.

**Sem Docker** — suba Postgres e Redis por conta própria e ajuste `DB_HOST`,
`DB_PORT` e `REDIS_URL` no `.env.local`; o `bin/dev` detecta a ausência do Docker
e segue direto para a aplicação.

**Porta ocupada** (`connection refused` / `port is already allocated`) — algum
outro Postgres/Redis está na mesma porta. Troque `DB_PORT`/`REDIS_URL` no
`.env.local` e o mapeamento em `compose.dev.yml`, depois
`docker compose -f compose.dev.yml up -d`.

---

## 02 · Technology Stack

```
┌──────────────────┬──────────────────────────────────────────────────────────┐
│  Runtime         │  Ruby 3.4.8                                              │
│  Framework       │  Rails 7.2.3.1 (monolito, não API-only)                  │
│  Front           │  Hotwire - Turbo + Stimulus + ViewComponent              │
│  Estilo          │  Tailwind CSS 4 · design system próprio                  │
│  Banco           │  PostgreSQL 16                                           │
│  Jobs            │  Sidekiq 8 + sidekiq-cron · Redis 7                      │
│  Auth (web)      │  Sessão via cookie assinado                              │
│  Auth (API)      │  Doorkeeper OAuth2 + API keys com escopo                 │
│  Gráficos        │  D3.js                                                   │
│  Testes          │  Minitest + fixtures · VCR · Capybara                    │
└──────────────────┴──────────────────────────────────────────────────────────┘
```

---

## 03 · Arquitetura

Monolito server-side. O Rails entrega o HTML; o Turbo troca fragmentos de página
sem recarregar. **Não há front desacoplado, build de JS nem CORS** - HTML e JSON
saem da mesma origem.

```
┌──────────────┐     HTML / Turbo Streams      ┌──────────────────────────────┐
│   Browser    │ ◄───────────────────────────► │  Rails 7.2 (Puma)            │
│   PWA        │        WebSocket (cable)      │  ├─ Views ERB + ViewComponent│
└──────────────┘                               │  ├─ Stimulus controllers     │
                                               │  └─ /api/v1 (Jbuilder)       │
                                               └───────────┬──────────────────┘
                                                           │
                              ┌────────────────────────────┼──────────────┐
                              ▼                            ▼              ▼
                     ┌────────────────┐          ┌──────────────┐  ┌────────────┐
                     │  PostgreSQL    │          │  Redis       │  │  Sidekiq   │
                     │  dados         │          │  cache/cable │  │  sync/jobs │
                     └────────────────┘          └──────────────┘  └────────────┘
```

Convenções: lógica de negócio nos models (`app/models/`), não em `app/services/`.
Escopo multi-tenant por `Current.family` - não há `default_scope` de tenant, então
toda query precisa partir da família. Detalhes em [`CLAUDE.md`](CLAUDE.md).

---

## 04 · Configuração

```
┌────────────────────────┬────────────────────────────────────────────────────┐
│  SELF_HOSTED           │  true - desliga assinatura/Stripe                  │
│  SECRET_KEY_BASE       │  obrigatório · openssl rand -hex 64                │
│  DB_HOST / DB_PORT     │  Postgres                                          │
│  POSTGRES_USER/PASSWORD│  Postgres                                          │
│  REDIS_URL             │  Sidekiq e Action Cable                            │
│  APP_DOMAIN            │  host canônico - usado nos links de e-mail         │
│  SOURCE_CODE_URL       │  link do código no rodapé (AGPLv3 §13)             │
│  GITHUB_REPO_OWNER/NAME│  tela "Novidades" · sem isso, não busca nada       │
│  OPENAI_ACCESS_TOKEN   │  opcional - habilita o assistente de IA            │
│  PLAID_CLIENT_ID/SECRET│  opcional - sincronização bancária US/EU           │
│  FRANKFURTER_URL       │  opcional - instância própria do Frankfurter       │
│  SYNTH_URL             │  opcional - instância própria do Synth (ver 04.1)  │
│  DEMO_URL              │  opcional - mostra "Ver a demo" na landing         │
│  DEMO_INSTANCE         │  true SÓ na instância de demo (ver 04.2)           │
└────────────────────────┴────────────────────────────────────────────────────┘
```

O assistente de IA lê `OPENAI_ACCESS_TOKEN` **da variável de ambiente**, não do
banco: não há tela para configurá-lo. Além da chave, cada pessoa precisa aceitar
o uso de IA na própria conta (`ai_enabled`), que nasce desligado.

### 04.1 · Cotações de câmbio e preços de ativos

**Câmbio funciona automaticamente, sem configurar nada.** As cotações vêm da API
do [Frankfurter](https://frankfurter.dev) - livre, sem chave, com dados do Banco
Central Europeu. Cobre a maioria das moedas; uma moeda que ela não publica
degrada com aviso (sem saldo histórico para aquela conta). Para apontar a uma
instância própria do Frankfurter (ele é self-hostable), use `FRANKFURTER_URL`.

**Preço de ação e fundo é que não tem provedor público.** Vinha da API Synth,
**descontinuada junto com o projeto Maybe**: `api.synthfinance.com` não resolve
mais. Sem ela, contas de investimento ficam sem valor histórico - o resto do app
funciona normal. O Synth era open source; para tê-lo de volta, suba a sua a
partir do [código arquivado](https://github.com/maybe-finance/synth-archive) e
aponte `SYNTH_URL` para ela. **Não existe cadastro para o qual apontar** - o
`synthdata.co`, que aparece nas buscas, é outra empresa (dados sintéticos de
previsão), sem relação com esta API.

### 04.2 · Instância de demonstração

`DEMO_INSTANCE=true` faz duas coisas, e **nenhuma delas é segura numa instância
com dado real**:

1. expõe `/demo`, que cria sessão **sem senha** como a conta de demonstração;
2. libera `bin/rails demo:reset`, que **apaga todas as famílias do banco**.

Use só num deploy dedicado, com banco próprio. Na instância pessoal, deixe a
variável vazia e aponte `DEMO_URL` para a URL `/demo` da outra instância - a
landing só mostra o botão da demo quando `DEMO_URL` existe.

---

## 05 · Deploy

Docker, atrás de proxy reverso com TLS. Ver [`docs/hosting/docker.md`](docs/hosting/docker.md).

Por ser monolito same-origin, o deploy é **um container** com um roteador
apontando o domínio para a porta 3000. Não há CORS a configurar.

```
Cloudflare (proxy, SSL Full strict)
      │
      ▼
Traefik  ──►  muquirana:3000  ──►  postgres · redis · sidekiq
```

> [!WARNING]
> - `SSL/TLS` no Cloudflare precisa ser **Full (strict)**. Em *Flexible*, o
>   Cloudflare fala HTTP com o origin e o Rails com `force_ssl` entra em
>   redirect loop infinito.
> - Desligue o **Rocket Loader** - ele reordena scripts e quebra Turbo/Stimulus.
> - **Nunca** faça cache de HTML na CDN: as páginas têm token CSRF e conteúdo por
>   usuário.
> - `RAILS_ASSUME_SSL=true` para o Rails confiar no `X-Forwarded-Proto` do proxy.

---

## 06 · Segurança

O projeto original foi arquivado em jul/2025 e não publica mais correções - elas
são responsabilidade deste repositório.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  [■] bundler-audit         - Gate obrigatório no CI + varredura diária      │
│  [■] Brakeman              - Análise estática a cada PR                     │
│  [■] AR Encryption         - access_token bancário e API key cifrados       │
│  [■] Rack::Attack          - Rate limiting na API                           │
│  [■] Escopo por família    - Validado inclusive nas FKs de transação        │
└─────────────────────────────────────────────────────────────────────────────┘
```

Três vulnerabilidades críticas herdadas foram corrigidas, cada uma com teste de
regressão: token OAuth revogado que continuava autenticando (toda revogação do
app era inoperante), vazamento de dados entre famílias por chave estrangeira não
validada, e token de acesso bancário gravado em texto plano. 165 alertas de
vulnerabilidade em dependências foram zerados.

Depois disso, mais quatro, também herdadas e também com teste:

- **XSS armazenado** no diálogo de confirmação. O nome de um estabelecimento ou
  de um usuário era interpolado no corpo e escrito via `innerHTML`; o Rails
  escapava no `data-attribute` - o que fazia o HTML *parecer* seguro - mas o
  `JSON.parse` no controller desfazia o escape antes de executar.
- **Escalada de privilégio** em `Settings::Hostings`: um membro comum
  reconfigurava a instância inteira (inclusive reabrir o cadastro público).
- **Códigos de convite expostos** a qualquer usuário logado. Listar código é, na
  prática, poder convidar - agora é só do admin.
- **Convite queimado por cadastro que falhava**: o código era consumido antes do
  save, então uma senha fraca na primeira tentativa matava o link para sempre.

Todas as actions do GitHub são pinadas por SHA de commit: tag é mutável, e o
workflow tem `GITHUB_TOKEN` e publica a imagem. Ver
[docs/codacy-prd.md](docs/codacy-prd.md) para a triagem completa dos alertas
estáticos, incluindo o que é falso positivo e por quê.

> [!WARNING]
> Gere um `SECRET_KEY_BASE` próprio antes de expor a instância. **Nunca** use o
> valor de exemplo do `compose.example.yml` - ele é público. Em modo self-hosted
> esse mesmo segredo deriva as chaves de criptografia do banco: quem o obtiver lê
> os tokens de acesso bancário e as chaves de API.

> [!IMPORTANT]
> **O suporte ao Rails 7.2 termina em 09/08/2026.** A partir dessa data, uma CVE
> no framework não recebe correção oficial - e o projeto original, arquivado, não
> vai fazer esse upgrade. Subir para o Rails 8 é trabalho deste repositório e
> está planejado como ciclo próprio, separado do rebranding/i18n desta versão.
> O Brakeman acusa esse prazo; a dívida está registrada em
> [`config/brakeman.ignore`](config/brakeman.ignore) com data e instrução de
> remoção, em vez de silenciada.

---

## 07 · Development

```sh
bin/rails test                  # suíte completa
bin/rails test:system           # system tests (mais lentos)
bin/rubocop                     # lint Ruby
bundle exec erb_lint ./app/**/*.erb
bin/brakeman --no-pager         # análise estática
bundle exec bundler-audit check --update
bundle exec i18n-tasks missing  # chaves de tradução faltando
bundle exec i18n-tasks unused   # chaves órfãs
```

Antes de abrir PR: testes, rubocop, erb_lint e brakeman precisam passar.
Convenções e arquitetura em [`CLAUDE.md`](CLAUDE.md).

### Traduções

`pt-BR` é o locale padrão e `en` é o fallback de tudo (`config/application.rb`).
Strings de UI ficam em `config/locales/views/**`; rótulo que nasce em model ou
helper (tipo de conta, período, categoria padrão) fica em `config/locales/models/**`.

Dois cuidados que já custaram bug aqui:

- **`i18n-tasks missing` não enxerga string hardcoded.** Ele só compara chaves já
  chamadas via `t()` - um literal em ERB é invisível para ele. Zero "missing" não
  significa tela traduzida.
- **Não derive o singular do plural.** `String#singularize` usa regra de inflexão
  do inglês e destrói português ("Imóveis" → "Imóvei"). As duas formas têm chave
  própria: `display_name` e `display_name_singular`.

---

**Última atualização**: 2026-07-15 · **Versão**: 0.7.0
**Ruby**: 3.4.8 · **Rails**: 7.2.3.1
**Locale padrão**: pt-BR · **Moeda**: BRL · **Fallback**: en

---

<details>
<summary><kbd>▶ Fork do Maybe Finance · não afiliado nem endossado · AGPLv3 (clique para expandir)</kbd></summary>

<br>

O Muquirana é um fork do [Maybe Finance](https://github.com/maybe-finance/maybe),
derivado do commit `77b5469` (tag `v0.6.0`) em **14/07/2026** e mantido de forma
independente desde então.

**Não é afiliado, mantido, patrocinado nem endossado pela Maybe Finance, Inc.**
"Maybe" é marca registrada da Maybe Finance, Inc., citada aqui exclusivamente
para atribuir a autoria do trabalho original - não como marca deste projeto.
Nenhum asset de marca do projeto original é distribuído aqui.

O projeto original foi arquivado em julho de 2025, na
[versão v0.6.0](https://github.com/maybe-finance/maybe/releases/tag/v0.6.0).
Defeitos, alterações e decisões deste repositório são de responsabilidade dele,
não do original.

Distribuído sob a [licença AGPLv3](LICENSE), preservada integralmente nos mesmos
termos do original. Entre outras coisas, isso significa que **hospedar este
software como serviço acessível pela rede obriga a disponibilizar o código-fonte
aos usuários**, inclusive das modificações feitas.

</details>
