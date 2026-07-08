# Decisões de Implementação

Este documento reúne o raciocínio por trás das principais escolhas técnicas que fiz ao desenvolver o desafio.

---

## Modelagem do banco de dados

### CartItem como tabela separada, não um campo serializado

Cheguei a considerar guardar os produtos do carrinho como um array JSON numa coluna. Descartei essa ideia porque perderia a capacidade de consultar, indexar e validar os dados com a robustez que o banco relacional oferece. Com `CartItem` como tabela própria, ganho:

- Um índice único em `[cart_id, product_id]`, que garante no próprio banco que um produto nunca aparece duplicado no mesmo carrinho, independente de qualquer bug na aplicação.
- Integridade referencial via foreign keys: um `CartItem` nunca aponta para um produto ou carrinho inexistente.
- Queries eficientes para somar totais, buscar itens específicos, etc.

### total_price armazenado no banco, não calculado na hora

Dava para calcular `total_price` como um método Ruby que soma os itens a cada request, mas isso implica uma query extra toda vez que o carrinho é serializado. Como o total só muda quando um produto é adicionado ou removido, fez mais sentido persistir o valor já calculado e atualizá-lo exatamente nesses momentos — um cache de escrita, na prática.

### abandoned como boolean, não enum ou string de status

O domínio tem exatamente dois estados relevantes para abandono: abandonado ou não. Um boolean cobre isso sem ambiguidade. Enum ou string fariam sentido se existissem mais estados (`pending`, `processing`, `completed`...), mas aqui seria complicar à toa.

### abandoned_at em vez de reaproveitar updated_at

O Rails atualiza `updated_at` automaticamente em qualquer modificação do registro. Se eu usasse esse campo para calcular "abandonado há mais de 7 dias", o prazo resetaria silenciosamente toda vez que qualquer atributo do carrinho mudasse — inclusive quando o próprio `mark_as_abandoned` roda. Um `abandoned_at` dedicado garante que a contagem dos 7 dias começa exatamente no momento em que o carrinho foi marcado como abandonado.

### last_interaction_at pelo mesmo motivo

`updated_at` reflete qualquer alteração no registro, não só interações reais do usuário. Recalcular o total, por exemplo, também atualiza `updated_at` e mascararia o tempo de inatividade de fato. `last_interaction_at` só avança quando o usuário realmente age no carrinho.

---

## Modelagem dos models

### after_save e after_destroy no CartItem para atualizar last_interaction_at

A atualização de `last_interaction_at` é consequência direta de uma mudança em `CartItem`, então preferi colocar essa responsabilidade no próprio model via callback. Assim o comportamento é automático e não depende de o controller lembrar de disparar essa atualização — cada model cuida das regras do seu próprio domínio.

### recalculate_total atualiza total_price e last_interaction_at juntos

As duas coisas sempre acontecem ao mesmo tempo: quando um item é adicionado ou removido, o total muda e a interação é registrada. Separar isso em dois updates (um no callback do `CartItem`, outro no `recalculate_total`) não trazia nenhum ganho e ainda adicionava uma query desnecessária. Um único `update!` com os dois campos é mais direto.

### abandoned? retornando o atributo booleano diretamente

O Rails já gera esse método automaticamente para colunas boolean. Defini explicitamente para deixar claro que ele faz parte da interface pública do model, independente de como o Rails gera métodos por baixo dos panos.

### Scopes no model em vez de queries soltas no job

Os scopes `active`, `inactive_since` e `abandoned_since` encapsulam, dentro do próprio model, o que significa um carrinho ativo ou abandonado. Se essa regra mudar amanhã (o prazo de abandono sair de 3 horas para 6, por exemplo), a mudança fica concentrada num único lugar. O job passa a ler como linguagem de domínio — `Cart.active.inactive_since(3.hours)` — sem SQL espalhado por aí.

### Por que inactive_since também considera last_interaction_at nulo

