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
  - LWC-Aura
abertura: 2026-09-01
prazo: 2026-09-03
parent: "[[2026-09-01 — Apex Developer Challenge — DigiLibrary]]"
tags:
  - tarefa
  - lwc
---
# Interface de busca e empréstimo (LWC)

## Contexto
Subtarefa promovida a nota própria a partir de
[[2026-09-01 — Apex Developer Challenge — DigiLibrary]] — componente de
front-end do desafio, consumindo
[[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]].

Desenvolver um LWC (ou Visualforce Page, decisão a confirmar — LWC é o
padrão do projeto STRONG, ver decisões em [[STRONG — Book Management]]) que:
- Permite buscar livros por título ou autor (chama
  `LibraryService.searchBooks`).
- Exibe os detalhes do livro, incluindo cópias disponíveis.
- Tem um botão "Solicitar empréstimo" por linha/card, que chama
  `LibraryService.loanBook` e trata o erro de `NoAvailableCopiesException`
  exibindo mensagem amigável ao usuário.

## Subtarefas
- [x] Decidir Visualforce vs. LWC (default: LWC, alinhado ao padrão do ✅ 2026-09-01
      projeto) 🔼
- [x] Criar componente de busca (input + chamada a `searchBooks`) — ✅ 2026-09-01
      `libraryBookSearch`, `@wire` reativo + debounce 300 ms 🔼
- [x] Criar listagem/detalhe dos livros com cópias disponíveis — ✅ 2026-09-01
      cards com título, autor e badge `X de Y disponivel(is)` 🔼
- [x] Implementar botão "Solicitar empréstimo" + tratamento de erro de ✅ 2026-09-01
      `NoAvailableCopiesException` (toast) 🔺
- [x] Integrar o botão na listagem da busca — `c-library-loan-button` por ✅ 2026-09-01
      card + `refreshApex` no evento `loancreated` 🔼
- [x] LWCs de lista próprios (`libraryBookList` / `libraryLoanList`) + ✅ 2026-09-01
      message channel `LibraryRefresh__c` para recarregar ao criar empréstimo 🔼
- [x] Ação "Excluir" por linha no `libraryLoanList` (`deleteRecord` + ✅ 2026-09-01
      confirm), devolvendo a cópia ao acervo via trigger `after delete` 🔼
- [x] Traduzir toda a interface para inglês (labels, botões, textos ✅ 2026-09-02
      auxiliares, toasts) — requisito do cliente 🔼
- [x] Testes Jest dos 4 LWCs (`libraryBookSearch`, `libraryLoanButton`, ✅ 2026-09-02
      `libraryBookList`, `libraryLoanList`) — 29 testes, cobertura de linhas
      ~94% (todos ≥ 93%) 🔽

## O que foi feito

### 2026-09-01 — `libraryLoanButton` (botão + toast de erro/sucesso)

Decisão VF vs. LWC: **LWC** (padrão do projeto STRONG). Criado
`force-app/main/default/lwc/libraryLoanButton/` (API 65.0) como componente
reutilizável — recebe o livro por `@api recordId` (record page de
`Library_Book__c`) ou por `@api bookId` / `bookTitle` (embutido na busca),
tem um `lightning-record-picker` de Contact para o solicitante.

**Fluxo e toast:**

```js
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import requestLoan from '@salesforce/apex/LibraryService.requestLoan';

async handleRequestLoan() {
    this.loading = true;
    try {
        const loanId = await requestLoan({
            bookId: this.effectiveBookId,
            borrowerId: this.borrowerId
        });
        this.dispatchEvent(new ShowToastEvent({
            title: 'Emprestimo registrado',
            message: this.bookTitle ? `"${this.bookTitle}" foi emprestado com sucesso.`
                                    : 'Emprestimo registrado com sucesso.',
            variant: 'success'
        }));
        this.dispatchEvent(new CustomEvent('loancreated', {
            detail: { bookId: this.effectiveBookId, loanId }
        }));
    } catch (error) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Nao foi possivel registrar o emprestimo',
            message: this.getErrorMessage(error),   // error.body.message vindo da AuraHandledException
            variant: 'error',
            mode: 'sticky'
        }));
    } finally {
        this.loading = false;
    }
}

// normaliza os formatos de erro do Apex/LWC
getErrorMessage(error) {
    if (Array.isArray(error?.body)) return error.body.map((e) => e.message).join(', ');
    if (typeof error?.body?.message === 'string') return error.body.message;
    if (typeof error?.message === 'string') return error.message;
    return 'Erro inesperado ao registrar o emprestimo. Tente novamente.';
}
```

