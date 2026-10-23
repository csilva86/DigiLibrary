import { createElement } from "lwc";
import LibraryBookList from "c/libraryBookList";
import getBooks from "@salesforce/apex/LibraryListController.getBooks";
import { refreshApex } from "@salesforce/apex";
import { subscribe, unsubscribe } from "lightning/messageService";

jest.mock(
  "@salesforce/apex/LibraryListController.getBooks",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

jest.mock(
  "@salesforce/messageChannel/LibraryRefresh__c",
  () => ({ default: "LibraryRefresh__c" }),
  { virtual: true }
);

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("c-library-book-list", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function createComponent() {
    const element = createElement("c-library-book-list", {
      is: LibraryBookList
    });
    document.body.appendChild(element);
    return element;
  }

  it("subscribes to LibraryRefresh on connect and unsubscribes on disconnect", () => {
    const element = createComponent();
    expect(subscribe).toHaveBeenCalledTimes(1);
    expect(subscribe.mock.calls[0][1]).toBe("LibraryRefresh__c");

    document.body.removeChild(element);
    expect(unsubscribe).toHaveBeenCalled();
  });

  it("renders the datatable with the wired books", async () => {
    const element = createComponent();
    getBooks.emit([
      {
        Id: "b1",
        Title__c: "A",
        Author__c: "X",
        Available_Copies__c: 2,
        Total_Copies__c: 3
      }
    ]);
    await flushPromises();

    const datatable = element.shadowRoot.querySelector("lightning-datatable");
    expect(datatable).not.toBeNull();
    expect(datatable.data.length).toBe(1);
    expect(element.shadowRoot.textContent).not.toContain("No books registered");
  });

  it("shows the empty state for an empty result", async () => {
    const element = createComponent();
    getBooks.emit([]);
    await flushPromises();

    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
    expect(element.shadowRoot.textContent).toContain("No books registered");
  });

  it("shows an error message when the wire fails", async () => {
    const element = createComponent();
    getBooks.error({ message: "boom" });
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("boom");
  });

  it("calls refreshApex when a LibraryRefresh message arrives", () => {
    createComponent();
    const listener = subscribe.mock.calls[0][2];
    listener({ source: "somewhere" });
    expect(refreshApex).toHaveBeenCalled();
  });
});
