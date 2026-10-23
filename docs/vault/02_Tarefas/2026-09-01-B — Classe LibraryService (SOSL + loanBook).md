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
  - soql
---
# Classe LibraryService (SOSL + loanBook)

## Contexto
Subtarefa promovida a nota própria a partir de
[[2026-09-01 — Apex Developer Challenge — DigiLibrary]] — camada de serviço
que concentra busca (SOSL) e registro de empréstimo, reaproveitada pela UI.

Criar classe `LibraryService` com:
- `List<Library_Book__c> searchBooks(String searchTerm)` — usa **SOSL** para
  buscar por título ou autor (`FIND :searchTerm IN ALL FIELDS RETURNING
  Library_Book__c(...)` ou equivalente), retornando também
  `Available_Copies__c` e `Total_Copies__c`.
- `void loanBook(Id bookId, Id borrowerId)` — cria o `Library_Book_Loan__c`
  correspondente; delega a validação/decremento de estoque ao trigger em
  [[2026-09-01-A — Trigger de empréstimo (Library_Book_Loan__c)]] e propaga
  `NoAvailableCopiesException` quando não houver cópias.

## Subtarefas
- [x] Implementar `searchBooks(String searchTerm)` com SOSL ✅ 2026-09-01 🔺
- [x] Implementar `loanBook(Id bookId, Id borrowerId)` (cria ✅ 2026-09-01
      `Library_Book_Loan__c`, trata exceção) 🔺
- [x] Reutilizar `NoAvailableCopiesException` (definida na tarefa-mãe) ao ✅ 2026-09-01
      propagar erro de estoque 🔽
- [x] Adicionar wrapper `@AuraEnabled requestLoan` que converte a falha em ✅ 2026-09-01
      `AuraHandledException` para o LWC 🔺
- [x] Testes unitários da classe (`LibraryServiceTest`, 12 métodos, 98%) — ✅ 2026-09-02
      busca curta/fixa/sanitize, loanBook OK/nulo/não-achado/sem-cópia,
      requestLoan OK/sem-cópia/nulo/DmlException 🔼

## O que foi feito

### 2026-09-01 — `loanBook` + `requestLoan` (parte de exceção/UI)

Criada `classes/LibraryService.cls` (API 65.0). Primeiro passo: o necessário
para o toast de erro de empréstimo. `searchBooks` (SOSL) adicionado logo em
seguida — ver subseção mais abaixo.

**`loanBook` — Apex puro, lança a exceção customizada (requisito do desafio):**

```apex
public static Id loanBook(Id bookId, Id borrowerId) {
    if (bookId == null || borrowerId == null) {
        throw new IllegalArgumentException('Informe o livro e o solicitante...');
    }
    List<Library_Book__c> books = [
        SELECT Id, Name, Available_Copies__c
        FROM Library_Book__c
        WHERE Id = :bookId
        FOR UPDATE
    ];
    if (books.isEmpty()) { throw new NoAvailableCopiesException('Livro nao encontrado.'); }

    Library_Book__c book = books[0];
    Decimal available = (book.Available_Copies__c != null) ? book.Available_Copies__c : 0;
    if (available <= 0) {
        throw new NoAvailableCopiesException(
            'O livro "' + book.Name + '" nao tem copias disponiveis no momento. ...'
        );
    }
    Library_Book_Loan__c loan = new Library_Book_Loan__c(
        Book__c = bookId, Borrower__c = borrowerId, Loan_Start_Date__c = Date.today()
    );
    insert loan;        // o trigger decrementa Available_Copies__c
    return loan.Id;
}
```

**`requestLoan` — ponto de entrada do LWC:**

```apex
@AuraEnabled
public static Id requestLoan(Id bookId, Id borrowerId) {
    try {
        return loanBook(bookId, borrowerId);
    } catch (NoAvailableCopiesException e) {
        throw toAuraException(e.getMessage());
    } catch (DmlException e) {
        String msg = (e.getNumDml() > 0) ? e.getDmlMessage(0) : e.getMessage();
        throw toAuraException(msg);
    } catch (Exception e) {
        throw toAuraException(e.getMessage());
    }
}

private static AuraHandledException toAuraException(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);   // garante o message no error.body.message do LWC
    return ex;
}
```

### Leitura técnica