### Leitura técnica

- **Toast = `ShowToastEvent` de `lightning/platformShowToastEvent`**, só
  funciona em contexto Lightning. A tela padrão de criação de registro (onde
  o erro apareceu no teste) **não** dispara toast — mostra banner; por isso o
  fluxo de empréstimo tem que passar por este LWC.
- **`mode: 'sticky'` no erro** para o usuário conseguir ler a mensagem (o
  `dismissible` padrão some em ~3 s).
- **`getErrorMessage`** cobre os vários formatos: `error.body` pode ser array
  (`page errors`), objeto com `message` (`AuraHandledException`,
  `DmlException`) ou o erro pode nem ter `body` (falha de rede/JS).
- **Depende de `LibraryService.requestLoan`** (não `loanBook`) — é o wrapper
  que devolve `AuraHandledException`, cuja mensagem é a única que chega em
  `error.body.message`. Ver
  [[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]].
- **`loancreated`**: evento custom para a futura listagem da busca atualizar
  o contador de cópias sem refetch geral.
- **`disabled`** enquanto `loading` ou sem livro/solicitante — evita duplo
  clique / chamada inválida.

### 2026-09-01 (cont.) — dependência de busca pronta

`LibraryService.searchBooks(String)` foi implementado do lado Apex
(`@AuraEnabled(cacheable=true)`, SOSL por título/autor, `LIMIT 50` — ver
[[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]]). O componente de
busca ainda não foi criado, mas já pode consumir via `@wire(searchBooks, {
searchTerm: '$term' })` ou imperativo; o `libraryLoanButton` entra como filho
de cada linha/card passando `bookId` / `bookTitle` e ouvindo `loancreated`
para atualizar as cópias.

### 2026-09-01 — `libraryBookSearch` (busca + lista + integração do botão)

Criado `force-app/main/default/lwc/libraryBookSearch/` (API 65.0). Fecha as
subtarefas de busca, listagem e integração do botão (só falta o Jest).

**Estrutura:**

- `lightning-input type="search"` (título ou autor) com **debounce de 300 ms**
  antes de mexer no parâmetro reativo.
- `lightning-record-picker` de Contact **único no topo** — o `borrowerId`
  desce para todos os cards; o `libraryLoanButton` deixou de exigir picker
  próprio quando recebe `bookId` (modo embutido).
- `@wire(searchBooks, { searchTerm: '$searchKey' })` guardando o resultado em
  `wiredResult`; `wiredBooks()` mapeia cada livro para um view-model com
  `copiesLabel` (`"X de Y disponivel(is)"`) e `badgeClass`
  (`slds-theme_error`/`_success`).
- Lista de cards: título, autor, badge de cópias e
  `<c-library-loan-button book-id book-title borrower-id onloancreated>`.
- `handleLoanCreated()` → `refreshApex(this.wiredResult)` — revalida o wire
  para o contador de cópias cair na hora (padrão de
  [[LWC-Aura · Atualizar lista com refreshApex]]).
- Estados: prompt ("digite ao menos dois caracteres"), spinner, erro
  (`getErrorMessage`), "nenhum livro encontrado".

**Alteração no `libraryLoanButton`:** novo `@api borrowerId`; o picker interno
só aparece em uso avulso (record page, sem `bookId`). `effectiveBorrowerId` =
`borrowerId ?? selectedBorrowerId`.

