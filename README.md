# Desafio técnico e-commerce — Carrinho de compras

API Rest em Ruby on Rails para gerenciamento de um carrinho de compras de e-commerce, desenvolvida como resposta ao desafio técnico da RD Station descrito na seção [Enunciado original](#enunciado-original).

As decisões técnicas por trás da modelagem, das validações e do job de abandono estão documentadas em [DECISIONS.md](./DECISIONS.md).

## Stack

- Ruby 3.3.1
- Rails 7.1.3.2
- PostgreSQL 16
- Redis 7.0.15
- Sidekiq + sidekiq-scheduler (job de carrinhos abandonados)

## Como executar

### Com Docker (recomendado)

```bash
docker compose up --build
```

Isso sobe `db` (Postgres), `redis`, `web` (Rails na porta `3000`, com `db:create db:migrate` automático) e `sidekiq` (worker + scheduler do job de abandono).

### Sem Docker

Com Ruby 3.3.1, Postgres 16 e Redis 7.0.15 instalados e configurados:

```bash
bundle install
bundle exec rails db:create db:migrate
bundle exec sidekiq      # worker + scheduler, em um terminal
bundle exec rails server # em outro terminal
```

## Testes

```bash
bundle exec rspec
```

ou, via Docker, usando o serviço `test` do compose (sobe banco de teste, roda migrations e a suíte):

```bash
docker compose run --rm test
```

## Endpoints

### `GET /cart`

Retorna o carrinho da sessão atual. Se não houver carrinho na sessão, retorna um carrinho vazio sem persistir nada no banco.

**Response**
```json
{
  "id": 789,
  "products": [
    { "id": 645, "name": "Nome do produto", "quantity": 2, "unit_price": 1.99, "total_price": 3.98 }
  ],
  "total_price": 3.98
}
```

### `POST /cart`

Adiciona um produto ao carrinho. Se não existir carrinho na sessão, cria um e salva o `id` na sessão. Se o produto já estiver no carrinho, soma a quantidade em vez de duplicar o item.

**Payload**
```json
{ "product_id": 345, "quantity": 2 }
```

Retorna o mesmo formato de `GET /cart`. `product_id` inexistente responde `404`; `quantity` menor ou igual a zero responde `422`.

### `POST /cart/add_item`

Altera a quantidade de um produto no carrinho (soma à quantidade existente, ou cria o item se ainda não estiver no carrinho). Mesmo contrato de payload/response de `POST /cart`. Também disponível em `POST /cart/add_items`.

### `DELETE /cart/:product_id`

Remove um produto do carrinho atual. Se o produto não estiver no carrinho, responde `422` com uma mensagem de erro. Após a remoção, retorna o carrinho atualizado (podendo ficar com `products: []` e `total_price: 0`).

### Carrinhos abandonados

Um job (`MarkCartAsAbandonedJob`) roda a cada hora via `sidekiq-scheduler`:

- Marca como abandonado (`abandoned: true`, `abandoned_at` preenchido) todo carrinho sem interação (adição/remoção de item) há mais de 3 horas.
- Remove definitivamente carrinhos marcados como abandonados há mais de 7 dias.

## Enunciado original

> A equipe de engenharia da RD Station tem alguns princípios nos quais baseamos nosso trabalho diário. Um deles é: projete seu código para ser mais fácil de entender, não mais fácil de escrever.
>
> Portanto, para nós, é mais importante um código de fácil leitura do que um que utilize recursos complexos e/ou desnecessários.

O que era esperado:

- Código fácil de ler (Clean Code).
- Notas gerais sobre versão da linguagem e demais informações para executar o código.
- Código que se preocupa com performance (complexidade de algoritmo).
- **O código deve cobrir todos os casos de uso presentes no README, mesmo que não haja um teste implementado para tal.** A adição de novos testes é sempre bem-vinda.
- Link do repositório público com a aplicação desenvolvida.

### O desafio — Carrinho de compras

API Rest em Ruby/Rails com 3 endpoints, implementando:

1. **Registrar um produto no carrinho** — `POST /cart`. Se não existir um carrinho para a sessão, criar o carrinho e salvar o ID na sessão. Adicionar o produto e devolver o payload com a lista de produtos do carrinho atual.
2. **Listar itens do carrinho atual** — `GET /cart`.
3. **Alterar a quantidade de produtos no carrinho** — `POST /cart/add_item`. Um carrinho pode ter *N* produtos; se o produto já existir no carrinho, apenas a quantidade dele deve ser alterada.
4. **Remover um produto do carrinho** — `DELETE /cart/:product_id`. Verificar se o produto existe no carrinho antes de remover; se não estiver, retornar erro apropriado; após remover, retornar o payload atualizado, lidando corretamente com o carrinho ficando vazio.
5. **Excluir carrinhos abandonados** — um carrinho é considerado abandonado sem interação (adição ou remoção de produtos) há mais de 3 horas. Se abandonado há mais de 7 dias, o carrinho deve ser removido. Um job deve gerenciar (marcar como abandonado e remover) esses carrinhos, configurado para rodar nos períodos especificados.

Itens adicionais / legais de ter:

- Uso de factory na construção dos testes.
- Dockerização da aplicação (`docker-compose.yml`).
- Tratamento de erros para situações excepcionais válidas (ex: produto não pode ter quantidade negativa).
