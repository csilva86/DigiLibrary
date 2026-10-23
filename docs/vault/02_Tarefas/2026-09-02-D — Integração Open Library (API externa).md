---
type: tarefa
dominio: salesforce
id:
fonte: Outro
projeto: "[[STRONG — Book Management]]"
cliente: STRONG
status: concluído
prioridade: média
area:
  - Integracoes
  - Apex
  - LWC-Aura
abertura: 2026-09-02
prazo: 2026-09-03
parent: "[[2026-09-01 — Apex Developer Challenge — DigiLibrary]]"
tags:
  - tarefa
  - apex
  - lwc
  - integracao
---
# Integração Open Library (API externa)

## Contexto
**Extra Challenge (opcional)** do enunciado DigiLibrary — estender a busca para
uma fonte externa e permitir importar livros que ainda não estão no catálogo.

- `searchBooks` deve consultar o local (SOSL) **e** a Open Library Search API
  (`https://openlibrary.org/search.json?q={term}`).
- A UI correlaciona por **título**: se o livro da API já existe em
  `Library_Book__c`, mostra `Available_Copies__c` + botão "Request Loan";
  se não existe, mostra "Register / Import Book".
- Importar cria o `Library_Book__c` (Title + Author da API) e o livro fica
  disponível para empréstimo.

Requisitos do Carlos: **Named Credential** (sem Remote Site Setting),
`try-catch` adequado.

## Subtarefas
- [x] Named Credential `Open_Library` (anônima, `NoAuthentication`) ✅ 2026-09-02
- [x] `OpenLibraryService.search(term)` — callout via `callout:Open_Library`, ✅ 2026-09-02
      parse defensivo, nunca lança 🔺
- [x] `LibraryService.searchBooks` unificado (local + externo, dedupe por ✅ 2026-09-02
      título, local primeiro) — deixou de ser `cacheable` 🔺
- [x] `LibraryService.importBook(title, author)` — cria `Library_Book__c` ✅ 2026-09-02
      (1 cópia), dedupe por `Name`, `try-catch` → `AuraHandledException` 🔺
- [x] LWC `libraryBookSearch` — chamada imperativa + botão "Register / Import" ✅ 2026-09-02
      por linha externa, re-busca após importar 🔼
- [x] Testes: `OpenLibraryServiceTest` (mock HTTP), `LibraryServiceTest` ✅ 2026-09-02
      atualizado — 38 testes, `OpenLibraryService` 100%, `LibraryService` 99% 🔺

## O que foi feito

### Named Credential (legacy, anônima)

`force-app/main/default/namedCredentials/Open_Library.namedCredential-meta.xml`:

```xml
<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Open Library</label>
    <endpoint>https://openlibrary.org</endpoint>
    <generateAuthorizationHeader>false</generateAuthorizationHeader>
    <principalType>Anonymous</principalType>
    <protocol>NoAuthentication</protocol>
</NamedCredential>
```

Deployou limpo. Formato **legacy** (não o novo par External Credential +
Named Credential) porque a API é pública sem auth — legacy anônimo é o caminho
mais simples e suportado. Sem Remote Site Setting (a Named Credential dispensa).

### `OpenLibraryService`

```apex
public static List<ExternalBook> search(String term) {
    List<ExternalBook> books = new List<ExternalBook>();
    if (String.isBlank(term)) { return books; }
    try {
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setTimeout(TIMEOUT_MS);                 // 10 s
        request.setEndpoint(
            'callout:Open_Library/search.json?limit=' + MAX_RESULTS +
            '&fields=title,author_name&q=' + EncodingUtil.urlEncode(term, 'UTF-8')
        );
        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) { return books; }   // log WARN + degrada
        books = parseDocs(response.getBody());
    } catch (CalloutException e) {
        System.debug(LoggingLevel.WARN, 'Open Library callout failed: ' + e.getMessage());
    } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'Open Library response unreadable: ' + e.getMessage());
    }
    return books;
}
```

- **Nunca lança**: HTTP != 200, `CalloutException` (DNS/timeout/named cred) e
  parse quebrado → lista vazia. Assim `searchBooks` degrada para "só local".
- `parseDocs`: `JSON.deserializeUntyped` + checagens `instanceof Map<String,Object>`
  / `instanceof List<Object>` antes de cada cast; ignora doc sem `title`;
  `firstAuthor` pega `author_name[0]`.
