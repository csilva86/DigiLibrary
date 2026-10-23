/**
 * Reusable HttpCalloutMock for the Open Library integration tests.
 *
 *   Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.ok(docs));
 *   Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.status(500));
 *   Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.failing());
 *   Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.rawBody('not-json'));
 */
@IsTest
public class OpenLibraryCalloutMock implements HttpCalloutMock {
    private Integer statusCode = 200;
    private String body = '{"docs":[]}';
    private Boolean throwCallout = false;

    public static OpenLibraryCalloutMock ok(List<Map<String, Object>> docs) {
        OpenLibraryCalloutMock mock = new OpenLibraryCalloutMock();
        mock.body = JSON.serialize(new Map<String, Object>{ 'docs' => docs });
        return mock;
    }

    public static OpenLibraryCalloutMock status(Integer code) {
        OpenLibraryCalloutMock mock = new OpenLibraryCalloutMock();
        mock.statusCode = code;
        return mock;
    }

    public static OpenLibraryCalloutMock rawBody(String rawBody) {
        OpenLibraryCalloutMock mock = new OpenLibraryCalloutMock();
        mock.body = rawBody;
        return mock;
    }

    public static OpenLibraryCalloutMock failing() {
        OpenLibraryCalloutMock mock = new OpenLibraryCalloutMock();
        mock.throwCallout = true;
        return mock;
    }

    public HttpResponse respond(HttpRequest request) {
        if (throwCallout) {
            throw new CalloutException('Simulated Open Library connection failure');
        }
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setHeader('Content-Type', 'application/json');
        response.setBody(body);
        return response;
    }
}
