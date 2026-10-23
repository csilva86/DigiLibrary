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
  - Apex
  - LWC-Aura
  - Data-SOQL
abertura: 2026-09-01
prazo:
parent:
tags:
  - tarefa
  - apex
  - lwc
  - soql
---
# Apex Developer Challenge — DigiLibrary

## Contexto
Documento de teste técnico recebido da StrongCRM (PDF *"StrongCRM - Development
Test"*): **Apex Developer Challenge — DigiLibrary**. Objetivo: desenvolver uma
funcionalidade de gerenciamento de livros para uma biblioteca digital corporativa
(DigiLibrary), cobrindo inventário, busca por título/autor e empréstimo de livros.
Não é um ticket de sistema (sem ID) — tratado como origem "Outro". Vinculado ao
projeto [[STRONG — Book Management]] (cliente STRONG), que já contém o escopo
completo e os ambientes de trabalho.

**Requisitos funcionais:**
1. Registro de empréstimo — só permite empréstimo se houver cópias disponíveis
   (tratamento de erro apropriado); decrementa `Available_Copies__c` ao
   registrar; incrementa ao remover o empréstimo.
2. Busca e detalhes de livros — interface (VF ou LWC) para buscar por título ou
   autor, exibindo cópias disponíveis e botão para solicitar empréstimo.

**Solução técnica esperada:**
- Objeto customizado `Library_Book__c` (`Title__c`, `Author__c`,
  `Available_Copies__c`, `Total_Copies__c`).
- Objeto customizado `Library_Book_Loan__c` (`Borrower__c` → Contact,
  `Book__c` → Library_Book__c, `Loan_Start_Date__c`, `Loan_End_Date__c`).
- Trigger em `Library_Book_Loan__c`: valida `Available_Copies__c > 0`,
  decrementa no insert, incrementa no delete.
- Exceção customizada `NoAvailableCopiesException`.
- Interface de busca/empréstimo (VF ou LWC) usando SOSL.
- Classe `LibraryService` com `searchBooks(String searchTerm)` (SOSL) e
  `loanBook(Id bookId, Id borrowerId)`.
- SOQL/SOSL otimizados na trigger e na `LibraryService`.

**Entregáveis:** código-fonte (trigger, `LibraryService`,
`NoAvailableCopiesException`), interface de usuário (VF/LWC + controllers) e
testes unitários com cobertura mínima de 85%.

> Prioridade e prazo não vieram informados no documento; prioridade assumida
> como **média** por ser um teste avaliativo. Ajustar se houver deadline real.

## Subtarefas
- [x] Criar objeto customizado `Library_Book__c` (`Title__c`, `Author__c`, ✅ 2026-09-01
      `Available_Copies__c`, `Total_Copies__c`) 🔼
- [x] Criar objeto customizado `Library_Book_Loan__c` (`Borrower__c` → ✅ 2026-09-01
      Contact, `Book__c` → Library_Book__c, `Loan_Start_Date__c`,
      `Loan_End_Date__c`) 🔼
- [x] Implementar trigger de empréstimo + teste (100%) — ver ✅ 2026-09-02
      [[2026-09-01-A — Trigger de empréstimo (Library_Book_Loan__c)]] 🔺
- [x] Criar exceção customizada `NoAvailableCopiesException` ✅ 2026-09-01 🔽
- [x] Implementar `LibraryService` (`searchBooks` SOSL + `loanBook` + ✅ 2026-09-02
      `requestLoan`) + teste (98%) — ver
      [[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]] 🔺
- [/] Desenvolver interface de busca/empréstimo (busca + lista + botão/toast +
      LWCs de lista com LMS + exclusão + UI em inglês feitos; falta Jest) — ver
      [[2026-09-01-C — Interface de busca e empréstimo (LWC)]] 🔼
- [x] Escrever testes unitários Apex (trigger, `LibraryService`, ✅ 2026-09-02
      `LibraryListController`) — org-wide 99% 🔺
- [x] **Extra Challenge** — integração Open Library (busca externa + import) ✅ 2026-09-02
      via Named Credential — ver
      [[2026-09-02-D — Integração Open Library (API externa)]] 🔽
- [x] Escrever testes Jest dos LWCs — 29 testes, linhas ~94% — ver ✅ 2026-09-02
      [[2026-09-01-C — Interface de busca e empréstimo (LWC)]] 🔼
- [/] Deploy/validação no org do projeto [[STRONG — Book Management]] —
      deploy OK em 2026-09-01 (Apex + LWCs + `LibraryRefresh__c`); falta
      validação funcional completa e testes 🔽

## O que foi feito

- **2026-09-01** — Trigger de empréstimo + `NoAvailableCopiesException`
  implementados. Detalhes e leitura técnica em
  [[2026-09-01-A — Trigger de empréstimo (Library_Book_Loan__c)]].
- **2026-09-01** — Tratamento de erro amigável ponta a ponta:
  - trigger passou de `throw` para `addError(NoAvailableCopiesException)` —
    mensagem limpa na UI padrão, partial success em lote
    ([[2026-09-01-A — Trigger de empréstimo (Library_Book_Loan__c)]]);
  - `LibraryService.loanBook` (lança a exceção customizada) + `requestLoan`
    `@AuraEnabled` que converte para `AuraHandledException`
    ([[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]]);
  - LWC `libraryLoanButton` com `ShowToastEvent` (sucesso/erro) e evento
    `loancreated` ([[2026-09-01-C — Interface de busca e empréstimo (LWC)]]).
  - Ainda faltam: objetos custom no repo, componente LWC de busca (o Apex
    `searchBooks` já existe) e todos os testes (Apex ≥ 85% + Jest).

- **2026-09-01** — `LibraryService.searchBooks(String)` implementado com SOSL
  (`FIND :key IN ALL FIELDS RETURNING Library_Book__c(...)`, wildcard de
  prefixo, `sanitizeSoslTerm`, `cacheable=true`, `LIMIT 50`). Detalhe em
  [[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]].
- **2026-09-01** — LWC `libraryBookSearch`: busca por título/autor
  (`lightning-input` + debounce + `@wire` reativo), lista de cards com badge de
  cópias, `c-library-loan-button` por card e `refreshApex` no evento
  `loancreated`. `libraryLoanButton` ganhou `@api borrowerId` (picker interno
  só em uso avulso). Falta só o Jest. Detalhe em
  [[2026-09-01-C — Interface de busca e empréstimo (LWC)]].
- **2026-09-01** — `RefreshEvent` não recarregou as list views padrão na Home
  page. Trocado por LWCs de lista próprios `libraryBookList` / `libraryLoanList`
  (`LibraryListController` `cacheable` + `refreshApex`) avisados pelo message
  channel `LibraryRefresh__c` (LMS) que o `libraryBookSearch` publica no
  `loancreated`. Detalhe em
  [[2026-09-01-C — Interface de busca e empréstimo (LWC)]].
- **2026-09-01 — Deploy OK e validado no org.** Todo o pacote deployado com
  sucesso: `NoAvailableCopiesException`, trigger `LibraryBookLoanTrigger` +
  handler, `LibraryService`, `LibraryListController`, message channel
  `LibraryRefresh__c`, LWCs `libraryBookSearch` / `libraryLoanButton` /
  `libraryBookList` / `libraryLoanList`. Home page do app DigiLibrary montada
  com o search + as duas listas; ao solicitar empréstimo o toast aparece e as
  duas listas recarregam. **Pendente:** todos os testes (Apex ≥ 85% + Jest) e
  versionar os objetos/campos custom em `force-app/main/default/objects/`.

- **2026-09-01** — `libraryLoanList` ganhou ação "Excluir" por linha
  (`deleteRecord` + `LightningConfirm`): o trigger `after delete` devolve a
  cópia (+1) e o canal `LibraryRefresh__c` recarrega as demais listas. O
  `libraryBookSearch` passou a também `subscribe` no canal. Detalhe em
  [[2026-09-01-C — Interface de busca e empréstimo (LWC)]].

- **2026-09-02** — **Interface toda em inglês** (requisito do cliente):
  traduzidos os 4 LWCs (labels, botões, textos auxiliares, colunas de
  datatable, toasts) e as mensagens Apex que aparecem em toast/banner
  (`LibraryService`, `LibraryBookLoanTriggerHandler`). Sem mudança de lógica.
  Detalhe em [[2026-09-01-C — Interface de busca e empréstimo (LWC)]].
- **2026-09-02** — **Testes Apex** criados e executados no org:
  `LibraryServiceTest`, `LibraryBookLoanTriggerTest`, `LibraryListControllerTest`,
  `NoAvailableCopiesExceptionTest` + factory `LibraryTestDataFactory` (`@IsTest`).
  **23/23 passam. Cobertura org-wide 99%**:
  `LibraryBookLoanTrigger` 100%, `LibraryBookLoanTriggerHandler` 100%,
  `LibraryListController` 100%, `LibraryService` 98% (1 linha: o ramo
  `: e.getMessage()` do ternário no `catch (DmlException)` — `DmlException`
  com 0 linhas é impraticável de simular). `NoAvailableCopiesException` não
  tem linhas executáveis (corpo vazio).
- **2026-09-02 — Descoberta:** `Library_Book__c.Title__c` é **fórmula**
  (`<formula>Name</formula>`) — `createable/updateable = false`. O título é
  gravado via `Name`; SOQL/SOSL leem `Title__c` normalmente. Ajustada a
  factory de teste. Objetos custom retrieved para
  `force-app/main/default/objects/` (repo agora completo).
- **2026-09-02 — Extra Challenge (API externa) implementado.** Named Credential
  `Open_Library` (anônima) + `OpenLibraryService` (callout resiliente) +
  `searchBooks` unificado (local SOSL + Open Library, dedupe por título) +
  `importBook` + LWC `libraryBookSearch` com botão "Register / Import".
  38 testes Apex, `OpenLibraryService` 100%, `LibraryService` 99%. Detalhe em
  [[2026-09-02-D — Integração Open Library (API externa)]].
- **2026-09-02 — Ajustes de UX/bug pós-integração:**
  - `libraryBookSearch` ganhou **botão "Search"** (debounce removido) — como a
    busca agora faz callout à Open Library, disparar a cada tecla geraria 1
    callout por letra;
  - **bug intermitente** "livro importado reaparece como externo": o índice
    do **SOSL não é síncrono**, então o `searchBooks` logo após o `importBook`
    não via o registro novo. Corrigido com **backfill SOQL**
    (`WHERE Name IN :títulosExternos`) + update otimista no LWC;
  - padding lateral dos `<lightning-datatable>` nas listas irmãs.
  - Tudo em [[2026-09-02-D — Integração Open Library (API externa)]] e
    [[2026-09-01-C — Interface de busca e empréstimo (LWC)]].

- **2026-09-02 — Testes Jest** dos 4 LWCs criados e passando (29 testes, 4
  suites, cobertura de linhas ~94%). `jest.config.js` ajustado
  (`collectCoverageFrom`). Runner exige Node ≥ 20 (sfdx-lwc-jest 7) — usado
  Node 24 via nvm. Detalhe e notas de montagem em
  [[2026-09-01-C — Interface de busca e empréstimo (LWC)]].

### Estado atual (2026-09-01, atualizado 2026-09-02)

| Entregável | Status |
|---|---|
| `NoAvailableCopiesException` | ✅ (0 linhas executáveis) |
| Trigger + handler (`addError`, bulk, `FOR UPDATE`) | ✅ código / ✅ teste 100% |
| `LibraryService` (`searchBooks` unificado, `importBook`, `loanBook`, `requestLoan`) | ✅ código / ✅ teste 99% |
| `LibraryListController` (`getBooks`, `getRecentLoans`) | ✅ código / ✅ teste 100% |
| LWC busca (botão "Search", callout sob demanda) + botão + toast | ✅ |
| LWCs de lista + `LibraryRefresh__c` (LMS) | ✅ |
| Excluir empréstimo no `libraryLoanList` (+1 cópia via trigger) | ✅ |
| Interface + mensagens Apex em inglês (requisito do cliente) | ✅ 2026-09-02 |
| **Extra Challenge** — Open Library (`OpenLibraryService`, Named Credential, import) | ✅ 2026-09-02 — teste 100% |
| Deploy no org | ✅ 2026-09-02 |
| Testes unitários Apex (≥ 90%) | ✅ 2026-09-02 — 38 testes, org-wide 99% |
| Testes Jest dos LWCs | ✅ 2026-09-02 — 29 testes, linhas ~94% |
| Objetos/campos custom versionados no repo | ✅ 2026-09-02 (retrieve) |

## Obstáculos & solução

- **2026-09-01** — Subtarefas de objetos (`Library_Book__c`,
  `Library_Book_Loan__c`) marcadas como concluídas. O deploy de 2026-09-01
  passou, então os objetos/campos **existem no org**; falta confirmar se estão
  versionados em `force-app/main/default/objects/` (podem ter sido criados só
  na UI). Se não estiverem, exportar com `sf project retrieve`.
- **2026-09-01** — Erro de empréstimo aparecia como painel "We hit a snag"
  com stack na tela padrão; pedido de toast. **Solução:** `addError` no
  trigger (UI padrão) + caminho LWC `requestLoan`/`AuraHandledException` +
  `ShowToastEvent` (Lightning). Toast não é disparável por trigger nem pela
  página padrão de criação de registro.
- **2026-09-01 — Deploy falhou:** `Unable to retrieve metadata for
  descriptor: markup://c:__LightningMessageChannel__LibraryRefresh__c`. O
  `manifest/package.xml` não listava o tipo `LightningMessageChannel`, então o
  canal não ia no deploy e os LWCs que o importam não compilavam.
  **Solução:** adicionado `<name>LightningMessageChannel</name>` ao manifest e
  deployado o canal primeiro (`-d force-app/main/default/messageChannels`),
  depois o resto. O canal precisa existir no org antes dos LWCs que o
  referenciam.

## 🧠 Para o acervo
- [[Apex · Trigger bulkificada que mantém contador no registro pai]] (já
  extraído — inclui `throw` vs `addError`).
- Candidato: tratamento de erro Apex→LWC (`AuraHandledException` +
  `setMessage`, separação método de domínio × `@AuraEnabled`, toast sticky +
  normalização de `error.body`) — ver "Para o acervo" das subtarefas B e C.
