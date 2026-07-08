# Decisões de Implementação

Este documento reúne o raciocínio por trás das principais escolhas técnicas que fiz ao desenvolver o desafio.

---

## Modelagem do banco de dados

### CartItem como tabela separada, não um campo serializado

Cheguei a considerar guardar os produtos do carrinho como um array JSON numa coluna e descartei essa ideia porque perderia a capacidade de consultar, indexar e validar os dados com a robustez que o banco relacional oferece. Usando `CartItem` como tabela própria, ganho:

- Um índice único em `[cart_id, product_id]`, que garante no banco que um produto nunca aparece duplicado no mesmo carrinho, independente de qualquer bug na aplicação.
- Integridade referencial via foreign keys: um `CartItem` nunca aponta para um produto ou carrinho inexistente.
- Queries eficientes para somar totais, buscar itens específicos, etc.

### total_price armazenado no banco, não calculado na hora

Dava para calcular `total_price` como um método Ruby que soma os itens a cada request, mas isso implica uma query extra toda vez que o carrinho é serializado. Como o total só muda quando um produto é adicionado ou removido, fez mais sentido persistir o valor já calculado e atualizá-lo exatamente nesses momentos — um cache de escrita, na prática.

### abandoned como boolean, não enum ou string de status

O domínio tem exatamente dois estados relevantes: abandonado ou não, por isso escolhi boolean que cobre isso sem ambiguidade. Enum ou string fariam sentido se existissem mais estados (`pending`, `processing`, `completed`...), podemos considerar isso na entrevista final.

### abandoned_at em vez de reaproveitar updated_at

O Rails atualiza `updated_at` automaticamente em qualquer modificação do registro. Se eu usasse esse campo para calcular "abandonado há mais de 7 dias", o prazo resetaria silenciosamente toda vez que qualquer atributo do carrinho mudasse — inclusive quando o próprio `mark_as_abandoned` roda. Um `abandoned_at` dedicado garante que a contagem dos 7 dias começa exatamente no momento em que o carrinho foi marcado como abandonado.

### last_interaction_at pelo mesmo motivo

`updated_at` reflete qualquer alteração no registro, não só interações reais do usuário. Recalcular o total, por exemplo, também atualiza `updated_at` e mascararia o tempo de inatividade de fato. `last_interaction_at` só avança quando o usuário realmente age no carrinho.

---

## Modelagem dos models

### add_product e remove_product concentram a mutação do carrinho no model

Numa versão anterior, o controller manipulava `CartItem` diretamente e chamava `recalculate_total` logo em seguida, em dois passos separados e sem transação. Isso deixava uma janela real de concorrência aberta: duas requisições simultâneas adicionando o mesmo produto podiam ambas encontrar que o item ainda não existia e tentar criar duas linhas, esbarrando no índice único; ou ler a mesma quantidade e perder uma das duas atualizações. Movi essa lógica para `Cart#add_product` e `Cart#remove_product`, que envolvem toda a operação — busca do item, criação ou incremento, e recálculo do total — dentro de um único `with_lock`. Isso serializa leitura e escrita do mesmo carrinho entre requisições concorrentes, e o controller passa a chamar um método só, sem conhecer esses detalhes.

### Incremento atômico em vez de ler e somar em Ruby

Trocar `cart_item.update!(quantity: cart_item.quantity + quantity)` por `cart_item.increment!(:quantity, quantity)` faz o próprio banco somar no `UPDATE` (`quantity = quantity + ?`), em vez de trazer o valor para o Ruby, somar e gravar de volta. Combinado com o lock do carrinho, isso elimina o lost update: o cenário em que duas requisições leem a mesma quantidade e uma das duas somas acaba se perdendo.

### recalculate_total atualiza total_price e last_interaction_at juntos

As duas coisas sempre acontecem ao mesmo tempo: quando um item é adicionado ou removido, o total muda e a interação é registrada. Separar isso em dois updates não traria nenhum ganho e ainda adicionaria uma query desnecessária. Preferi um único `update!` com os dois campos — mais direto.

### Validação de quantidade dentro de add_product, não no controller

