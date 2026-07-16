# PRD: Muquirana v0.8

**Status:** proposto
**Data:** 2026-07-16
**Versão de partida:** v0.7.0 (979 testes, no ar em muquirana.com)

## Contexto

A v0.7.0 fez o trabalho de fork: rebranding, tradução pt-BR, self-hosting no
Coolify, e uma pilha de correções de segurança e de bugs herdados do Maybe. Ao
longo dela, várias coisas foram **descobertas e adiadas de propósito** por
serem escopo próprio. Este documento junta essas pendências, mais o que a
operação em produção revelou, e propõe a v0.8.

O princípio segue o mesmo: **não inventar funcionalidade**. Quase tudo aqui é
fechar o que ficou pela metade, decidir o que ficou em aberto, ou pagar dívida
que já está cobrando juros.

## Objetivo da v0.8

Deixar o Muquirana **operável por terceiros sem asterisco**: quem clona e
hospeda a própria instância não deve esbarrar em serviço morto, funcionalidade
que não funciona, ou tela que promete o que o app não entrega. Hoje ainda
esbarra em alguns.

## Não-objetivo

- Funcionalidade nova de produto (open banking, relatórios novos, metas). O app
  faz o que promete; a v0.8 é sobre fazer o que promete **bem**, não fazer mais.
- Reescrever o que veio do upstream só por gosto. Herança que funciona fica.

---

## Frente 1 - Fechar o laço da infraestrutura (bloqueante)

A v0.7.0 terminou com correções de deploy que **só existem no repositório**. A
operação real expôs problemas que o desenvolvimento não pega.

### 1.1 - Instância de demo, no ar

O código da demo está pronto e testado (`/demo`, `Demo::DataCleaner` com guarda
`DEMO_INSTANCE`, `demo:reset`), mas **nenhuma instância foi provisionada**. O
botão "Ver a demo" na landing depende de `DEMO_URL`, que não existe.

- Subir `demo.muquirana.com` no Coolify: app + Postgres + Redis próprios,
  `DEMO_INSTANCE=true`, `OPENAI_ACCESS_TOKEN` **vazia** (senão a demo vira
  ChatGPT público pago pelo dono).
- Cron de `demo:reset` para a demo não acumular lixo de visitante.
- `DEMO_URL=https://demo.muquirana.com/demo` na instância principal.

Pronto quando: a landing mostra o botão, o clique cai no painel com dados de
demonstração, e o reset roda sozinho.

### 1.2 - Cache compartilhado (`CACHE_REDIS_URL`)

Confirmado em produção: o compose **não define `CACHE_REDIS_URL`**, então o
Rails cai no cache em memória por processo. Com `WEB_CONCURRENCY=2`, cada worker
do Puma tem o próprio cache, e ele morre a cada deploy. O `net_worth_series` é
`Rails.cache.fetch` - é candidato ao gráfico de patrimônio inconsistente.

- Apontar `CACHE_REDIS_URL` para o `muquirana-redis` (mesmo Redis do Sidekiq,
  database separado).

Pronto quando: o cache sobrevive ao deploy e é o mesmo entre os processos Puma.

### 1.3 - Patrimônio somando parte das contas (diagnóstico)

Sintoma observado: "Ativos R$22.500" mas "Patrimônio R$7.000". A matemática
(`net_worth = assets − liabilities`) aponta para contas classificadas como
passivo, OU sync que não rodou (o que a colisão de Redis, já corrigida,
causava). Precisa de diagnóstico **em produção com o Redis já isolado**, com o
`rails runner` de contas por classificação. Pode ser dado, não código - mas não
foi confirmado.

Pronto quando: sabemos se é classificação (dado) ou cálculo (código), e a causa
está documentada ou corrigida.

---

## Frente 2 - Terminar a triagem de segurança do Codacy

O PRD do Codacy (`docs/codacy-prd.md`) fechou os itens confirmados, mas deixou
três **explicitamente não investigados**. A lição daquele documento foi que
grep não é análise de alcance: o XSS "não explorável" era real. Estes três
merecem o mesmo cuidado.

### 2.1 - `insertAdjacentHTML` em rules_controller.js e conditions_controller.js

Confirmado que existem (`rules_controller.js:49`,
`rule/conditions_controller.js:20`). Ambos montam HTML de um `<template>` e
injetam. Verificar se o conteúdo do template pode conter dado do usuário (nome
de regra, valor de condição) como no XSS já corrigido do confirm dialog.

### 2.2 - Redirects com input do usuário (4 ocorrências)

`redirect_to` com `params`/`return_to`. Triar caso a caso: `return_to` que
aceite URL absoluta é open redirect.

### 2.3 - CRITICAL de reflexão

"Found user-controllable input to a reflection method". Reflexão com input é a
classe que vira RCE quando é real. Não foi olhado.

### 2.4 - Supressões, com justificativa

Depois de confirmar 2.1-2.3, aplicar o `.codacy.yml` + `# nosemgrep` para os
falsos positivos já triados (find escopado, unicode de ml/fa, md5 de cache),
seguindo a convenção da prostaff-api. Cada supressão com comentário.

Pronto quando: zero CRITICAL/HIGH de Security que não esteja corrigido ou
justificado no código.

---

## Frente 3 - Preencher (ou remover) o buraco do Synth

