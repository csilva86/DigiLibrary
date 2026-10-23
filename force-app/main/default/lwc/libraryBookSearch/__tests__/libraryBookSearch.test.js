import { createElement } from "lwc";
import LibraryBookSearch from "c/libraryBookSearch";
import searchBooks from "@salesforce/apex/LibraryService.searchBooks";
import importBook from "@salesforce/apex/LibraryService.importBook";
import { publish, subscribe } from "lightning/messageService";

jest.mock(
  "@salesforce/apex/LibraryService.searchBooks",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryService.importBook",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
// libraryBookSearch renders c-library-loan-button, which imports requestLoan.
jest.mock(
  "@salesforce/apex/LibraryService.requestLoan",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/messageChannel/LibraryRefresh__c",
  () => ({ default: "LibraryRefresh__c" }),
  { virtual: true }
);

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function localRow(overrides = {}) {
  return {
    bookId: "bk1",
    title: "Dune",
    author: "Herbert",
    availableCopies: 2,
    totalCopies: 3,
    existsLocally: true,
    source: "LOCAL",
    ...overrides
  };
}
function externalRow(overrides = {}) {
  return {
    bookId: null,
    title: "Remote Book",
    author: "Remote Author",
    availableCopies: null,
    totalCopies: null,
    existsLocally: false,
    source: "EXTERNAL",
    ...overrides
  };
}

describe("c-library-book-search", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function createComponent() {
    const element = createElement("c-library-book-search", {
      is: LibraryBookSearch
    });
    document.body.appendChild(element);
    return element;
  }

  function typeTerm(element, value) {
    element.shadowRoot
      .querySelector("lightning-input")
      .dispatchEvent(new CustomEvent("change", { detail: { value } }));
  }

  function searchButton(element) {
    return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
      (b) => b.label === "Search"
    );
  }

  function importButton(element) {
    return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
      (b) => b.label === "Register / Import"
    );
  }

  it("renders a disabled Search button and runs no search before input", async () => {
    const element = createComponent();
    await flushPromises();

    const button = searchButton(element);
    expect(button).toBeTruthy();
    expect(button.disabled).toBe(true);
    expect(element.shadowRoot.querySelectorAll("li").length).toBe(0);
    expect(searchBooks).not.toHaveBeenCalled();
  });

  it("enables Search only from two characters and never auto-searches", async () => {
    const element = createComponent();
    await flushPromises();

    typeTerm(element, "a");
    await flushPromises();
    expect(searchButton(element).disabled).toBe(true);

    typeTerm(element, "dune");
    await flushPromises();
    expect(searchButton(element).disabled).toBe(false);
    expect(searchBooks).not.toHaveBeenCalled();
  });

  it("runs the search when the button is pressed and renders both row types", async () => {
    searchBooks.mockResolvedValue([localRow(), externalRow()]);
    const element = createComponent();
    await flushPromises();

    typeTerm(element, "twain");
    await flushPromises();
    searchButton(element).dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(searchBooks).toHaveBeenCalledWith({ searchTerm: "twain" });
    expect(element.shadowRoot.querySelectorAll("li").length).toBe(2);
    expect(
      element.shadowRoot.querySelector("c-library-loan-button")
    ).not.toBeNull();
    expect(importButton(element)).toBeTruthy();
  });

  it("searches on Enter in the field", async () => {
    searchBooks.mockResolvedValue([localRow()]);
    const element = createComponent();
    await flushPromises();

    typeTerm(element, "twain");
    await flushPromises();
    element.shadowRoot
      .querySelector("lightning-input")
      .dispatchEvent(new KeyboardEvent("keyup", { key: "Enter" }));
    await flushPromises();

    expect(searchBooks).toHaveBeenCalledWith({ searchTerm: "twain" });
  });

  it("shows an error when the search fails", async () => {
    searchBooks.mockRejectedValue({ body: { message: "API down" } });
    const element = createComponent();
    await flushPromises();

    typeTerm(element, "twain");
    await flushPromises();
    searchButton(element).dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("API down");
  });

  it("imports an external book, toasts and re-runs the search", async () => {
    searchBooks
      .mockResolvedValueOnce([
        externalRow({ title: "New Title", author: "New Author" })
      ])
      .mockResolvedValueOnce([localRow({ title: "New Title", bookId: "bk9" })]);
    importBook.mockResolvedValue("bk9");

    const element = createComponent();
    await flushPromises();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    typeTerm(element, "new");
    await flushPromises();
    searchButton(element).dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    importButton(element).dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(importBook).toHaveBeenCalledWith({
      title: "New Title",
      author: "New Author"
    });
    expect(toastHandler.mock.calls[0][0].detail.title).toBe("Book imported");
    expect(searchBooks).toHaveBeenCalledTimes(2);
    expect(publish).toHaveBeenCalled();
  });

  it("captures the borrower from the picker and feeds it to the loan button", async () => {
    searchBooks.mockResolvedValue([localRow()]);
    const element = createComponent();
    await flushPromises();

    element.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "003abc" } })
      );
    typeTerm(element, "dune");
    await flushPromises();
    searchButton(element).dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(
      element.shadowRoot.querySelector("c-library-loan-button").borrowerId
    ).toBe("003abc");
  });

  it("treats a channel refresh before any search as a no-op", async () => {
    const element = createComponent();
    await flushPromises();

    const listener = subscribe.mock.calls[0][2];
    listener({ source: "elsewhere" });
    await flushPromises();

    expect(searchBooks).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelectorAll("li").length).toBe(0);
  });

  it("re-enables the import button and toasts on import failure", async () => {
    searchBooks.mockResolvedValue([
      externalRow({ title: "Dup Book", author: "Someone" })
    ]);
    importBook.mockRejectedValue({ body: { message: "already exists" } });

    const element = createComponent();
    await flushPromises();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    typeTerm(element, "dup");
    await flushPromises();
    searchButton(element).dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    importButton(element).dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("error");
    expect(toastHandler.mock.calls[0][0].detail.message).toBe("already exists");
    expect(importButton(element).disabled).toBe(false);
  });

  it("re-runs the search and publishes when a child loancreated bubbles up", async () => {
    searchBooks.mockResolvedValue([localRow()]);
    const element = createComponent();
    await flushPromises();

    typeTerm(element, "twain");
    await flushPromises();
    searchButton(element).dispatchEvent(new CustomEvent("click"));
    await flushPromises();
    expect(searchBooks).toHaveBeenCalledTimes(1);

    element.shadowRoot
      .querySelector("c-library-loan-button")
      .dispatchEvent(
        new CustomEvent("loancreated", { detail: { bookId: "bk1" } })
      );
    await flushPromises();

    expect(searchBooks).toHaveBeenCalledTimes(2);
    expect(publish).toHaveBeenCalled();
  });
});
