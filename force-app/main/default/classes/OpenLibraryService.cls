/**
 * Thin client for the Open Library Search API
 * (https://openlibrary.org/search.json?q={term}).
 *
 * The HTTP endpoint is reached through the "Open Library" Named Credential
 * (callout:Open_Library) so the URL and any future auth stay out of the code.
 *
 * search() never throws: a remote outage, a non-200 response or an unparseable
 * body simply yield an empty list, so LibraryService.searchBooks degrades to
 * "local results only" instead of failing.
 */
public with sharing class OpenLibraryService {
    @TestVisible
    private static final Integer MAX_RESULTS = 10;

    @TestVisible
    private static final Integer TIMEOUT_MS = 10000;

    /** Lightweight projection of one Open Library "doc". */
    public class ExternalBook {
        public String title;
        public String author;

        public ExternalBook(String title, String author) {
            this.title = title;
            this.author = author;
        }
    }

    /**
     * @param term free-text query (title or author)
     * @return up to MAX_RESULTS external books, or an empty list on any failure
     */
    public static List<ExternalBook> search(String term) {
        List<ExternalBook> books = new List<ExternalBook>();
        if (String.isBlank(term)) {
            return books;
        }

        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            request.setTimeout(TIMEOUT_MS);
            request.setEndpoint(
                'callout:Open_Library/search.json' +
                '?limit=' + MAX_RESULTS +
                '&fields=title,author_name' +
                '&q=' + EncodingUtil.urlEncode(term, 'UTF-8')
            );

            HttpResponse response = new Http().send(request);

            if (response.getStatusCode() != 200) {
                System.debug(
                    LoggingLevel.WARN,
                    'Open Library returned HTTP ' + response.getStatusCode()
                );
                return books;
            }

            books = parseDocs(response.getBody());
        } catch (CalloutException e) {
            // DNS / timeout / Named Credential misconfig -> no external suggestions
            System.debug(LoggingLevel.WARN, 'Open Library callout failed: ' + e.getMessage());
        } catch (Exception e) {
            // JSON shape changed, cast failure, etc.
            System.debug(LoggingLevel.WARN, 'Open Library response unreadable: ' + e.getMessage());
        }

        return books;
    }

    private static List<ExternalBook> parseDocs(String body) {
        List<ExternalBook> books = new List<ExternalBook>();

        Object parsed = JSON.deserializeUntyped(body);
        if (!(parsed instanceof Map<String, Object>)) {
            return books;
        }

        Object rawDocs = ((Map<String, Object>) parsed).get('docs');
        if (!(rawDocs instanceof List<Object>)) {
            return books;
        }

        for (Object item : (List<Object>) rawDocs) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> doc = (Map<String, Object>) item;
            String title = (String) doc.get('title');
            if (String.isBlank(title)) {
                continue;
            }
            books.add(new ExternalBook(title, firstAuthor(doc.get('author_name'))));
        }

        return books;
    }

    private static String firstAuthor(Object rawAuthors) {
        if (rawAuthors instanceof List<Object>) {
            List<Object> authors = (List<Object>) rawAuthors;
            if (!authors.isEmpty()) {
                return String.valueOf(authors[0]);
            }
        }
        return null;
    }
}
