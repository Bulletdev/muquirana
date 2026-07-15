# PRD: tratar os apontamentos do Codacy

**Status:** proposto
**Data:** 2026-07-15
**Base:** varredura do Codacy com 372 apontamentos (`codacyissues.md`)

## Resumo

O Codacy aponta 372 problemas, sendo 83 de Security. O numero assusta e o
painel fica vermelho, mas a triagem mostra outra coisa: **a maior parte dos
alertas de seguranca e falso positivo**, e o trabalho real e pequeno e
concentrado.

Este documento existe para o time nao gastar semanas corrigindo ruido, nem
ignorar o punhado de coisas que importa.

## O que a varredura diz

| severidade | quantidade |
|---|---|
| CRITICAL | 5 |
| HIGH | 86 |
| MEDIUM | 65 |
| MINOR | 216 |

| categoria | quantidade |
|---|---|
| Code style | 175 |
| Security | 83 |
| Best practice | 40 |
| Code complexity | 27 |
| Comprehensibility | 20 |
| Unused code | 16 |
| Error prone | 9 |

Os 83 de Security se dividem em: Insecure Modules Libraries (46), XSS (19),
Malicious Code (12), Insecure Storage (3), Routes (2), Cryptography (1).

## Triagem: o que e falso positivo

Cada item abaixo foi verificado no codigo, nao presumido.

### `find` sem escopo (35 apontamentos) - FALSO POSITIVO

O Codacy acusa "Avoid Unscoped find with User-Controllable Input" em coisas
como `accountable_resource.rb:78`:

```ruby
@account = Current.family.accounts.find(params[:id])
```

Isso **e** escopado: a busca parte de `Current.family`, entao `params[:id]` so
alcanca contas da propria familia. A ferramenta ve `find(params[:id])` e nao
entende o receiver.

Evidencia da varredura no app: **42 finds escopados por `Current.family`, zero
ocorrencias de `Model.find(params[...])` solto** em `app/controllers/`.

Acao: silenciar o padrao, nao "corrigir" o codigo.

### Unicode invisivel / "Malicious Code" (12) - FALSO POSITIVO

Concentrados em `config/locales/defaults/ml.yml` (malaiala) e `fa.yml` (persa).
O alerta sugere instrucao maliciosa escondida em caractere invisivel.

Os unicos caracteres invisiveis nesses arquivos sao:

- `U+200C` ZERO WIDTH NON-JOINER (persa: 5, malaiala: 3)
- `U+200D` ZERO WIDTH JOINER (malaiala: 4)

Sao **parte da ortografia** dessas linguas, nao escondem texto. Um ataque
*trojan source* de verdade usa bidi override (`U+202A`-`U+202E`), e **nao ha
nenhum** nesses arquivos.

Acao: silenciar para `config/locales/defaults/`. Manter o padrao ligado no
resto do repo, onde ele tem valor.

### md5 (1 CRITICAL) - FALSO POSITIVO

`income_statement.rb:116`:

```ruby
sql_hash = Digest::MD5.hexdigest(transactions_scope.to_sql)
```

E **chave de cache**, nao controle de seguranca. MD5 sendo fraco contra colisao
nao importa aqui: ninguem ganha nada colidindo uma chave de cache de SQL. Trocar
por SHA-256 nao aumenta seguranca nenhuma e invalida o cache existente.

Acao: silenciar nesta linha, com comentario explicando por que.

## Triagem: o que e real

### 1. XSS latente em `innerHTML` / `insertAdjacentHTML` (3 CRITICAL + 16 HIGH)

Arquivos: `confirm_dialog_controller.js`, `rules_controller.js`,
`rule/conditions_controller.js`.

`confirm_dialog_controller.js:40-41` mostra bem o problema:

```js
this.titleTarget.textContent = data.title || "Are you sure?";   // seguro
this.subtitleTarget.innerHTML = data.body || "...";             // sink
```

**CORRECAO: e exploravel hoje. Confirmado com teste, nao presumido.**

A primeira versao deste documento dizia que o sink nao era alcancavel, com base
em um grep de `turbo_confirm:` nas views. O grep era incompleto: os call sites
perigosos passam `confirm:` para `DS::MenuItem`, que so entao faz
`data.merge(turbo_confirm: confirm.to_data_attribute)`.

A cadeia real:

```
family_merchant.name              <- o usuario escolhe este texto
  -> CustomConfirm.for_resource_deletion(name)
  -> body: "Are you sure you want to delete #{resource_name.downcase}? ..."
  -> to_data_attribute -> data-turbo-confirm='{"body":"..."}'   (Rails escapa)
  -> JSON.parse(el.dataset.turboConfirm)                        (escape desfeito)
  -> subtitleTarget.innerHTML = data.body                       -> EXECUTA
```

