---
type: conhecimento
dominio: salesforce
area: Integracoes
conceito: Callout GET a uma API pública que degrada em vez de quebrar o fluxo
maturidade: semente
fontes: ["[[2026-09-02-D — Integração Open Library (API externa)]]"]
tags: [conhecimento, integracao]
---
# Integrações · Callout resiliente para API pública com Named Credential

## Ideia central

Quando um recurso externo **enriquece** um fluxo (não é a fonte de verdade), o
callout tem que **falhar em silêncio**: erro de rede, HTTP != 200 ou JSON
inesperado → devolve resultado vazio, não exceção. O fluxo principal (busca
local, gravação...) segue funcionando.

Quatro peças:

1. **Named Credential** para o endpoint — URL e auth fora do código, sem
   Remote Site Setting. Para API pública sem auth: Named Credential *legacy*
   `principalType = Anonymous` + `protocol = NoAuthentication`.
2. **`try-catch` em camadas**: `catch (CalloutException)` (DNS, timeout, named
   cred quebrada) e `catch (Exception)` (cast/JSON) — ambos logam `WARN` e
   retornam a coleção vazia.
3. **Parse defensivo**: `JSON.deserializeUntyped` + `instanceof Map<String,Object>`
   / `instanceof List<Object>` **antes de cada cast**; pula item inválido.
4. **`HttpCalloutMock` reutilizável** (`@IsTest`) com factories para cada
   cenário (ok / status N / corpo cru / lança).

## Quando aplicar

- Buscar sugestões/metadados de um catálogo externo (livros, CEP, empresa por
  CNPJ, geocoding...).
- Qualquer callout cujo resultado é "nice to have" — se a API cair, a tela
  ainda tem que abrir.
- **Não** aplicar quando a resposta é obrigatória para a regra de negócio; aí
  a exceção tem que subir.

## Exemplo

```apex
public with sharing class OpenLibraryService {
    public class ExternalBook {
        public String title; public String author;
        public ExternalBook(String t, String a) { title = t; author = a; }
    }

    public static List<ExternalBook> search(String term) {
        List<ExternalBook> books = new List<ExternalBook>();
        if (String.isBlank(term)) { return books; }
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setTimeout(10000);
            req.setEndpoint('callout:Open_Library/search.json?limit=10&fields=title,author_name&q='
                + EncodingUtil.urlEncode(term, 'UTF-8'));
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                System.debug(LoggingLevel.WARN, 'HTTP ' + res.getStatusCode());
                return books;                                   // degrada
            }
            books = parse(res.getBody());
        } catch (CalloutException e) {
            System.debug(LoggingLevel.WARN, 'callout failed: ' + e.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'unreadable response: ' + e.getMessage());
        }
        return books;
    }

    private static List<ExternalBook> parse(String body) {
        List<ExternalBook> out = new List<ExternalBook>();
        Object parsed = JSON.deserializeUntyped(body);
        if (!(parsed instanceof Map<String, Object>)) { return out; }
        Object rawDocs = ((Map<String, Object>) parsed).get('docs');
        if (!(rawDocs instanceof List<Object>)) { return out; }
        for (Object item : (List<Object>) rawDocs) {
            if (!(item instanceof Map<String, Object>)) { continue; }
            Map<String, Object> doc = (Map<String, Object>) item;
            String title = (String) doc.get('title');
            if (String.isBlank(title)) { continue; }
            out.add(new ExternalBook(title, firstAuthor(doc.get('author_name'))));
        }
        return out;
    }
}
```

Named Credential (`namedCredentials/Open_Library.namedCredential-meta.xml`):

```xml
<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Open Library</label>
    <endpoint>https://openlibrary.org</endpoint>
    <generateAuthorizationHeader>false</generateAuthorizationHeader>
    <principalType>Anonymous</principalType>
    <protocol>NoAuthentication</protocol>
</NamedCredential>
```

Mock de teste:

```apex
@IsTest
public class OpenLibraryCalloutMock implements HttpCalloutMock {
    private Integer statusCode = 200;
    private String body = '{"docs":[]}';
    private Boolean throwCallout = false;

    public static OpenLibraryCalloutMock ok(List<Map<String,Object>> docs) {
        OpenLibraryCalloutMock m = new OpenLibraryCalloutMock();
        m.body = JSON.serialize(new Map<String,Object>{ 'docs' => docs });
        return m;
    }
    public static OpenLibraryCalloutMock status(Integer c) { OpenLibraryCalloutMock m = new OpenLibraryCalloutMock(); m.statusCode = c; return m; }
    public static OpenLibraryCalloutMock rawBody(String b) { OpenLibraryCalloutMock m = new OpenLibraryCalloutMock(); m.body = b; return m; }
    public static OpenLibraryCalloutMock failing() { OpenLibraryCalloutMock m = new OpenLibraryCalloutMock(); m.throwCallout = true; return m; }

    public HttpResponse respond(HttpRequest req) {
        if (throwCallout) { throw new CalloutException('simulated'); }
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(body);
        return res;
    }
}
```

Testar todos os ramos: `ok(docs)`, `status(503)`, `failing()` (→
`CalloutException`), `rawBody('<<not json>>')` (→ parse catch),
`rawBody('{"numFound":0}')` (sem `docs`), `rawBody('[1,2,3]')` (JSON que não é
objeto). Cada um deve devolver lista vazia (menos o `ok`).

## Armadilhas

- **`@AuraEnabled(cacheable=true)` + callout são incompatíveis** — método
  cacheable não pode fazer callout nem DML. Se o LWC precisa do dado, a
  chamada vira **imperativa** (`await apexMethod({...})`), sem `@wire`, e o
  refresh passa a ser re-`await` no lugar de `refreshApex`.
- **Sem parse defensivo**, um `(Map<String,Object>) parsed` ou
  `(String) doc.get('x')` num payload diferente lança `TypeException` e, se
  não houver `catch (Exception)`, quebra tudo. Cheque `instanceof` antes.
- **`setTimeout`** — sem ele o callout usa 120 s; numa tela isso trava o
  usuário. 10 s é um bom teto.
- **Named Credential legacy vs. novo modelo**: para API pública anônima, o
  legacy (`Anonymous` / `NoAuthentication`) deploya limpo e é o mais simples.
  O modelo novo (External Credential + Named Credential + perm set) só compensa
  quando há auth real.
- **`EncodingUtil.urlEncode(term, 'UTF-8')`** no query string — sem isso,
  espaço/acento no termo geram URL inválida.
- **Não confundir "degrada" com "engole erro de negócio"**: só o callout
  auxiliar degrada. Uma falha na gravação local ou numa regra continua sendo
  exceção que sobe.
- Callout conta 1 nos limites (100 síncronos / transação) e não pode vir
  **depois de DML não commitada** ("uncommitted work pending").

## Relacionadas

- [[MOC · Integracoes]]
- [[2026-09-02-D — Integração Open Library (API externa)]] — origem
- [[Apex · Erro de Apex que chega ao LWC com AuraHandledException]] — o
  `importBook` que persiste o resultado usa esse padrão de erro
- [[Data-SOQL · Busca textual por título ou autor com SOSL]] — o merge
  local+externo depende de SOSL (e de um backfill SOQL pela latência do índice)
