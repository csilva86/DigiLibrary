---
type: conhecimento
dominio: salesforce
area: Apex
conceito: Trigger bulkificada que mantém um contador/estoque no registro pai a partir dos filhos
maturidade: semente
fontes: ["[[2026-09-01-A — Trigger de empréstimo (Library_Book_Loan__c)]]"]
tags: [conhecimento, apex, soql, limits]
---
# Apex · Trigger bulkificada que mantém contador no registro pai

## Ideia central

Quando cada registro-filho precisa somar/subtrair 1 de um contador no
registro-pai (estoque, vagas, saldo), a trigger deve:

1. **Agregar o delta por `Id` do pai** num `Map<Id, Integer>` percorrendo
   `Trigger.new` / `Trigger.old` — nunca tratar registro a registro.
2. **Um único SOQL** buscando os pais afetados: `WHERE Id IN :map.keySet()`
   com **`FOR UPDATE`** para travar as linhas contra escrita concorrente.
3. **Validar contra o delta agregado**, não contra `> 0` ingênuo:
   `disponivel < solicitado` cobre o caso de N filhos do mesmo pai no mesmo
   lote.
4. **Um único `update`** da lista de pais no fim.

Rodar em contexto **`after`**: os filhos já têm `Id` e estão persistidos, e se
a validação lançar exceção o rollback automático da transação desfaz filho +
pai juntos — nada fica gravado quando não há saldo.

Consumo fixo: **1 SOQL + 1 DML** por operação, para qualquer volume (200+).

## Quando aplicar

- Estoque de cópias (empréstimo de livro), vagas de evento, assentos, saldo de
  cotas, "quantidade em uso" — qualquer campo no pai que é função da contagem
  de filhos.
- Alternativa a **Roll-Up Summary** quando: o filho não é master-detail, a
  regra de negócio é mais que uma soma (validação + exceção customizada), ou
  precisa lançar erro no momento do insert.
- Junto de uma classe de serviço (`loanBook(...)`): a trigger é a rede de
  segurança que vale para qualquer origem (API, import, fluxo), o serviço é a
  porta de entrada amigável.

## Exemplo

`Library_Book_Loan__c` (filho) mantém `Library_Book__c.Available_Copies__c`:

```apex
trigger LibraryBookLoanTrigger on Library_Book_Loan__c(after insert, after delete) {
    if (Trigger.isAfter && Trigger.isInsert) {
        LibraryBookLoanTriggerHandler.handleAfterInsert(Trigger.new);
    } else if (Trigger.isAfter && Trigger.isDelete) {
        LibraryBookLoanTriggerHandler.handleAfterDelete(Trigger.old);
    }
}
```

```apex
// agregação por pai — ignora lookup nulo
private static Map<Id, Integer> countLoansByBook(List<Library_Book_Loan__c> loans) {
    Map<Id, Integer> byBook = new Map<Id, Integer>();
    for (Library_Book_Loan__c l : loans) {
        if (l.Book__c == null) { continue; }
        Integer cur = byBook.containsKey(l.Book__c) ? byBook.get(l.Book__c) : 0;
        byBook.put(l.Book__c, cur + 1);
    }
    return byBook;
}

public static void handleAfterInsert(List<Library_Book_Loan__c> newLoans) {
    Map<Id, Integer> requested = countLoansByBook(newLoans);
    if (requested.isEmpty()) { return; }

    Map<Id, Library_Book__c> books = new Map<Id, Library_Book__c>([
        SELECT Id, Name, Available_Copies__c
        FROM Library_Book__c
        WHERE Id IN :requested.keySet()
        FOR UPDATE
    ]);

    List<Library_Book__c> toUpdate = new List<Library_Book__c>();
    for (Id bookId : requested.keySet()) {
        Library_Book__c b = books.get(bookId);
        Integer n = requested.get(bookId);
        Decimal avail = (b != null && b.Available_Copies__c != null) ? b.Available_Copies__c : 0;
        if (b == null || avail < n) {
            throw new NoAvailableCopiesException('Sem cópias para "' + (b != null ? b.Name : bookId)
                + '". Pedido: ' + n + ', disponível: ' + avail + '.');
        }
        b.Available_Copies__c = avail - n;
        toUpdate.add(b);
    }
    update toUpdate;
}
// delete: mesma agregação, Available_Copies__c = avail + n; (sem validação)
```

## Armadilhas

- **`throw` numa trigger `after` polui a UI padrão.** Aparece como o painel
  "We hit a snag" com `Class.X: line N`. Preferir
  `sObject.addError(new MinhaException(msg))` — a UI mostra só a mensagem, o
  tipo da exceção é preservado, e um insert em lote grava os filhos que
  *podem* ser atendidos (partial success) em vez de derrubar tudo. Contrapartida:
  deixa de haver rollback total no lote — a validação passa a ser por registro.
- **Toast só no contexto Lightning.** Trigger e página padrão de criação de
  registro nunca disparam toast — mostram banner. Para toast, o filho tem que
  ser criado por um LWC que chama Apex e converte o erro em `ShowToastEvent`.
- **`before insert` para a validação, `after` para o decremento** é uma opção
  se o avaliador exigir "não gravar o filho quando não há saldo sem depender de
  rollback". Custa uma segunda passagem; `addError` no `after` já resolve na
  maioria dos casos.
- **Sem `FOR UPDATE`**: dois empréstimos concorrentes leem o mesmo
  `Available_Copies__c`, ambos decrementam, uma atualização se perde
  (overbooking).
- **Validar `> 0` em vez de `< solicitado`**: quebra quando o mesmo lote tem N
  filhos do mesmo pai (import, `Database.insert` de lista).
- **Campo nulo**: tratar `Available_Copies__c == null` como `0`, senão
  aritmética com null explode.
- **`after update`**: se um dia a trigger passar a ouvir update, cuidar
  recursão e reparent (mudança de `Book__c` = devolver ao antigo + tirar do
  novo).
- **Roll-Up nativo** resolve o caso simples sem código — só escrever trigger
  quando há regra/erro de negócio envolvido.

## Relacionadas

- [[MOC · Apex]]
- [[2026-09-01-A — Trigger de empréstimo (Library_Book_Loan__c)]] — origem
- Exceção customizada `NoAvailableCopiesException` (`extends Exception`)