**Exposição:** `libraryBookSearch` em `lightning__AppPage` / `HomePage` /
`Tab`; `libraryLoanButton` segue em record page de `Library_Book__c` + App/Home.

**Leitura técnica:**

- **`@wire` reativo + `refreshApex`** em vez de imperativo: ganha o cache do
  LDS (o `searchBooks` é `cacheable=true`) e o refresh pós-empréstimo é
  barato. Exige guardar o objeto do wire — `wiredBooks(result)` inteiro, não
  `{ data, error }` desestruturado.
- **Debounce** evita uma chamada SOSL por tecla; só dispara com `length === 0`
  ou `>= 2` (alinhado ao guard do Apex).
- **View-model no JS**: template LWC não faz expressão, então
  `copiesLabel`/`badgeClass`/`unavailable` são calculados no handler.
- **Um picker para N cards**: evita N record-pickers e N seleções repetidas;
  o botão fica `disabled` até o `borrowerId` chegar.
- **`key={book.id}`** no `for:each` (Id do livro, estável).

### 2026-09-01 — Atualizar as list views da página no `loancreated`

Pedido: com o componente numa Home page ao lado das list views padrão de
`Library_Book__c` e `Library_Book_Loan__c`, clicar em "Solicitar empréstimo"
deveria recarregar essas listas.

`handleLoanCreated()` passou a fazer 3 coisas:

```js
import { RefreshEvent } from 'lightning/refresh';

handleLoanCreated() {
    const localRefresh = refreshApex(this.wiredResult);   // 1. lista própria

    this.dispatchEvent(new RefreshEvent());               // 2. resto da página (API suportada)

    try {                                                 // 3. fallback legado
        // eslint-disable-next-line no-eval
        const legacyRefresh = eval("$A.get('e.force:refreshView')");
        if (legacyRefresh) { legacyRefresh.fire(); }
    } catch (e) { /* sem contexto Aura / LWS */ }

    return localRefresh;
}
```

**Leitura técnica:**

