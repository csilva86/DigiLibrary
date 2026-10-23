---
type: tarefa
dominio: salesforce
id:
fonte: Outro
projeto: "[[STRONG — Book Management]]"
cliente: STRONG
status: concluído
prioridade: alta
area:
  - Apex
  - Data-SOQL
abertura: 2026-09-01
prazo: 2026-09-03
parent: "[[2026-09-01 — Apex Developer Challenge — DigiLibrary]]"
tags:
  - tarefa
  - apex
---
# Trigger de empréstimo (Library_Book_Loan__c)

## Contexto
Subtarefa promovida a nota própria a partir de
[[2026-09-01 — Apex Developer Challenge — DigiLibrary]] por concentrar a
lógica de negócio central do desafio (validação + atualização de estoque),
boa candidata a gerar aprendizado reutilizável.

Implementar trigger em `Library_Book_Loan__c` que:
- Valida que só é possível registrar o empréstimo se
  `Library_Book__c.Available_Copies__c > 0`; caso contrário, lança
  `NoAvailableCopiesException`.
- No `insert` (empréstimo registrado): decrementa `Available_Copies__c` em 1
  no livro relacionado.
- No `delete` (empréstimo removido): incrementa `Available_Copies__c` em 1.
- Usa SOQL otimizado (bulkified, sem query dentro de loop) para buscar os
  `Library_Book__c` afetados e aplicar o `update` em lote.

## Subtarefas
- [x] Criar handler (trigger + classe handler bulkificada) para ✅ 2026-09-01
      `Library_Book_Loan__c` 🔺
- [x] Implementar validação de cópias disponíveis + lançamento de ✅ 2026-09-01
      `NoAvailableCopiesException` 🔺
- [x] Implementar decremento no insert / incremento no delete, com update em ✅ 2026-09-01
      lote (sem DML em loop) 🔺
- [x] Trocar `throw` por `addError(NoAvailableCopiesException)` no handler — ✅ 2026-09-01
      mensagem limpa na UI padrão + partial success em lote 🔺
- [x] Testes unitários do trigger (cópias disponíveis, sem cópias, delete, ✅ 2026-09-02
      bulk, partial success, `Available_Copies__c` nulo, loan sem `Book__c`) —
      `LibraryBookLoanTriggerTest`, trigger + handler 100% 🔼

## O que foi feito

### 2026-09-01 — Trigger, handler e exceção customizada

Criados no repo SFDX (`force-app/main/default/`), API 65.0, padrão
**trigger fina + classe handler** para deixar a lógica testável e fora do
arquivo `.trigger`:

| Arquivo | Papel |
|---|---|
| `triggers/LibraryBookLoanTrigger.trigger` | Só roteia `after insert` / `after delete` para o handler |
| `classes/LibraryBookLoanTriggerHandler.cls` | Validação de estoque + ajuste de `Available_Copies__c`, bulkificado |
| `classes/NoAvailableCopiesException.cls` | `public class NoAvailableCopiesException extends Exception {}` |

**Trigger:**

```apex
trigger LibraryBookLoanTrigger on Library_Book_Loan__c(after insert, after delete) {
    if (Trigger.isAfter && Trigger.isInsert) {
        LibraryBookLoanTriggerHandler.handleAfterInsert(Trigger.new);
    } else if (Trigger.isAfter && Trigger.isDelete) {
        LibraryBookLoanTriggerHandler.handleAfterDelete(Trigger.old);
    }
}
```

**Handler (trechos principais):**