O Synth foi descontinuado: `api.synthfinance.com` não resolve. Ele é o **único**
provedor de câmbio e preço de ativos (3 chamadas fixas a `get_provider(:synth)`).
Sem ele, contas em outra moeda ou com investimentos ficam sem saldo histórico.
Hoje o app degrada com elegância e avisa, mas a funcionalidade está morta.

Decisão de produto necessária, três caminhos:

- **A) Não fazer nada além do aviso** (estado atual). Honesto, custo zero. Quem
  usa só BRL não perde nada.
- **B) Provedor de câmbio brasileiro.** O Banco Central tem API pública e
  gratuita (SGS / PTAX) para cotação de moeda. Cobre a maior parte do caso de
  uso pt-BR (dólar, euro). Não cobre preço de ação. Escopo médio: um
  `Provider::Bcb` implementando o mesmo contrato do `Provider::Synth`.
- **C) Tornar o provedor plugável de verdade** e documentar como apontar
  `SYNTH_URL` para um fork do synth-archive. Escopo baixo, resolve para quem
  quer, não resolve para a maioria.

Recomendação: **B para câmbio** (é o que mais gente usa em BRL) e deixar preço
de ativo como conhecido-faltante. Mas é decisão do dono.

Pronto quando: ou existe um provedor vivo de câmbio, ou a decisão de manter só o
aviso está registrada e a UI não promete o que não entrega.

---

## Frente 4 - Deixar a demo apresentável

A demo vai ser a vitrine (o vídeo, quem chega pela landing). Hoje ela tem duas
manchas herdadas do gerador do Maybe.

### 4.1 - Categorias em inglês

`Demo::Generator` cria **21 categorias hardcoded em inglês** (Salary, Housing,
Food & Dining, Loan Interest...). Numa demo pt-BR isso aparece na cara. Traduzir
para os nomes que o `Category.default_categories` já usa.

Cuidado verificado nesta sessão: conferir se algum código referencia essas
categorias por nome (`find_by(name: "Salary")`) antes de traduzir, senão quebra
o seed.

### 4.2 - Nomes "Demo (admin) Muquirana"

O usuário e a família da demo se chamam "Demo (admin)", "Demo Family". Tornar
configuráveis por env (`DEMO_ADMIN_NAME`) para a demo pública nascer com nome
apresentável, sem editar na UI a cada reset.

Pronto quando: a demo, recém-semeada, está inteira em pt-BR e com nomes que não
gritam "isto é um seed".

---

## Frente 5 - Idioma es: completar ou remover

O `es` está em `available_locales` mas tem **1846 chaves faltando** - a tela sai
em inglês. Já foi deixado fora do seletor de idioma do visitante de propósito
(oferecer idioma que não existe é a desinformação que tiramos da landing).

Duas saídas:

- **Traduzir** o es de verdade (1846 chaves é trabalho real, mas mecânico).
- **Remover** o es de `available_locales` até ele existir. Menos promessa
  quebrada.

Recomendação: **remover** por ora. Um idioma meio-feito é pior do que dois bem
feitos. Volta quando alguém traduzir.

Pronto quando: todo locale em `available_locales` renderiza a UI completa no
próprio idioma.

---

## Frente 6 - Dívida de dependências

Há **20 PRs abertos**, quase todos Dependabot, alguns com CI falhando. Isso não
é cosmético: dependência velha é onde CVE mora, e um backlog de 20 PRs vira um
muro que ninguém escala.

- Triar os 20: mesclar os verdes, corrigir ou fechar os vermelhos com motivo.
- Configurar o Dependabot para agrupar patches (menos PRs, menos ruído).
- Aviso conhecido: as actions pinadas por SHA usam Node 20, que o GitHub está
  depreciando. Atualizar os SHAs para versões em Node 24.

Pronto quando: menos de 5 PRs abertos e nenhum com CI vermelho sem motivo
escrito.

---

## Sequenciamento sugerido

1. **Frente 1** (infra) primeiro: é o que trava a demo e pode estar por trás do
   patrimônio errado. Rápido e alto impacto.
2. **Frente 2** (segurança) em paralelo: independente do resto, e é risco.
3. **Frente 4** (demo apresentável) junto da 1.1, porque a demo só faz sentido
   com as duas.
4. **Frente 6** (dependências) pode rodar em background o tempo todo.
5. **Frentes 3 e 5** dependem de decisão do dono; destravar cedo.

## Critério de corte da v0.8

A v0.8 sai quando:

- a demo está no ar, em pt-BR, e o botão da landing funciona;
- não há CRITICAL/HIGH de segurança em aberto sem justificativa;
- o cache de produção é compartilhado e persistente;
- todo idioma oferecido renderiza completo;
- o backlog de dependências está sob controle;
- e a decisão sobre o Synth (câmbio) está tomada e refletida na UI.

## Riscos

- **Renomear as categorias da demo** pode quebrar o seed se houver referência
  por nome. Verificar antes (já sabemos que isto morde).
- **Deploy da demo na mesma VPS** compartilha a rede `coolify` com a instância
  principal e a prostaff. A colisão de nomes de serviço já mordeu uma vez; a
  demo tem que usar nomes próprios (`demo-postgres`, `demo-redis`) desde o
  primeiro deploy.
- **Provedor de câmbio (Frente 3B)** é a única frente com código novo de
  integração externa. Tem custo de manutenção: uma API do BCB que mude quebra o
  saldo histórico. Pesar contra o benefício antes de começar.