- **Só `AuraHandledException` repassa a mensagem ao cliente.** Qualquer outra
  exceção (inclusive a customizada) saindo de um método `@AuraEnabled` chega
  ao JS como `error.body.message === 'Internal Server Error'` / *"An internal
  server error has occurred"*. Por isso o par **`loanBook` (lança a
  customizada, para Apex/testes) + `requestLoan` (relança como
  `AuraHandledException`, para o LWC)**.
- **`setMessage()` além do construtor:** em várias versões o
  `new AuraHandledException(msg)` sozinho não populava `error.body.message`
  de forma confiável; `setMessage(msg)` fecha essa lacuna. Custo zero, mantém.
- **`FOR UPDATE` também aqui:** a checagem `available <= 0` e o `insert` do
  loan precisam da linha travada para não competir com outra requisição
  simultânea (mesmo motivo do trigger).
- **Camadas:** o `requestLoan` faz a checagem *antes* do DML, então o
  caminho feliz nunca aciona o `addError` do trigger; o `catch (DmlException)`
  é a rede para corrida (o `addError` disparando entre a checagem e o insert).
- **`IllegalArgumentException`** é built-in do Apex (`System.IllegalArgumentException`);
  usada só para argumento nulo, não para regra de negócio.

### 2026-09-01 — `searchBooks` (SOSL por título ou autor)

```apex
@AuraEnabled(cacheable=true)
public static List<Library_Book__c> searchBooks(String searchTerm) {
    if (String.isBlank(searchTerm) || searchTerm.trim().length() < MIN_SEARCH_LENGTH) {
        return new List<Library_Book__c>();          // SOSL exige >= 2 chars
    }
    String searchKey = sanitizeSoslTerm(searchTerm) + '*';   // prefixo: "advent" -> "Adventures"

    List<List<SObject>> results = [
        FIND :searchKey
        IN ALL FIELDS
        RETURNING Library_Book__c(
            Id, Name, Title__c, Author__c, Available_Copies__c, Total_Copies__c
            ORDER BY Title__c
            LIMIT :MAX_RESULTS                        // 50
        )
    ];
    return (List<Library_Book__c>) results[0];
}

// escapa os caracteres que o SOSL trata como operador (\ primeiro, p/ não duplicar)
private static String sanitizeSoslTerm(String term) {
    String cleaned = term.trim();
    for (String ch : new List<String>{
        '\\','?','&','|','!','{','}','[',']','(',')','^','~','*',':','"','\'','+','-'
    }) {
        cleaned = cleaned.replace(ch, '\\' + ch);
    }
    return cleaned;
}
```

**Leitura técnica:**

- **SOSL e não SOQL** porque o requisito é busca textual por título *ou* autor:
  o índice de texto do SOSL faz OR entre campos e tokeniza por palavra
  (`FIND 'Tom'` acha "The Adventures of **Tom** Sawyer" sem `%...%`). SOQL
  exigiria `WHERE Title__c LIKE :x OR Author__c LIKE :x` com `LIKE` não
  seletivo (full scan).
- **`IN ALL FIELDS`**: o `FIND` não permite escolher 2 campos específicos —
  as opções são `ALL / NAME / EMAIL / PHONE / SIDEBAR FIELDS`. Como os únicos
  campos de texto de `Library_Book__c` são `Title__c`, `Author__c` e `Name`,
  `ALL FIELDS` = "título ou autor" na prática.