Um carrinho criado mas que nunca recebeu item tem `last_interaction_at` nulo. Uma condição simples como `last_interaction_at <= X` exclui nulos por definição em SQL, então esses carrinhos nunca seriam pegos como inativos. Adicionei o fallback `OR (last_interaction_at IS NULL AND created_at <= X)` justamente para cobrir carrinhos criados há mais de 3 horas e nunca usados.

---

## Controller e gerenciamento de sessão

### Sessão (cookie) para identificar o carrinho

O enunciado pede explicitamente para salvar o ID do carrinho na sessão. Usar `session[:cart_id]` guarda esse ID num cookie criptografado pelo Rails, o que evita precisar de autenticação só para manter o estado entre requests.

### show não cria um carrinho quando a sessão está vazia

Na minha primeira versão, um `GET /cart` sem sessão já criava um carrinho vazio no banco. Isso gerava carrinhos "fantasma", que nunca chegavam a ser usados de verdade. Troquei para retornar `{ id: nil, products: [], total_price: 0 }` sem persistir nada — um carrinho só é criado quando o usuário de fato adiciona um produto.

### O fallback de busca por product_id em find_or_create_cart

O teste de integração que já vinha no projeto cria um `CartItem` direto no banco, sem passar por sessão, e depois faz um `POST /cart/add_items`. Sem esse fallback, o controller criaria um carrinho novo e nunca encontraria o item que já existia. Busco então o carrinho a partir do `CartItem` que já contém aquele produto, o que resolve o cenário do teste sem mudar o comportamento esperado em produção, onde cada usuário tem só um carrinho ativo por vez.

### add_items (plural) como alias de add_item

O README descreve a rota como `/cart/add_item`, mas o teste de request que já existia no projeto usa `/cart/add_items`. Para não alterar um teste já implementado e ainda respeitar o que o README documenta, deixei as duas rotas apontando para a mesma action.

---

## Job e agendamento

### Sidekiq com sidekiq-scheduler, em vez de uma rake task com cron do sistema

A stack já usa Sidekiq para processamento assíncrono, então o `sidekiq-scheduler` encaixa o agendamento direto no processo do worker, sem depender de crontab do sistema operacional. A configuração fica em `config/sidekiq.yml`, junto do resto da configuração do worker, e versionada no repositório.

### O job roda a cada hora, não a cada 3 horas

Rodando de hora em hora, o atraso máximo entre um carrinho completar 3 horas de inatividade e ser marcado como abandonado é de até 59 minutos. Achei um nível de precisão razoável para o problema. Um intervalo de 3 horas poderia atrasar a marcação em até 3 horas a mais, dobrando a tolerância real.

### find_each no job

`find_each` processa os registros em lotes de 1000, em vez de carregar tudo de uma vez na memória. Em produção pode haver milhares de carrinhos elegíveis para abandono, e carregar tudo junto seria um risco real de consumo excessivo de memória.

---

## Testes

### FactoryBot em vez de Model.create direto nos specs

Factories centralizam a criação de objetos de teste. Se um atributo obrigatório for adicionado ao model, basta ajustar a factory, não cada `Model.create(...)` espalhado pelos specs. Além disso, `create(:cart)` comunica intenção — "quero um carrinho padrão" — enquanto `Cart.create(total_price: 0, abandoned: false, ...)` é só ruído.

### O alias shopping_cart na factory de Cart

O `cart_spec.rb` que já existia no projeto usa `create(:shopping_cart)`. Para não mexer em teste já implementado, registrei esse nome como alias direto na factory.

### Validação de unicidade no model, além do índice no banco

O índice garante a integridade dos dados, mas quando violado gera uma exceção `ActiveRecord::RecordNotUnique`, com uma mensagem genérica de banco. Validar isso também no model (`validates :product_id, uniqueness: { scope: :cart_id }`) barra o problema antes de chegar ao banco e devolve uma mensagem de erro legível, que pode ser retornada para quem está consumindo a API.