- `callout:Open_Library/...` — URL fora do código.

### `LibraryService.searchBooks` unificado

```apex
@AuraEnabled   // NÃO cacheable — faz callout
public static List<BookSearchResult> searchBooks(String searchTerm) {
    List<BookSearchResult> rows = new List<BookSearchResult>();
    if (String.isBlank(searchTerm) || searchTerm.trim().length() < MIN_SEARCH_LENGTH) {
        return rows;
    }
    Set<String> localTitleKeys = new Set<String>();
    for (Library_Book__c book : findLocalBooks(searchTerm)) {   // SOSL (extraído p/ método privado)
        rows.add(new BookSearchResult(book));                   // existsLocally=true, source LOCAL
        localTitleKeys.add(normalizeTitle(book.Title__c));
    }
    for (OpenLibraryService.ExternalBook ext : OpenLibraryService.search(searchTerm)) {
        if (localTitleKeys.contains(normalizeTitle(ext.title))) { continue; }   // dedupe
        rows.add(new BookSearchResult(ext.title, ext.author));  // existsLocally=false, source EXTERNAL
    }
    return rows;
}
```

- **DTO `BookSearchResult`** (`bookId`, `title`, `author`, `availableCopies`,
  `totalCopies`, `existsLocally`, `source`) com dois construtores — inner class
  **não pode ter método `static`** em Apex, então nada de `fromLocal()`.
- **Dedupe por título** normalizado (`trim().toLowerCase()`). `Title__c` é
  fórmula = `Name`, então a chave bate com o título da API.
- Local **primeiro** (é acionável); externo-só depois.
- `searchBooks` deixou de ser `cacheable` → o LWC passou a chamar **imperativo**
  (métodos `cacheable` não podem fazer callout).

### `LibraryService.importBook`

```apex
@AuraEnabled
public static Id importBook(String title, String author) {
    try {
        if (String.isBlank(title)) {
            throw new IllegalArgumentException('A title is required to import a book.');
        }
        String cleanTitle = title.trim();
        List<Library_Book__c> existing = [SELECT Id FROM Library_Book__c WHERE Name = :cleanTitle LIMIT 1];
        if (!existing.isEmpty()) { return existing[0].Id; }   // sem duplicar

        Library_Book__c book = new Library_Book__c(
            Name = cleanTitle,
            Author__c = String.isBlank(author) ? null : author.trim(),
            Total_Copies__c = 1,
            Available_Copies__c = 1                            // já loanable
        );
        insert book;
        return book.Id;
    } catch (DmlException e) {
        throw toAuraException(e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage());
    } catch (Exception e) {
        throw toAuraException(e.getMessage());
    }
}
```

### LWC `libraryBookSearch`

- `@wire(searchBooks)` → **imperativo** (`await searchBooks({searchTerm})`);
  `runSearch()` centraliza. (O disparo virou botão "Search" — ver subseção
  "Busca sob demanda" abaixo.)
- Cada linha: `existsLocally` → `<c-library-loan-button>`; senão →
  `<lightning-button label="Register / Import">` (`data-title`/`data-author`,
  `disabled={row.importing}`) + spinner.
- `handleImport` → `importBook({title, author})` → toast →
  `markImported(title, bookId)` (update otimista da linha para local) →
  `publishRefresh(bookId)` → `runSearch()` (reconcilia).
- Canal `LibraryRefresh__c`: subscribe → `runSearch()`; após loan/import →
  `publish` + `RefreshEvent`.
- `refreshApex`/`wiredResult` removidos (não há mais wire).

### 2026-09-02 — Busca sob demanda (botão "Search")

Com a busca agora batendo numa **API externa**, o debounce de 300 ms
disparava um callout a cada tecla. Trocado por **acionamento explícito**:

- Novo `<lightning-button label="Search">` ao lado do input, `variant="brand"`,
  `disabled={searchDisabled}` — habilitado só quando `term.trim().length >= 2`
  e não está carregando.
- `handleTermChange` só atualiza `this.term` (estado do botão); **não** busca.
- `handleTermKeyUp` → Enter no campo dispara `handleSearch` (mesma guarda).
- Dois estados de termo: `term` (input ao vivo) × `submittedTerm` (o que os
  resultados representam). `runSearch()` usa `submittedTerm`; os refreshes
  (loan/import/canal LMS) re-executam a última busca submetida, não o texto
  não confirmado.