- **Bind `:searchKey`** evita injeção; o `sanitizeSoslTerm` cobre o outro
  risco (um `?`/`*`/`-` solto lançando `SearchException`). `\` escapado
  primeiro para não re-escapar os que vêm depois.
- **Wildcard só no fim** (`term + '*'`): prefixo é indexado e rápido; wildcard
  no início (`*term`) força varredura e é proibido em alguns contextos.
- **`cacheable=true`**: busca é read-only e idempotente → habilita cache do
  Lightning Data Service e permite `@wire` no LWC; termos repetidos não
  batem no servidor.
- **Guard de 2 chars + `LIMIT 50` + `ORDER BY Title__c`**: 1 só SOSL,
  resultado limitado e estável para a UI. SOSL conta como 1 dos 20
  `Queries` do governor; sem loop.
- **`with sharing`** na classe → a busca respeita a visibilidade do usuário.

### 2026-09-02 — Estendido pelo Extra Challenge (API externa)

`searchBooks` foi reescrito para unir local (SOSL) + Open Library e passou a
retornar `List<BookSearchResult>` (DTO) em vez de `List<Library_Book__c>`;
**deixou de ser `cacheable`** (faz callout). Adicionado `importBook(title,
author)`. A SOSL local virou o método privado `findLocalBooks`; adicionado
`booksByExactTitle` — **backfill SOQL** (`WHERE Name IN :títulosExternos`) para
compensar a latência do índice SOSL (livro recém-importado não aparece no
`FIND` por alguns segundos). Detalhe e racional em
[[2026-09-02-D — Integração Open Library (API externa)]].
`LibraryServiceTest` foi atualizado junto (mock HTTP + asserts do DTO +
testes de `importBook` + `searchBooks_bookMissedBySosl_isBackfilledFromSoql`)
— 99% na classe, 38 testes no total do desafio.

### 2026-09-02 — `LibraryServiceTest` (98% → 99% após o Extra Challenge)

12 métodos, todos passam. Cobre 57/58 linhas — a única não coberta é o ramo
`: e.getMessage()` do ternário no `catch (DmlException)` (`DmlException` com
`getNumDml() == 0` é impraticável de simular). Bem acima dos 90%.

- **SOSL**: `Test.setFixedSearchResults(new List<Id>{...})` **obrigatório** —
  sem isso o SOSL retorna vazio em teste. Testes: termo curto/nulo → lista
  vazia; termo com resultados fixos → tamanho certo; termo com
  `? & ( ) * -` → sem `SearchException` (cobre `sanitizeSoslTerm`).
- **`loanBook`**: sucesso (−1 cópia); `null` → `IllegalArgumentException`;
  livro deletado → `NoAvailableCopiesException` ("not found"); `Available=0`
  → `NoAvailableCopiesException` ("no available copies").
- **`requestLoan`**: sucesso; `Available=0` → `AuraHandledException`;
  args nulos → `AuraHandledException` (cobre `catch (Exception)`);
  **borrower deletado** → `insert` falha → `catch (DmlException)` →
  `AuraHandledException` (cobre `getNumDml()`/`getDmlMessage(0)`).
- **Gotcha**: `Library_Book__c.Title__c` é fórmula (espelha `Name`); a factory
  `LibraryTestDataFactory` grava `Name`.

## Obstáculos & solução

- **2026-09-01 — Mensagem de erro sumindo no LWC.** Exceção customizada crua
  de método `@AuraEnabled` → cliente recebe erro genérico. **Solução:** wrapper
  `requestLoan` relança como `AuraHandledException` + `setMessage()`.
- **2026-09-01 — Restringir SOSL a "título ou autor".** `FIND` não aceita
  lista de campos. **Solução:** `IN ALL FIELDS` (só há campos de texto
  relevantes no objeto) + `sanitizeSoslTerm` para caractere reservado.
- **2026-09-01 — Deploy OK.** A classe compilou e deployou no org junto com o
  resto do pacote (os objetos/campos custom já existem lá). **Pendente:**
  testes unitários da classe (SOSL usa `Test.setFixedSearchResults`) e
  confirmar se os objetos estão versionados em
  `force-app/main/default/objects/` (ver
  [[2026-09-01 — Apex Developer Challenge — DigiLibrary]]).
- **2026-09-02 — Mensagens em inglês.** `NoAvailableCopiesException` /
  `IllegalArgumentException` de `loanBook` traduzidas ("Book not found.",
  "Select a book and a borrower…", "The book \"X\" has no available copies
  right now…") — requisito do cliente, essas mensagens chegam ao toast do LWC
  via `AuraHandledException`. Sem mudança de lógica; ajustar asserts de
  mensagem nos testes quando forem escritos.

## 🧠 Para o acervo
- [[Apex · Erro de Apex que chega ao LWC com AuraHandledException]] — extraído
  em 2026-09-01 (só `AuraHandledException` repassa `message` ao JS +
  `setMessage()`; camada de domínio com exceção tipada × camada `@AuraEnabled`
  que adapta para a UI).
- [[Data-SOQL · Busca textual por título ou autor com SOSL]] — extraído em
  2026-09-01 (`FIND :key IN ALL FIELDS RETURNING ...`, curinga só no fim,
  `sanitizeSoslTerm`, `cacheable=true`, `Test.setFixedSearchResults` no teste).