Reproduzido: um estabelecimento chamado `<img src=x onerror=...>` dispara o
`onerror` ao abrir o menu de exclusao. Dois call sites alimentam o sink com
dado do usuario: `family_merchants/_family_merchant.html.erb:26`
(`family_merchant.name`) e `settings/profiles/show.html.erb:59`
(`user.display_name`).

O escape do Rails no atributo e o que torna isso dificil de ver: o HTML
inspecionado parece seguro (`<img`). O `JSON.parse` no controller e que
devolve o payload cru.

**Corrigido:** `confirm_dialog_controller.js` passa a usar `textContent`.
Nenhum call site precisa de markup no body. Regressao coberta por
`test/system/confirm_dialog_xss_test.rb`, verificada nos dois sentidos (falha
com `innerHTML`, passa com `textContent`).

Licao para o resto desta lista: **grep nao e analise de alcance**. Os
`insertAdjacentHTML` restantes (`rules_controller.js`,
`rule/conditions_controller.js`) ainda nao foram investigados e nao devem ser
presumidos seguros pelo mesmo motivo.

### 2. Actions do GitHub sem pin de SHA (7 HIGH)

`.github/workflows/publish.yml` e outros usam actions de terceiro por tag
mutavel (`@v4`). Tag pode ser reapontada por quem controla a action, e o
workflow tem acesso ao `GITHUB_TOKEN` e publica a imagem no ghcr.

E o unico risco de **cadeia de suprimentos** da lista, e o unico que atinge o
artefato que vai para producao.

Prioridade: alta. Correcao mecanica e verificavel.

### 3. Redirect com input do usuario (11 HIGH)

Ex.: `redirect_to account_params[:return_to].presence || @account`.

Precisa de triagem caso a caso: `return_to` vindo do formulario pode virar open
redirect se aceitar URL absoluta. Ainda **nao verificado** -- e o proximo passo
de investigacao, nao uma conclusao.

### 4. Reflexao com input do usuario (1 CRITICAL)

"Found user-controllable input to a reflection method" em `app/controllers/`.
**Nao verificado ainda.** Reflexao com input e a classe de bug que vira RCE
quando e real, entao merece olhada antes dos itens de estilo.

## Escopo por fase

### Fase 1: os reais (bloqueante)

1. Pinar actions do GitHub por SHA completo
2. Trocar `innerHTML`/`insertAdjacentHTML` por `textContent` onde o markup nao
   e necessario; onde for, sanitizar
3. Verificar e resolver o item de reflexao (CRITICAL)
4. Triar os 11 redirects; corrigir os que aceitam URL absoluta

Criterio de pronto: zero CRITICAL e zero HIGH de Security que nao tenham sido
explicitamente classificados como falso positivo, com justificativa no codigo.

### Fase 2: calar o ruido (com justificativa escrita)

Configurar o Codacy para desligar, **com comentario dizendo o porque**:

- `Avoid Unscoped find with User-Controllable Input` (35)
- `Detect Invisible Unicode Characters` em `config/locales/defaults/` (12)
- md5 em `income_statement.rb:116` (1)

Criterio de pronto: o painel reflete risco real. Alerta que ninguem age vira
alerta que ninguem le.

### Fase 3: estilo, se sobrar tempo

175 de Code style, majoritariamente markdown (`Enforce Lists/Headings
Surrounded by Blank Lines`, 77 juntos) e CSS (`selector-class-pattern`,
`import-notation`, unidades em zero).

Quase tudo tem auto-fix. Nao bloqueia nada e nao muda comportamento.

Observacao: parte dos alertas de CSS vem de regra mal configurada -- o proprio
Codacy reporta `Unknown rule scss_selector-class-pattern. Did you mean
selector-class-pattern?`. Corrigir a configuracao pode zerar um bloco inteiro
sem tocar em uma linha de codigo.

## Fora de escopo

- Refatorar por `Limit Function Length` (14) e `Cyclomatic Complexity` (8).
  Sao metricas, nao defeitos. Refatorar codigo herdado do upstream so para
  agradar contador de linhas aumenta o risco de regressao sem beneficio.
- Migrar md5 para SHA-256 (ver triagem).
- "Define acronyms and jargon on first use" (12) em documentacao interna.

## Riscos

- **Silenciar demais.** Cada exclusao precisa de justificativa escrita e
  revisada. Regra desligada sem motivo e divida escondida.
- **Falso negativo de escopo.** A conclusao de que nao ha `find` solto vale
  para `app/controllers/` **hoje**. Se o padrao for desligado, nada impede um
  `Account.find(params[:id])` de entrar depois. Mitigacao: manter o Brakeman,
  que entende Rails, como a rede de seguranca real desta classe.

## Como medir

- CRITICAL e HIGH de Security: de 91 para 0 (corrigidos ou justificados)
- Nenhuma regra desligada sem comentario explicando
- CI continua verde (940 testes)