A checagem de `quantity <= 0` vivia duplicada no controller, repetida em `create` e `add_item`. E tinha uma inconsistência: pra um item novo, `cart_items.create!` roda a validação do model e pegaria uma quantidade inválida de qualquer jeito; mas pra um item que já existe, uso `increment!`, que pula validações — então quem garantia que a soma não ficava negativa era só o guard clause do controller, não o model. Movi essa checagem para dentro de `Cart#add_product`, que agora recusa quantidade zero ou negativa antes de tocar no banco, cobrindo os dois caminhos (criar e incrementar) num lugar só. O controller só chama o método e trata o `false` como quantidade inválida.

### Cart.find_or_create_for_session tira a regra de resolução de carrinho do controller

A lógica de "como achar ou criar o carrinho da sessão atual" — olhar `session[:cart_id]`, cair no fallback via `CartItem` quando não há sessão, criar um novo se nada bater — é regra de domínio, não é sobre HTTP. Só a leitura e escrita do valor na sessão é, de fato, responsabilidade do controller (é cookie, o model não deveria conhecer isso). Separei essa lógica em `Cart.find_or_create_for_session(cart_id:, product_id:)`, que recebe só valores primitivos, e o controller ficou responsável apenas por ler `session[:cart_id]`, repassar pro model, e gravar o `id` do carrinho retornado de volta na sessão.

### abandoned? retornando o atributo booleano diretamente

O Rails já gera esse método automaticamente para colunas boolean. Defini explicitamente para deixar claro que ele faz parte da interface pública do model, independente de como o Rails gera métodos por baixo dos panos.

### Scopes no model em vez de queries soltas no job

Os scopes `active`, `inactive_since` e `abandoned_since` encapsulam dentro do próprio model, o que significa um carrinho ativo ou abandonado. Se essa regra mudar amanhã (o prazo de abandono sair de 3 horas para 6, por exemplo), a mudança fica concentrada num único lugar. O job passa a ler como linguagem de domínio — `Cart.active.inactive_since(3.hours)` — sem SQL espalhado por aí.

### Por que inactive_since também considera last_interaction_at nulo

Um carrinho criado mas que nunca recebeu item tem `last_interaction_at` nulo. Uma condição simples como `last_interaction_at <= X` exclui nulos por definição em SQL, então esses carrinhos nunca seriam pegos como inativos. Adicionei o fallback `OR (last_interaction_at IS NULL AND created_at <= X)` justamente para cobrir carrinhos criados há mais de 3 horas e nunca usados.

---

## Controller e gerenciamento de sessão

### Sessão (cookie) para identificar o carrinho

O enunciado pede explicitamente para salvar o ID do carrinho na sessão. Usar `session[:cart_id]` guarda esse ID num cookie criptografado pelo Rails, o que evita precisar de autenticação só para manter o estado entre requests.

### show não cria um carrinho quando a sessão está vazia

Para evitar a geração de carrinhos "fantasma", que nunca chegavam a ser usados de verdade. Troquei para retornar `{ id: nil, products: [], total_price: 0 }` sem persistir nada, ou seja, um carrinho só é criado quando o usuário de fato adiciona um produto.

### O fallback de busca por product_id em find_or_create_cart

O teste de integração que já vinha no projeto cria um `CartItem` direto no banco, sem passar por sessão, e depois faz um `POST /cart/add_items`. Sem esse fallback, o controller criaria um carrinho novo e nunca encontraria o item que já existia. Busquei então o carrinho a partir do `CartItem` que já contém aquele produto, o que resolve o cenário do teste sem mudar o comportamento esperado em produção, onde cada usuário tem só um carrinho ativo por vez.

### add_items (plural) como alias de add_item

O README descreve a rota como `/cart/add_item`, mas o teste de request que já existia no projeto usa `/cart/add_items`. Para não alterar um teste já implementado e ainda respeitar o que o README documenta, deixei as duas rotas apontando para a mesma action (fiquei na dúvida aqui se era algo para eu sacar e arrumar ou não), enfim, da forma como adaptei funciona.

---

## Tratamento de erros

### rescue_from centralizado no ApplicationController

Reparei que só tinha tratado os caminhos felizes e os erros de negócio óbvios (produto inexistente, quantidade inválida), mas qualquer coisa fora desses caminhos — um `GET /products/:id` com um id que não existe, um `POST /products` sem o campo `product`, ou até um corpo JSON malformado — caía direto no tratamento padrão do Rails, que devolve o stack trace inteiro da exceção no corpo da resposta (em produção isso viraria uma resposta genérica, sem JSON, quebrando o contrato da API pro cliente). Adicionei `rescue_from` no `ApplicationController` para `ActiveRecord::RecordNotFound`, `ActiveRecord::RecordInvalid`, `ActionController::ParameterMissing` e `ActionDispatch::Http::Parameters::ParseError`, cada um devolvendo `{ error: mensagem }` com o status HTTP correto (404, 422, 400, 400). A mensagem de cada exceção já é descritiva o suficiente pra ser exposta ao cliente sem vazar detalhe de implementação (tipo linha de código ou stack trace).