```apex
// Agrupa os loans por livro (ignora Book__c nulo) e conta quantos por livro
private static Map<Id, Integer> countLoansByBook(List<Library_Book_Loan__c> loans) {
    Map<Id, Integer> countByBookId = new Map<Id, Integer>();
    for (Library_Book_Loan__c loan : loans) {
        if (loan.Book__c == null) { continue; }
        Integer current = countByBookId.containsKey(loan.Book__c) ? countByBookId.get(loan.Book__c) : 0;
        countByBookId.put(loan.Book__c, current + 1);
    }
    return countByBookId;
}

public static void handleAfterInsert(List<Library_Book_Loan__c> newLoans) {
    Map<Id, Integer> requestedByBookId = countLoansByBook(newLoans);
    if (requestedByBookId.isEmpty()) { return; }

    Map<Id, Library_Book__c> booksById = new Map<Id, Library_Book__c>([
        SELECT Id, Name, Available_Copies__c, Total_Copies__c
        FROM Library_Book__c
        WHERE Id IN :requestedByBookId.keySet()
        FOR UPDATE
    ]);

    List<Library_Book__c> booksToUpdate = new List<Library_Book__c>();
    for (Id bookId : requestedByBookId.keySet()) {
        Library_Book__c book = booksById.get(bookId);
        Integer requested = requestedByBookId.get(bookId);
        Decimal available = (book != null && book.Available_Copies__c != null) ? book.Available_Copies__c : 0;

        if (book == null || available < requested) {
            throw new NoAvailableCopiesException(
                'No available copies for book "' + (book != null ? book.Name : String.valueOf(bookId)) +
                '". Requested: ' + requested + ', available: ' + available + '.'
            );
        }
        book.Available_Copies__c = available - requested;
        booksToUpdate.add(book);
    }
    update booksToUpdate;
}

public static void handleAfterDelete(List<Library_Book_Loan__c> oldLoans) {
    Map<Id, Integer> releasedByBookId = countLoansByBook(oldLoans);
    if (releasedByBookId.isEmpty()) { return; }

    List<Library_Book__c> booksToUpdate = new List<Library_Book__c>();
    for (Library_Book__c book : [
        SELECT Id, Available_Copies__c, Total_Copies__c
        FROM Library_Book__c
        WHERE Id IN :releasedByBookId.keySet()
        FOR UPDATE
    ]) {
        Decimal available = (book.Available_Copies__c != null) ? book.Available_Copies__c : 0;
        book.Available_Copies__c = available + releasedByBookId.get(book.Id);
        booksToUpdate.add(book);
    }
    update booksToUpdate;
}
```

### Leitura técnica (candidata a conhecimento)

- **Contexto `after` (e não `before insert`):** os registros de loan já têm
  `Id` e estão persistidos; a alteração de estoque incide sobre linhas-filho
  já gravadas. Trade-off: se a validação lançar exceção no `after insert`, a
  transação inteira sofre rollback (loan + update do livro), que é o
  comportamento desejado — nada é persistido quando não há cópia.
- **Bulkificação:** 1 `SOQL` + 1 `DML` por operação, independentemente do
  volume. Nenhuma query/DML dentro de loop. Vários loans para o mesmo livro
  no mesmo lote são **somados** (`countLoansByBook`) e validados de uma vez
  (`available < requested`), não `> 0` ingênuo — cobre o caso de N loans do
  mesmo livro numa única `insert`.
- **`FOR UPDATE`:** trava as linhas de `Library_Book__c` durante a transação
  para evitar corrida de dois empréstimos concorrentes lendo o mesmo
  `Available_Copies__c` e ambos decrementando (perda de atualização /
  overbooking).
- **Null-safety:** `Available_Copies__c` nulo é tratado como `0` (livro sem
  estoque definido nunca empresta; no delete, parte de `0`).
- **Governor limits:** consumo fixo — 1 SOQL, 1 DML, sem CPU relevante. Escala
  para lotes de 200 sem risco. Ponto de atenção: recursão se algum outro
  processo atualizar o loan e reentrar — hoje não há `after update`, então ok.
- **Aderência ao enunciado:** o PDF pede "decrementa em 1 no insert / incrementa
  em 1 no delete" e "valida `Available_Copies__c > 0`". A implementação
  generaliza para "em N" mantendo o caso unitário idêntico, e a validação
  `available < requested` reduz a `available < 1` (ou seja, `<= 0`) quando há
  só um loan.

