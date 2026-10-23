import { createElement } from "lwc";
import LibraryLoanList from "c/libraryLoanList";
import getRecentLoans from "@salesforce/apex/LibraryListController.getRecentLoans";
import { refreshApex } from "@salesforce/apex";
import { publish } from "lightning/messageService";
import { deleteRecord } from "lightning/uiRecordApi";
import LightningConfirm from "lightning/confirm";

jest.mock(
  "@salesforce/apex/LibraryListController.getRecentLoans",
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

const LOAN = {
  Id: "l1",
  Name: "LBL-0001",
  Book__c: "bk1",
  Borrower__r: { Name: "Ana" },
  Book__r: { Title__c: "Dune" },
  Loan_Start_Date__c: "2026-09-01",
  Loan_End_Date__c: "2026-09-15"
};

function rowActionEvent(row) {
  return new CustomEvent("rowaction", {
    detail: { action: { name: "delete" }, row }
  });
}

describe("c-library-loan-list", () => {
  beforeEach(() => {
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function createComponent() {
    const element = createElement("c-library-loan-list", {
      is: LibraryLoanList
    });
    document.body.appendChild(element);
    return element;
  }

  it("flattens the wired loans for the datatable", async () => {
    const element = createComponent();
    getRecentLoans.emit([LOAN]);
    await flushPromises();

    const datatable = element.shadowRoot.querySelector("lightning-datatable");
    expect(datatable.data).toEqual([
      {
        Id: "l1",
        name: "LBL-0001",
        bookId: "bk1",
        borrowerName: "Ana",
        bookTitle: "Dune",
        startDate: "2026-09-01",
        endDate: "2026-09-15"
      }
    ]);
  });

  it("shows the empty state when there are no loans", async () => {
    const element = createComponent();
    getRecentLoans.emit([]);
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("No loans registered");
  });

  it("deletes the loan after confirmation, refreshes and publishes", async () => {
    LightningConfirm.open.mockResolvedValue(true);
    const element = createComponent();
    getRecentLoans.emit([LOAN]);
    await flushPromises();

    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    element.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
      rowActionEvent({
        Id: "l1",
        name: "LBL-0001",
        bookId: "bk1",
        bookTitle: "Dune"
      })
    );
    await flushPromises();

    expect(LightningConfirm.open).toHaveBeenCalled();
    expect(deleteRecord).toHaveBeenCalledWith("l1");
    expect(refreshApex).toHaveBeenCalled();
    expect(publish.mock.calls[0][1]).toBe("LibraryRefresh__c");
    expect(publish.mock.calls[0][2]).toEqual({
      source: "libraryLoanList",
      bookId: "bk1"
    });
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("success");
  });

  it("does not delete when the confirmation is dismissed", async () => {
    LightningConfirm.open.mockResolvedValue(false);
    const element = createComponent();
    getRecentLoans.emit([LOAN]);
    await flushPromises();

    element.shadowRoot
      .querySelector("lightning-datatable")
      .dispatchEvent(
        rowActionEvent({ Id: "l1", name: "LBL-0001", bookTitle: "Dune" })
      );
    await flushPromises();

    expect(deleteRecord).not.toHaveBeenCalled();
  });

  it("shows an error message when the wire fails", async () => {
    const element = createComponent();
    getRecentLoans.error({ message: "load failed" });
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("load failed");
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
  });

  it("ignores row actions other than delete", async () => {
    const element = createComponent();
    getRecentLoans.emit([LOAN]);
    await flushPromises();

    element.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "view" }, row: {} }
      })
    );
    await flushPromises();

    expect(LightningConfirm.open).not.toHaveBeenCalled();
  });

  it("shows an error toast when the delete fails", async () => {
    LightningConfirm.open.mockResolvedValue(true);
    deleteRecord.mockRejectedValueOnce({ body: { message: "record locked" } });
    const element = createComponent();
    getRecentLoans.emit([LOAN]);
    await flushPromises();

    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    element.shadowRoot
      .querySelector("lightning-datatable")
      .dispatchEvent(
        rowActionEvent({ Id: "l1", name: "LBL-0001", bookTitle: "Dune" })
      );
    await flushPromises();

    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("error");
    expect(toastHandler.mock.calls[0][0].detail.message).toBe("record locked");
  });
});