- **`RefreshEvent` de `lightning/refresh`** é a API oficial (GA Winter '24)
  para pedir refresh a outros componentes da página. Componentes padrão que
  adotaram a *RefreshView API* (related lists, algumas list views) respondem;
  a cobertura em App/Home page ainda está crescendo.
- **`$A.get('e.force:refreshView')`** é o hack Aura antigo — funciona dentro
  do LEX sob Locker, **não** sob Lightning Web Security (o `try/catch` engole).
  Mantido só como rede de segurança enquanto o `RefreshEvent` não cobre 100%.
- **`refreshApex` continua** para a lista interna do próprio componente (o
  `RefreshEvent` não revalida o wire deste componente de forma garantida).
- Se as list views ainda não recarregarem no org, a alternativa robusta é
  trocar as list views padrão por LWC próprios (`getListUi` + `refreshApex`).

### 2026-09-01 — `RefreshEvent` não pegou; migrado p/ LWCs de lista + LMS

A ressalva se confirmou: as list views padrão na Home page **não** recarregaram
com `RefreshEvent`. Solução definitiva — listas próprias + Lightning Message
Service.

**Novos artefatos:**

| Arquivo | Papel |
|---|---|
| `messageChannels/LibraryRefresh.messageChannel-meta.xml` | canal `LibraryRefresh__c` (campos `source`, `bookId`) |
| `classes/LibraryListController.cls` | `getBooks()` / `getRecentLoans()` — ambos `@AuraEnabled(cacheable=true)`, `LIMIT 200` |
| `lwc/libraryBookList` | `lightning-datatable` de `Library_Book__c` (título, autor, disponíveis, total) |
| `lwc/libraryLoanList` | `lightning-datatable` de `Library_Book_Loan__c` (nº, solicitante, livro, início, devolução) |

**Fluxo:**

```js
// libraryBookSearch.handleLoanCreated(event)
refreshApex(this.wiredResult);                                   // lista de cards própria
publish(this.messageContext, LIBRARY_REFRESH_CHANNEL, {          // avisa as listas irmãs
    source: 'libraryBookSearch', bookId: event?.detail?.bookId
});
this.dispatchEvent(new RefreshEvent());                          // nudge best-effort p/ o resto

// libraryBookList / libraryLoanList (connectedCallback)
this._subscription = subscribe(
    this.messageContext, LIBRARY_REFRESH_CHANNEL,
    () => refreshApex(this.wiredResult),
    { scope: APPLICATION_SCOPE }
);
```

**Leitura técnica:**

- **Controller `cacheable=true` + `refreshApex`** dá controle total: nada de
  depender de a Salesforce ter portado a list view padrão para RefreshView.
- **LMS para irmãos na mesma página**: `publish`/`subscribe` de
  `lightning/messageService` + canal `.messageChannel-meta.xml` (`isExposed`).
  Funciona sob Lightning Web Security (ao contrário do `force:refreshView`).
- **`APPLICATION_SCOPE`** na subscrição — pega a mensagem mesmo se o
  componente não estiver na "área ativa" (ex.: utility bar); default seria só
  ativo.
- **`subscribe` no `connectedCallback`, `unsubscribe` no
  `disconnectedCallback`** — `this.messageContext` (wire) já resolvido nessa
  fase.
- **Campos de relação no `lightning-datatable`**: não aceita `Book__r.Title__c`
  em `fieldName` — achatar no map do wired handler (`bookTitle`,
  `borrowerName`).
- **`type: 'date-local'`** nas colunas de data → sem shift de timezone.
- **`RefreshEvent` mantido** (barato) para qualquer componente da página que
  um dia honre a API; o hack `eval("$A...")` foi **removido**.
- O `libraryBookSearch` continua com `@wire(MessageContext)` para publicar.

### 2026-09-01 — Ação "Excluir empréstimo" no `libraryLoanList`

Melhoria pedida: botão para excluir o `Library_Book_Loan__c` na própria linha;
ao excluir, `Available_Copies__c` volta +1. **A regra +1 já é do trigger**
(`after delete` → `handleAfterDelete`, ver
[[2026-09-01-A — Trigger de empréstimo (Library_Book_Loan__c)]]) — aqui é só
a UI que dispara o delete.

```js
// coluna de ação
{ type: 'action', typeAttributes: { rowActions: [
    { label: 'Excluir', name: 'delete', iconName: 'utility:delete' }
] } }

async confirmAndDelete(row) {
    const ok = await LightningConfirm.open({
        message: `Excluir o emprestimo ${row.name}? A copia de "${row.bookTitle}" volta ao acervo.`,
        variant: 'header', label: 'Confirmar exclusao'
    });
    if (!ok) return;
    try {
        await deleteRecord(row.Id);                       // LDS; o trigger faz o +1
        this.dispatchEvent(new ShowToastEvent({ title: 'Emprestimo excluido', variant: 'success', ... }));
        await refreshApex(this.wiredLoansResult);         // recarrega a própria lista
        publish(this.messageContext, LIBRARY_REFRESH_CHANNEL, { source: 'libraryLoanList', bookId: row.bookId });
    } catch (error) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Nao foi possivel excluir...', variant: 'error', mode: 'sticky', ... }));
    }
}
```

**Leitura técnica:**

- **`deleteRecord` de `lightning/uiRecordApi`** — sem Apex novo; respeita FLS
  e permissão de delete do usuário, e o trigger dispara normalmente.
- **`LightningConfirm.open`** (`lightning/confirm`) — modal nativo, retorna
  `Promise<boolean>`; exclusão é destrutiva, então confirma antes.
- **Reaproveita o canal `LibraryRefresh__c`**: após o delete, `publish` faz o
  `libraryBookList` e o `libraryBookSearch` recarregarem e mostrarem a cópia
  devolvida. Para isso o **`libraryBookSearch` passou a `subscribe`** no canal
  também (antes só publicava).
- **`bookId` no view-model** do loan (`row.Book__c`) — adicionado para mandar
  no payload da mensagem.
- Sem loop: `refreshApex` não publica; o `publish` do próprio componente só
  provoca um `refreshApex` extra (idempotente, barato).

### 2026-09-02 — Interface toda em inglês (requisito do cliente)

Cliente exige a UI 100% em inglês. Traduzidos **os 4 LWCs** + as mensagens
Apex que aparecem em toast/banner:

| Onde | pt → en (exemplos) |
|---|---|
| `libraryBookSearch` | "Biblioteca - Buscar e emprestar" → "Library - Search & Loan"; "Solicitante" → "Borrower"; "Buscar por titulo ou autor" → "Search by title or author"; "Digite ao menos dois caracteres..." → "Type at least two characters to search."; badge "X de Y disponivel(is)" → "X of Y available" |
| `libraryLoanButton` | "Solicitar emprestimo" → "Request loan"; toasts "Loan registered" / "Could not register the loan" |
| `libraryBookList` | card "Livros" → "Books"; colunas Title / Author / Available / Total; "Nenhum livro cadastrado." → "No books registered." |
| `libraryLoanList` | card "Emprestimos" → "Loans"; colunas Loan / Borrower / Book / Start date / Due date; ação "Excluir" → "Delete"; confirm "Delete loan …? The copy of … returns to the collection." / "Confirm deletion"; toasts "Loan deleted" / "Could not delete the loan" |
| `LibraryService.cls` | `NoAvailableCopiesException` / `IllegalArgumentException`: "Book not found.", "Select a book and a borrower…", "The book \"X\" has no available copies right now. Try again once a copy is returned." |
| `LibraryBookLoanTriggerHandler.cls` | `NO_COPIES_MESSAGE` mesma frase em inglês; fallback `'selecionado'` → `'selected'` |

Nota: as mensagens de erro que o toast do `libraryLoanButton` mostra vêm do
Apex (`AuraHandledException`), por isso `LibraryService` e o handler também
foram traduzidos — senão o cliente veria português num toast de erro.

### Estado atual (2026-09-02, atualizado após o Extra Challenge)

As seções acima são log cronológico; este é o retrato da versão atual.

| Componente | Papel na versão atual |
|---|---|
| `libraryBookSearch` | Card "Library - Search & Loan": `record-picker` de Borrower + input + **botão "Search"** (`disabled` até `term.trim().length >= 2`; Enter também dispara). Chamada **imperativa** a `LibraryService.searchBooks` (busca local SOSL + Open Library). Cada linha: local → badge "X of Y available" + `c-library-loan-button`; externa → `<lightning-button "Register / Import">` → `importBook` + `markImported` otimista. **Publica e assina** `LibraryRefresh__c`; após loan/import → `runSearch()` + `publish` + `RefreshEvent`. Sem `@wire`/`refreshApex`/debounce. Detalhe em [[2026-09-02-D — Integração Open Library (API externa)]]. |
| `libraryLoanButton` | Botão "Request loan" + spinner. `@api bookId`/`bookTitle`/`borrowerId`/`recordId`; picker interno só em uso avulso. Chama `LibraryService.requestLoan`, toasts de sucesso/erro, emite `loancreated`. |
| `libraryBookList` | `lightning-datatable` de `Library_Book__c` (Title/Author/Available/Total) via `LibraryListController.getBooks`. Assina `LibraryRefresh__c` → `refreshApex`. Datatable com wrapper `slds-var-p-horizontal_small` (bordas afastadas do card). |
| `libraryLoanList` | `lightning-datatable` de `Library_Book_Loan__c` (Loan/Borrower/Book/Start date/Due date) via `getRecentLoans`. Assina o canal. **Ação "Delete"** por linha: `LightningConfirm` → `deleteRecord` → toast + `refreshApex` + `publish` (o trigger `after delete` faz o +1 cópia). Mesmo wrapper de padding. |
| Apoio | `LibraryService` (`searchBooks` unificado + backfill SOQL, `importBook`, `loanBook`, `requestLoan`); `OpenLibraryService` (callout resiliente) + Named Credential `Open_Library`; `LibraryListController` (`getBooks`/`getRecentLoans`, `cacheable`, `LIMIT 200`); canal `LibraryRefresh__c` (`source`, `bookId`). |

Toda a UI e as mensagens Apex que chegam a toast/banner estão em **inglês**.
Deployado e validado no org (Home page do app DigiLibrary).

**Testes (2026-09-02):** o Apex de apoio `LibraryListController` está coberto
por `LibraryListControllerTest` (100%, ver
[[2026-09-01 — Apex Developer Challenge — DigiLibrary]]).

### 2026-09-02 — Testes Jest dos 4 LWCs

`__tests__/*.test.js` em cada bundle. **29 testes, 4 suites, todos passam.**
Cobertura de linhas: `libraryLoanButton` 96,5%, `libraryBookList` 93,8%,
`libraryLoanList` 93,6%, `libraryBookSearch` 93,2% — não coberto: os ramos de
fallback de `getErrorMessage`/`reduceError` e o getter morto `showPrompt`
(bloco comentado no HTML).

**O que cobrem:**

- `libraryLoanButton`: picker interno oculto/visível conforme `bookId`;
  botão `disabled` até book+borrower; sucesso → toast + evento `loancreated`
  com `{bookId, loanId}`; falha → toast `error` sticky, sem `loancreated`;
  borrower interno em modo avulso; normalização de erro (array / `{message}`).
- `libraryBookList`: `subscribe`/`unsubscribe` no ciclo de vida; wire com
  dados → datatable; vazio → "No books registered"; wire com erro → mensagem;
  mensagem no canal → `refreshApex`.
- `libraryLoanList`: flatten das relações (`Borrower__r.Name`,
  `Book__r.Title__c`); `rowaction` `delete` → `LightningConfirm` →
  `deleteRecord` → toast + `refreshApex` + `publish`; confirm negado → não
  deleta; erro no delete → toast; `rowaction` não-delete ignorado; wire erro.
- `libraryBookSearch`: botão "Search" `disabled` até 2 chars; sem
  auto-busca; clique → `searchBooks({searchTerm})` + linhas local/externa
  (loan button vs "Register / Import"); Enter dispara; erro → mensagem;
  import → `importBook` + toast + re-busca + `publish`; import falha →
  botão reabilita; `loancreated` do filho → re-busca + `publish`; canal
  antes de qualquer busca → no-op.

**Notas de montagem (sfdx-lwc-jest v7):**

- **Node ≥ 20** para rodar (`sfdx-lwc-jest` 7). O ambiente tinha Node 18 como
  default; usado o 24 via nvm.
- Não mockar `lightning/messageService` / `lightning/uiRecordApi` /
  `lightning/platformShowToastEvent` / `lightning/refresh` — os *stubs* do
  sfdx-lwc-jest já exportam `subscribe`/`publish`/`deleteRecord` como
  `jest.fn()` e `ShowToastEvent`/`RefreshEvent` como classes.
- `LightningConfirm`: **reatribuir** `LightningConfirm.open = jest.fn()`
  (o stub tem `static open()` que lança); `jest.mock('lightning/confirm', …)`
  não pega por causa do *resolver* customizado.
- `@salesforce/apex/*`, `@salesforce/apex` (`refreshApex`) e
  `@salesforce/messageChannel/*` **precisam** de `jest.mock(…, { virtual: true })`
  (não há stub). Wires de Apex via `createApexTestWireAdapter`.
- Toast: ouvir `element.addEventListener('lightning__showtoast', handler)`.
- `jest.config.js` ganhou `collectCoverageFrom` explícito (`**/lwc/**/*.js`
  menos `__tests__`) — o glob default do sfdx-lwc-jest não estava instrumentando.

### 2026-09-02 — `libraryBookSearch` reescrito para o Extra Challenge

Deixou de usar `@wire(searchBooks)` (agora faz callout → não é `cacheable`) e
passou a chamar **`searchBooks` imperativo**. Cada linha da busca agora é
`local` (→ `c-library-loan-button`) ou `external` (→
`<lightning-button label="Register / Import">` que chama
`LibraryService.importBook` e re-executa a busca). `refreshApex`/`wiredResult`
saíram; o refresh vira `runSearch()` + `publish` no canal. O disparo da busca
virou **botão "Search"** (debounce removido) — como agora bate na Open Library,
buscar a cada tecla geraria um callout por letra. `handleImport` faz
`markImported` (update otimista) antes do `runSearch()` de reconciliação.
Detalhe (incl. bug do índice SOSL e correção por backfill SOQL) em
[[2026-09-02-D — Integração Open Library (API externa)]].

### 2026-09-02 — Padding das tabelas (`libraryBookList` / `libraryLoanList`)

O `<lightning-datatable>` ficava no slot padrão do `lightning-card` (sem
padding horizontal) → bordas rentes ao card. Envolvido em
`<div class="slds-var-p-horizontal_small slds-var-p-bottom_small">` nos dois
componentes. Cosmético.

## Obstáculos & solução

- **2026-09-01 — Erro do trigger aparecia como painel feio na tela padrão e
  sem toast.** Toast não existe fora do Lightning; a mensagem da exceção
  customizada não chega ao JS. **Solução:** botão LWC dedicado chamando
  `requestLoan` (→ `AuraHandledException`) e renderizando `ShowToastEvent`.
  Ver também [[2026-09-01-A — Trigger de empréstimo (Library_Book_Loan__c)]]
  (mudança `throw` → `addError` para o caminho da UI padrão).
- **2026-09-01 — `RefreshEvent` não recarregou as list views padrão** na Home
  page (cobertura ainda incompleta em App/Home). **Solução:** LWCs de lista
  próprios (`libraryBookList` / `libraryLoanList`) + Lightning Message Service
  (canal `LibraryRefresh__c`) — ver subseção acima.
- **2026-09-01 — Deploy falhou:** `Unable to retrieve metadata for descriptor:
  markup://c:__LightningMessageChannel__LibraryRefresh__c`. O
  `manifest/package.xml` não tinha o tipo `LightningMessageChannel`.
  **Solução:** adicionado ao manifest + deploy do canal antes dos LWCs
  (`sf project deploy start -d force-app/main/default/messageChannels`, depois
  `-d force-app`). Depois disso o deploy passou e o refresh das duas listas
  ao solicitar empréstimo funcionou no org.

## 🧠 Para o acervo
- Candidato: **"Padrão de tratamento de erro Apex→LWC: `try/catch` +
  `ShowToastEvent` sticky + helper `getErrorMessage` que normaliza
  `error.body` (array | objeto | ausente)."** Linkar aqui quando extraído.
- Candidato: **"Busca-as-you-type em LWC: `lightning-input type=search` +
  debounce + `@wire` com parâmetro reativo `'$searchKey'` + `refreshApex` no
  resultado guardado; view-model calculado no JS."** Linkar quando extraído.
- Candidato: **"Refrescar componentes irmãos na mesma página após DML:
  `RefreshEvent` não cobre list views padrão em App/Home → LWCs de lista
  próprios (`cacheable` + `refreshApex`) + Lightning Message Service
  (`publish`/`subscribe`, `APPLICATION_SCOPE`, canal `.messageChannel`).
  Compatível com LWS."** Linkar quando extraído.
- Candidato: **"Ação de exclusão em `lightning-datatable`: coluna
  `type: 'action'` + `onrowaction` → `LightningConfirm.open` → `deleteRecord`
  (`lightning/uiRecordApi`, sem Apex, respeita FLS e dispara trigger)."**
  Linkar quando extraído.
- Relacionada existente: [[LWC-Aura · Atualizar lista com refreshApex]].