### 2026-09-01 (cont.) — Erro amigável na UI: `addError` + toast

**Motivação:** ao testar pela tela padrão "New Library Book Loan", o `throw`
aparecia como o painel feio "We hit a snag" com
`Class.LibraryBookLoanTriggerHandler.handleAfterInsert: line 42` exposto.
Pedido: mostrar o erro de forma clara e, no caminho Lightning, via **toast**.

**Handler — `throw` → `addError` (por registro):**

```apex
@TestVisible
private static final String NO_COPIES_MESSAGE =
    'O livro "{0}" nao tem copias disponiveis no momento. ' +
    'Tente novamente quando um exemplar for devolvido.';

// dentro de handleAfterInsert, no lugar do throw:
Set<Id> unfulfillableBookIds = new Set<Id>();
for (Id bookId : requestedByBookId.keySet()) {
    Library_Book__c book = booksById.get(bookId);
    Integer requested = requestedByBookId.get(bookId);
    Decimal available = (book != null && book.Available_Copies__c != null) ? book.Available_Copies__c : 0;
    if (book == null || available < requested) {
        unfulfillableBookIds.add(bookId);          // não lança
    } else {
        book.Available_Copies__c = available - requested;
        booksToUpdate.add(book);
    }
}
if (!unfulfillableBookIds.isEmpty()) {
    for (Library_Book_Loan__c loan : newLoans) {
        if (!unfulfillableBookIds.contains(loan.Book__c)) { continue; }
        Library_Book__c book = booksById.get(loan.Book__c);
        String bookName = (book != null) ? book.Name : 'selecionado';
        loan.addError(
            new NoAvailableCopiesException(
                String.format(NO_COPIES_MESSAGE, new List<Object>{ bookName })
            )
        );
    }
}
if (!booksToUpdate.isEmpty()) { update booksToUpdate; }
```

**Por que `addError(Exception)` e não `throw`:**

| | `throw new NoAvailableCopiesException(...)` | `loan.addError(new NoAvailableCopiesException(...))` |
|---|---|---|
| UI padrão | painel "We hit a snag" + `Class.X: line N` | banner com **só a mensagem** |
| Insert em lote | derruba a transação inteira | grava os loans que **têm** cópia; falham só os sem cópia (partial success) |
| Tipo da exceção | `NoAvailableCopiesException` | idem — `addError` aceita o objeto de exceção e usa `getMessage()` |
| Alvo do erro | transação | o **registro** de loan específico |

**Toast só existe no contexto Lightning.** A tela padrão de criação de
registro nunca mostra toast — mostra o banner. O toast vem pelo LWC
`libraryLoanButton`, que chama `LibraryService.requestLoan` e converte a
falha em `ShowToastEvent` (ver
[[2026-09-01-C — Interface de busca e empréstimo (LWC)]] e
[[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]]).

**Revisão da leitura técnica:** com `addError` por registro, **não há mais
rollback da transação inteira** no insert em lote — cada loan sem cópia falha
isolado e os demais são gravados. O caso "N loans do mesmo livro no mesmo
lote" continua coberto: se `available < requested`, **todos** os loans
daquele livro recebem `addError`.

### 2026-09-01 — Caminho `after delete` agora exercido pela UI

O `libraryLoanList` ganhou ação "Excluir" por linha (`deleteRecord`), então o
`handleAfterDelete` (incremento de `Available_Copies__c` em +1) passou a ser
acionado pela interface, não só por delete manual. Sem mudança no trigger.
Detalhe em [[2026-09-01-C — Interface de busca e empréstimo (LWC)]].

### 2026-09-02 — Mensagem do `addError` traduzida para inglês