- Debounce (`DEBOUNCE_MS`, `setTimeout`) removido.

### 2026-09-02 — Padding das tabelas nas listas irmãs

`libraryBookList` e `libraryLoanList`: o `<lightning-datatable>` ficava no
slot padrão do `lightning-card` (sem padding horizontal) → bordas laterais
rentes ao card. Envolvido em `<div class="slds-var-p-horizontal_small
slds-var-p-bottom_small">`. (Mudança cosmética, sem impacto em teste.)

## Obstáculos & solução

- **`static` em inner class** → *"static can only be used on methods of a top
  level type"*. Trocado `BookSearchResult.fromLocal/fromExternal` (static) por
  **construtores**.
- **`cacheable` + callout** são incompatíveis. `searchBooks` perdeu o
  `cacheable=true`; o LWC virou imperativo e re-executa a busca no lugar de
  `refreshApex`.
- **Testes de callout**: `OpenLibraryCalloutMock implements HttpCalloutMock`
  (`@IsTest`, factories `ok/status/rawBody/failing`); todo teste de
  `searchBooks` agora precisa de `Test.setMock` além do
  `Test.setFixedSearchResults`.
- **Cobrir o ramo `catch (DmlException)` de `importBook`**: `Name` tem limite
  de 80 chars → `importBook('X'.repeat(200), ...)` gera `STRING_TOO_LONG`.

- **2026-09-02 — Bug intermitente: livro importado reaparecia como "Not in the
  library yet".** Toast de sucesso OK (o `Library_Book__c` era criado), mas o
  `searchBooks` re-executado logo depois não via o livro. **Causa:** o índice
  do **SOSL (`FIND`) não é atualizado sincronamente** — leva alguns segundos.
  O `findLocalBooks` (SOSL) não trazia o registro novo → ele saía de
  `localTitleKeys` → o resultado da Open Library com o mesmo título deixava de
  ser deduplicado. Intermitente porque às vezes o índice já tinha atualizado.
  **Solução:** *backfill* por **SOQL** em `searchBooks` —
  `booksByExactTitle(...)` faz `SELECT ... WHERE Name IN :títulosExternos` (que
  a SOSL não trouxe); match → vira linha `LOCAL` acionável. SOQL é
  transacionalmente consistente. No LWC, `markImported(title, bookId)` também
  faz um update otimista da linha para "local" logo após o `importBook`
  (`runSearch()` depois reconcilia). Teste:
  `searchBooks_bookMissedBySosl_isBackfilledFromSoql`
  (`Test.setFixedSearchResults(new List<Id>())` simula o índice atrasado).

## Resultado

Deploy OK no org (classes + LWCs + `NamedCredential Open_Library`). Inclui o
botão "Search" e o backfill SOQL contra a latência do índice SOSL.
**38 testes Apex, 100% passam.** Cobertura: `OpenLibraryService` 100%,
`LibraryService` 99.2% (1/131 — ramo `: e.getMessage()` de ternário em
`catch (DmlException)` com `getNumDml()==0`, impraticável), trigger/handler/
`LibraryListController` 100%.

## 🧠 Para o acervo
- [[MOC · Integracoes]]
- [[Integracoes · Callout resiliente para API pública com Named Credential]] —
  extraído em 2026-09-02 (Named Credential anônima + `try-catch` em camadas +
  parse defensivo com `instanceof` + `HttpCalloutMock` reutilizável; inclui a
  armadilha `cacheable` × callout → LWC imperativo).
- Candidato: **"SOSL (`FIND`) tem índice near-real-time — um registro
  recém-inserido some da busca por alguns segundos. Quando a decisão precisa
  ser consistente logo após o insert (ex.: dedupe pós-import), completar com
  um SOQL (`WHERE Name IN ...`), que é transacional."** Linkar em
  [[Data-SOQL · Busca textual por título ou autor com SOSL]] quando extraído.
- Relacionadas: [[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]],
  [[2026-09-01-C — Interface de busca e empréstimo (LWC)]],
  [[Apex · Erro de Apex que chega ao LWC com AuraHandledException]].
