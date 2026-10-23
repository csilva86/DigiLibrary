---
type: conhecimento
dominio: salesforce
area: Data-SOQL
conceito: Busca textual multi-campo (título ou autor) com SOSL
maturidade: semente
fontes: ["[[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]]"]
tags: [conhecimento, soql]
---
# Data-SOQL · Busca textual por título ou autor com SOSL

## Ideia central

Para "buscar por X **ou** Y" em campos de texto, use **SOSL**, não SOQL:

```apex
List<List<SObject>> results = [
    FIND :searchKey IN ALL FIELDS
    RETURNING Library_Book__c(
        Id, Name, Title__c, Author__c, Available_Copies__c, Total_Copies__c
        ORDER BY Title__c
        LIMIT :MAX_RESULTS
    )
];
return (List<Library_Book__c>) results[0];
```

O índice de texto do SOSL já faz OR entre os campos e **tokeniza por palavra**
(`FIND 'Tom'` acha "The Adventures of **Tom** Sawyer" sem `LIKE %...%`). SOQL
faria `WHERE Title__c LIKE :x OR Author__c LIKE :x` — `LIKE` com curinga à
esquerda é não seletivo (full scan).

## Quando aplicar

- Caixa de busca livre sobre 1+ campos de texto (título, autor, assunto...).
- Precisa varrer vários objetos numa tacada (`RETURNING A(...), B(...)`).
- **Não** usar SOSL para filtro exato / navegação por chave — aí é SOQL.

## Exemplo (completo, pronto p/ LWC)

```apex
@AuraEnabled(cacheable=true)
public static List<Library_Book__c> searchBooks(String searchTerm) {
    if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
        return new List<Library_Book__c>();          // SOSL exige >= 2 chars
    }
    String searchKey = sanitizeSoslTerm(searchTerm) + '*';   // prefixo

    List<List<SObject>> results = [
        FIND :searchKey IN ALL FIELDS
        RETURNING Library_Book__c(
            Id, Name, Title__c, Author__c, Available_Copies__c, Total_Copies__c
            ORDER BY Title__c LIMIT :MAX_RESULTS
        )
    ];
    return (List<Library_Book__c>) results[0];
}

// escapa os caracteres que o SOSL trata como operador (\ primeiro!)
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

Teste (SOSL não retorna dados reais em teste sem isso):

```apex
@IsTest
static void searchBooks_encontraPorAutor() {
    Library_Book__c b = new Library_Book__c(Title__c = 'Tom Sawyer', Author__c = 'Mark Twain',
        Available_Copies__c = 2, Total_Copies__c = 2);
    insert b;
    Test.setFixedSearchResults(new List<Id>{ b.Id });   // <- obrigatório

    Test.startTest();
    List<Library_Book__c> found = LibraryService.searchBooks('Twain');
    Test.stopTest();

    System.assertEquals(1, found.size());
}
```

## Armadilhas

- **`FIND` não aceita lista de campos** — só `IN ALL / NAME / EMAIL / PHONE /
  SIDEBAR FIELDS`. "Título ou autor" vira `IN ALL FIELDS` quando esses são os
  únicos campos de texto do objeto; senão, filtre no `RETURNING ... WHERE`.
- **Injeção e `SearchException`**: use bind `:searchKey` (cobre injeção) **e**
  escape os caracteres reservados (`? & | ! * : - " ' + ( ) { } [ ] ^ ~ \`).
  Escape `\` primeiro para não duplicar.
- **Curinga só no fim** (`term + '*'`): prefixo é indexado. `*term` (à
  esquerda) força varredura e é bloqueado em vários contextos.
- **Mínimo 2 caracteres** (fora curingas) — abaixo disso o SOSL nem roda;
  faça o guard e retorne lista vazia.
- **Testes**: sem `Test.setFixedSearchResults(ids)` todo SOSL retorna vazio no
  contexto de teste, independentemente dos dados inseridos.
- **`cacheable=true`**: ótimo para busca (habilita `@wire` e cache do LDS),
  mas o método não pode ter efeito colateral nem DML.
- SOSL conta 1 nos limites de `SOQL queries` (20 sync) e devolve no máximo
  2.000 linhas — sempre `LIMIT` + `ORDER BY` para a UI.

## Relacionadas

- [[MOC · Data-SOQL]]
- [[2026-09-01-B — Classe LibraryService (SOSL + loanBook)]] — origem
- [[Apex · Erro de Apex que chega ao LWC com AuraHandledException]] — mesma
  classe, tratamento de erro do `loanBook`
