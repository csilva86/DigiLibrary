/**
 * Unit tests for OpenLibraryService.search - happy path, HTTP error, callout
 * exception and malformed payloads. All must degrade to an empty list.
 */
@IsTest
private class OpenLibraryServiceTest {
    private static List<Map<String, Object>> sampleDocs() {
        return new List<Map<String, Object>>{
            new Map<String, Object>{
                'title' => 'The Adventures of Tom Sawyer',
                'author_name' => new List<String>{ 'Mark Twain', 'Other' }
            },
            new Map<String, Object>{ 'title' => 'Untitled Notebook' } // no author
        };
    }

    @IsTest
    static void search_returnsMappedBooks() {
        Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.ok(sampleDocs()));

        Test.startTest();
        List<OpenLibraryService.ExternalBook> books = OpenLibraryService.search('twain');
        Test.stopTest();

        Assert.areEqual(2, books.size());
        Assert.areEqual('The Adventures of Tom Sawyer', books[0].title);
        Assert.areEqual('Mark Twain', books[0].author, 'first author_name is used');
        Assert.isNull(books[1].author, 'missing author_name maps to null');
    }

    @IsTest
    static void search_blankTerm_returnsEmptyWithoutCallout() {
        Test.startTest();
        Assert.areEqual(0, OpenLibraryService.search(null).size());
        Assert.areEqual(0, OpenLibraryService.search('  ').size());
        Test.stopTest();
    }

    @IsTest
    static void search_httpError_returnsEmpty() {
        Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.status(503));

        Test.startTest();
        List<OpenLibraryService.ExternalBook> books = OpenLibraryService.search('anything');
        Test.stopTest();

        Assert.areEqual(0, books.size());
    }

    @IsTest
    static void search_calloutException_returnsEmpty() {
        Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.failing());

        Test.startTest();
        List<OpenLibraryService.ExternalBook> books = OpenLibraryService.search('anything');
        Test.stopTest();

        Assert.areEqual(0, books.size());
    }

    @IsTest
    static void search_malformedJson_returnsEmpty() {
        Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.rawBody('<<not json>>'));

        Test.startTest();
        List<OpenLibraryService.ExternalBook> books = OpenLibraryService.search('anything');
        Test.stopTest();

        Assert.areEqual(0, books.size());
    }

    @IsTest
    static void search_jsonWithoutDocs_returnsEmpty() {
        Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.rawBody('{"numFound":0}'));

        Test.startTest();
        List<OpenLibraryService.ExternalBook> books = OpenLibraryService.search('anything');
        Test.stopTest();

        Assert.areEqual(0, books.size());
    }

    @IsTest
    static void search_nonObjectJson_returnsEmpty() {
        Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.rawBody('[1, 2, 3]'));

        Test.startTest();
        List<OpenLibraryService.ExternalBook> books = OpenLibraryService.search('anything');
        Test.stopTest();

        Assert.areEqual(0, books.size());
    }

    @IsTest
    static void search_docEntryNotObject_isSkipped() {
        Test.setMock(
            HttpCalloutMock.class,
            OpenLibraryCalloutMock.rawBody('{"docs":["just a string",{"title":"Real Book"}]}')
        );

        Test.startTest();
        List<OpenLibraryService.ExternalBook> books = OpenLibraryService.search('anything');
        Test.stopTest();

        Assert.areEqual(1, books.size());
        Assert.areEqual('Real Book', books[0].title);
    }

    @IsTest
    static void search_docWithBlankTitle_isSkipped() {
        Test.setMock(
            HttpCalloutMock.class,
            OpenLibraryCalloutMock.ok(
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'title' => '' },
                    new Map<String, Object>{ 'title' => 'Real Book' }
                }
            )
        );

        Test.startTest();
        List<OpenLibraryService.ExternalBook> books = OpenLibraryService.search('anything');
        Test.stopTest();

        Assert.areEqual(1, books.size());
        Assert.areEqual('Real Book', books[0].title);
    }
}