`NO_COPIES_MESSAGE` no handler e o fallback `'selecionado'` → `'selected'`
passaram para inglês (requisito do cliente — a mensagem do `addError` aparece
no banner da UI padrão). Sem mudança de lógica.

### 2026-09-02 — `LibraryBookLoanTriggerTest` (100% no trigger e no handler)

9 métodos, todos passam no org:

| Cenário | Verifica |
|---|---|
| `insert_decrementsAvailableCopies` | 1 loan → `Available_Copies__c` −1 |
| `delete_incrementsAvailableCopies` | delete → +1 |
| `insert_bulk_decrementsByLoanCount` | 5 loans mesmo livro → −5 (agregação por pai) |
| `insert_noCopies_blocksLoanWithFriendlyError` | `Available=0` → `DmlException` ("no available copies"), loan não gravado |
| `insert_partialBulk_commitsFulfillableOnly` | `Database.insert(list, false)` → livro com cópia grava, livro sem cópia falha |
| `insert_nullAvailableCopies_treatedAsZero` | `Available_Copies__c = null` → tratado como 0 → bloqueia |
| `delete_nullAvailableCopies_treatedAsZero` | `null` no delete → `0 + 1` |
| `loanWithoutBook_isIgnoredByTrigger` | loan com `Book__c` nulo → `countLoansByBook` ignora, early return |

**Notas de teste:**

- `insert_noCopies` cobre o `addError`: em modo all-or-none, `addError` vira
  `DmlException`; em `Database.insert(list, false)`, só a linha marcada falha.
- Forçar `book == null` no loop do handler é impraticável (FK impede inserir
  loan apontando p/ livro deletado) — código defensivo; ainda assim 100% de
  linhas porque o `if (book == null || available < requested)` é avaliado.
- `Library_Book__c.Title__c` é **fórmula** (espelha `Name`) — a factory grava
  `Name`. Ver [[2026-09-01 — Apex Developer Challenge — DigiLibrary]].

## Obstáculos & solução

- **Objetos/campos custom** (`Library_Book__c` com `Available_Copies__c` /
  `Total_Copies__c`, `Library_Book_Loan__c` com `Book__c`). O deploy de
  2026-09-01 passou, então existem no org. **Pendente:** confirmar se estão
  versionados em `force-app/main/default/objects/` (se não, `sf project
  retrieve`). Ver [[2026-09-01 — Apex Developer Challenge — DigiLibrary]].
- **Decisão `after` vs `before`:** avaliado fazer a validação em `before insert`
  (falha mais cedo, sem gravar o loan) e o decremento em `after`. Optado por
  concentrar tudo em `after insert` pela simplicidade e porque o rollback
  automático da transação já garante que nada persiste em caso de erro. Se o
  avaliador exigir "não criar o registro de loan quando não há cópia sem
  depender de rollback", mover a validação para `before insert`.

- **2026-09-01 — Erro feio na tela padrão.** `throw` numa trigger `after`
  aparece na UI de criação de registro como o painel "We hit a snag" com
  `Class.X: line N`. **Solução:** `SObject.addError(new NoAvailableCopiesException(msg))`
  — a UI passa a mostrar só a mensagem, sem stack. Para o **toast** pedido é
  necessário o caminho LWC (trigger/página padrão não disparam toast); feito
  no `libraryLoanButton` + `LibraryService.requestLoan`.
- **2026-09-01 — Mensagem some no LWC.** Exceção customizada crua saindo de
  método `@AuraEnabled` chega ao cliente como *"internal server error"*
  genérico. **Solução:** `requestLoan` captura e relança como
  `AuraHandledException` (única cujo `message` é repassado ao JS). Detalhe em
  [[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]].

## 🧠 Para o acervo
- [[Apex · Trigger bulkificada que mantém contador no registro pai]] —
  extraído em 2026-09-01 (agregação de delta por pai + SOQL `FOR UPDATE` +
  um único `update` em lote; contexto `after` e rollback automático).
