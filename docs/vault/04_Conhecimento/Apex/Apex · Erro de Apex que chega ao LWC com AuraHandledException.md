---
type: conhecimento
dominio: salesforce
area: Apex
conceito: Fazer a mensagem de erro do Apex chegar ao LWC com AuraHandledException
maturidade: semente
fontes: ["[[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]]"]
tags: [conhecimento, apex]
---
# Apex · Erro de Apex que chega ao LWC com AuraHandledException

## Ideia central

Um método `@AuraEnabled` só entrega ao JS a mensagem de uma
**`AuraHandledException`**. Qualquer outra exceção (customizada, `DmlException`,
`NullPointerException`...) chega ao `catch` do LWC como
`error.body.message === 'Script-thrown exception'` / *"An internal server error
has occurred"* — a mensagem real fica só no debug log.

Padrão: **duas camadas**.

1. **Método de domínio** (`loanBook`) — Apex puro, lança a exceção **tipada**
   (`NoAvailableCopiesException`). Serve a outros Apex e aos testes, que
   conseguem `catch` do tipo específico.
2. **Método `@AuraEnabled`** (`requestLoan`) — fino, chama o de domínio dentro
   de `try/catch` e **relança como `AuraHandledException`** com uma mensagem
   amigável. É o que o LWC chama.

## Quando aplicar

- Sempre que um LWC precisa **mostrar ao usuário** o motivo da falha (toast,
  inline error) e não só um "algo deu errado".
- Regras de negócio que já lançam exceção tipada e você não quer perder esse
  tipo para o resto do Apex.
- Vale também para Aura (`e.getMessage()` no `$A.getCallback`).

## Exemplo

```apex
// camada de domínio: lança o tipo específico
public static Id loanBook(Id bookId, Id borrowerId) {
    ...
    if (available <= 0) {
        throw new NoAvailableCopiesException(
            'The book "' + book.Name + '" has no available copies right now.'
        );
    }
    ...
}

// camada da UI: adapta para AuraHandledException
@AuraEnabled
public static Id requestLoan(Id bookId, Id borrowerId) {
    try {
        return loanBook(bookId, borrowerId);
    } catch (NoAvailableCopiesException e) {
        throw toAuraException(e.getMessage());
    } catch (DmlException e) {
        throw toAuraException(e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage());
    } catch (Exception e) {
        throw toAuraException(e.getMessage());
    }
}

private static AuraHandledException toAuraException(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);   // ver Armadilhas
    return ex;
}
```

No LWC:

```js
try {
    await requestLoan({ bookId, borrowerId });
} catch (error) {
    // error.body.message agora traz o texto que veio do toAuraException
    this.dispatchEvent(new ShowToastEvent({
        title: 'Could not register the loan',
        message: error?.body?.message ?? 'Unexpected error.',
        variant: 'error'
    }));
}
```

## Armadilhas

- **`new AuraHandledException(msg)` só no construtor** já preenche
  `error.body.message` na maioria das versões, mas houve releases em que
  ficava vazio/`"Script-thrown exception"`. Chamar **`setMessage(msg)` além do
  construtor** fecha a lacuna, custo zero.
- **Deixar a exceção customizada vazar** do método `@AuraEnabled` → usuário vê
  erro genérico. É o erro mais comum.
- **`e.getMessage()` de `DmlException`** costuma vir com ruído
  (`FIELD_CUSTOM_VALIDATION_EXCEPTION, ...`). Preferir `e.getDmlMessage(0)`.
- **Só logar e não relançar**: o LWC acha que deu certo. Sempre relançar.
- **Testes**: um teste que espera `NoAvailableCopiesException` deve chamar o
  **método de domínio** (`loanBook`); ao testar `requestLoan` o `catch` é de
  `AuraHandledException` e, historicamente, `getMessage()` dela em teste
  retorna `"Script-thrown exception"` — asserte via `Test.stopTest()` +
  captura, ou valide só que lançou.

## Relacionadas

- [[MOC · Apex]]
- [[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]] — origem
- [[2026-09-01-C — Interface de busca e empréstimo (LWC)]] — lado do LWC
  (`getErrorMessage` normalizando `error.body`)
- [[2026-09-01-A — Trigger de empréstimo (Library_Book_Loan__c)]] — no caminho
  da UI padrão o equivalente é `addError`, não exceção
