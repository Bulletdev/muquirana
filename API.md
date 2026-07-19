# Muquirana - API v1

API REST para acessar os dados da sua família (contas, transações, etc.) por
programação. Todos os endpoints ficam sob `/api/v1` e retornam JSON.

> **Direção dos dados:** esta API tira os **seus** dados **para fora** (para as
> suas ferramentas: planilha, script, automação, dashboard). **Não é** conexão
> com banco (Open Finance) - isso é feito em **Contas > Adicionar**.

## Base URL

```
https://SEU-HOST/api/v1
```

## Autenticação

Duas formas:

### 1. API key (recomendado para scripts e integrações)

Crie em **Configurações > Chave de API**. Envie no cabeçalho:

```
X-Api-Key: SUA_CHAVE
```

Também aceita `?api_key=SUA_CHAVE` na querystring (útil para o Google Sheets).

### 2. OAuth Bearer (aplicativos)

Obtenha um token em `/api/v1/auth/login` e envie:

```
Authorization: Bearer SEU_ACCESS_TOKEN
```

## Escopos (permissões)

| Escopo | Permite |
|---|---|
| `read` | Ler contas, transações e uso |
| `read_write` | Tudo do `read` + criar, editar e apagar |

Uma chave tem **exatamente um** escopo. `read_write` inclui o acesso de `read`.

## Paginação

Endpoints de lista aceitam `?page=` e `?per_page=` (1 a 100, padrão 25). A
resposta inclui um bloco `pagination`:

```json
{ "page": 1, "per_page": 25, "total_count": 143, "total_pages": 6 }
```

## Limite de requisições (rate limit)

Cada resposta traz cabeçalhos:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 97
X-RateLimit-Reset: 3600
```

Excedeu o limite -> `429 Too Many Requests`.

## Erros

Formato padrão:

```json
{ "error": "unauthorized", "message": "Access token is invalid, expired, revoked, or missing required scope" }
```

| Status | Quando |
|---|---|
| `400` | Parâmetro obrigatório faltando ou inválido |
| `401` | Chave/token inválido, expirado ou sem escopo |
| `404` | Recurso não encontrado |
| `422` | Validação falhou (ex.: criar transação sem conta) |
| `429` | Limite de requisições excedido |
| `500` | Erro interno |

---

## Contas

### `GET /api/v1/accounts`

Lista as contas da família. Escopo: `read`. Paginado.

```bash
curl -H "X-Api-Key: SUA_CHAVE" https://SEU-HOST/api/v1/accounts
```

Resposta `200`:

```json
{
  "accounts": [
    {
      "id": "b1f2...",
      "name": "Nubank",
      "balance": "R$ 1.234,56",
      "currency": "BRL",
      "classification": "asset",
      "account_type": "depository"
    }
  ],
  "pagination": { "page": 1, "per_page": 25, "total_count": 8, "total_pages": 1 }
}
```

---

## Transações

### `GET /api/v1/transactions`

Lista transações. Escopo: `read`. Paginado.

```bash
curl -H "X-Api-Key: SUA_CHAVE" "https://SEU-HOST/api/v1/transactions?page=1&per_page=25"
```

Resposta `200`: `{ "transactions": [ <objeto transação> ], "pagination": { ... } }`.

### Objeto transação

```json
{
  "id": "a1b2...",
  "date": "2026-07-18",
  "amount": "-R$ 42,50",
  "currency": "BRL",
  "name": "Café da manhã",
  "notes": null,
  "classification": "expense",
  "account": { "id": "b1f2...", "name": "Nubank", "account_type": "depository" },
  "category": { "id": "c3d4...", "name": "Alimentação", "classification": "expense", "color": "#e99537", "icon": "utensils" },
  "merchant": { "id": "e5f6...", "name": "Padaria" },
  "tags": [ { "id": "07a8...", "name": "café", "color": "#4da568" } ],
  "transfer": null,
  "created_at": "2026-07-18T10:00:00Z",
  "updated_at": "2026-07-18T10:00:00Z"
}
```

`category`, `merchant` e `transfer` podem ser `null`.

### `GET /api/v1/transactions/:id`

Uma transação pelo id. Escopo: `read`.

### `POST /api/v1/transactions`

Cria uma transação. Escopo: `read_write`.

```bash
curl -X POST -H "X-Api-Key: SUA_CHAVE" -H "Content-Type: application/json" \
  https://SEU-HOST/api/v1/transactions \
  -d '{"transaction":{"account_id":"b1f2...","date":"2026-07-18","amount":-42.50,"name":"Café","currency":"BRL"}}'
```

Campos aceitos em `transaction`:

| Campo | Obrigatório | Observação |
|---|---|---|
| `account_id` | sim | id de uma conta da família |
| `date` | sim | `YYYY-MM-DD` |
| `amount` | sim | número; negativo = despesa, positivo = receita |
| `name` | sim | descrição do lançamento |
| `currency` | não | padrão: moeda da família |
| `notes`, `description` | não | texto livre |
| `category_id`, `merchant_id` | não | ids existentes |
| `tag_ids` | não | lista de ids |
| `nature` | não | natureza do valor |

Resposta `201` com o objeto transação.

### `PUT/PATCH /api/v1/transactions/:id`

Atualiza uma transação. Escopo: `read_write`. Mesmos campos do create.

### `DELETE /api/v1/transactions/:id`

Remove uma transação. Escopo: `read_write`.

---

## Uso da chave

### `GET /api/v1/usage`

Info da chave + estado do rate limit. Escopo: `read`.

```json
{
  "api_key": { "name": "Meu script", "scopes": ["read"], "last_used_at": "...", "created_at": "..." },
  "rate_limit": { "tier": "standard", "limit": 100, "current_count": 3, "remaining": 97, "reset_in_seconds": 3600, "reset_at": "..." }
}
```

---

## Assistente de IA

Escopo: `read_write` (gera custo no provedor de IA configurado na instância).

- `GET /api/v1/chats` - lista as conversas
- `POST /api/v1/chats` - cria uma conversa
- `GET /api/v1/chats/:id` - lê uma conversa e suas mensagens
- `POST /api/v1/chats/:chat_id/messages` - envia uma mensagem
- `POST /api/v1/chats/:chat_id/messages/retry` - reprocessa a última resposta

---

## Autenticação de aplicativos (OAuth)

Para apps nativos, em vez da API key:

- `POST /api/v1/auth/signup` - cria conta (exige código de convite) e devolve tokens
- `POST /api/v1/auth/login` - e-mail + senha -> `access_token` + `refresh_token`
- `POST /api/v1/auth/refresh` - troca o `refresh_token` por um novo `access_token`

---

## Exemplo: Google Sheets

O export CSV de transações aceita `?api_key=`, então dá para puxar direto numa
planilha:

```
=IMPORTDATA("https://SEU-HOST/reports/export_transactions?api_key=SUA_CHAVE")
```