Não adicionei um rescue genérico pra `StandardError` — prefiro deixar um erro realmente inesperado estourar (e aparecer no log/500) a esconder um bug atrás de uma mensagem genérica bonitinha.

---

## Catálogo de produtos

### Paginação em GET /products

O endpoint devolvia `Product.all` sem limite nenhum. Com um catálogo grande isso vira um payload enorme e uma query pesada a cada request. Adicionei paginação simples por `page`/`per_page` direto na query (`limit`/`offset`), com um teto de 100 itens por página, sem trazer nenhuma gem nova pra isso — não parecia justificar uma dependência extra para o tamanho do problema aqui.

---

## Job e agendamento

### Sidekiq com sidekiq-scheduler, em vez de uma rake task com cron do sistema

A stack já usa Sidekiq para processamento assíncrono, então o `sidekiq-scheduler` encaixa o agendamento direto no processo do worker, sem depender de crontab do sistema operacional. A configuração fica em `config/sidekiq.yml`, junto do resto da configuração do worker, e versionada no repositório.

### O job roda a cada hora, não a cada 3 horas

Rodando de hora em hora, o atraso máximo entre um carrinho completar 3 horas de inatividade e ser marcado como abandonado é de até 59 minutos. Achei um nível de precisão razoável para o problema. Um intervalo de 3 horas poderia atrasar a marcação em até 3 horas a mais, dobrando a tolerância real.

### update_all e delete_all no job, em vez de instanciar cada carrinho

A primeira versão usava `find_each(&:mark_as_abandoned)` e `find_each(&:destroy)`, processando os carrinhos elegíveis um de cada vez — o que evita carregar tudo de uma vez na memória, mas em escala significa um `UPDATE` ou `DELETE` por linha. Troquei por `update_all` e `delete_all`, que geram uma única instrução SQL para todos os registros que casam com a condição, ordens de magnitude mais rápido quando há muitos carrinhos elegíveis. O preço é pular validações e callbacks do Active Record nesse caminho, mas nem marcar um carrinho como abandonado nem remover um carrinho já abandonado há dias dependem de nenhum callback.

Para o `delete_all` funcionar sem esbarrar na foreign key de `cart_items` — um carrinho abandonado pode perfeitamente ainda ter itens — troquei a constraint para `on_delete: :cascade`. O próprio Postgres remove os itens junto do carrinho, sem eu precisar instanciar cada um.

### Índices compostos para as scopes do job

`active`, `inactive_since` e `abandoned_since` filtram por `abandoned`, `last_interaction_at` e `abandoned_at`, e nenhuma dessas colunas tinha índice. Com poucos milhares de carrinhos isso já vira full table scan toda vez que o job roda. Adicionei `[:abandoned, :last_interaction_at]` e `[:abandoned, :abandoned_at]` como índices compostos, casando com o padrão de filtro de cada scope.

---

## Testes

### FactoryBot em vez de Model.create direto nos specs

Factories centralizam a criação de objetos de teste. Se um atributo obrigatório for adicionado ao model, basta ajustar a factory, não cada `Model.create(...)` espalhado pelos specs. Além disso, `create(:cart)` comunica intenção — "quero um carrinho padrão" — enquanto `Cart.create(total_price: 0, abandoned: false, ...)` é só ruído.

### O alias shopping_cart na factory de Cart

O `cart_spec.rb` que já existia no projeto usa `create(:shopping_cart)`. Para não mexer em teste já implementado, registrei esse nome como alias direto na factory.

### Validação de unicidade no model, além do índice no banco

O índice garante a integridade dos dados, mas quando violado gera uma exceção `ActiveRecord::RecordNotUnique`, com uma mensagem genérica de banco. Validar isso também no model (`validates :product_id, uniqueness: { scope: :cart_id }`) barra o problema antes de chegar ao banco e devolve uma mensagem de erro legível, que pode ser retornada para quem está consumindo a API.
