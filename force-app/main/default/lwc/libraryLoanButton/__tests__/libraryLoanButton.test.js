import { createElement } from "lwc";
import LibraryLoanButton from "c/libraryLoanButton";
import requestLoan from "@salesforce/apex/LibraryService.requestLoan";

jest.mock(
  "@salesforce/apex/LibraryService.requestLoan",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("c-library-loan-button", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function createComponent(props = {}) {
    const element = createElement("c-library-loan-button", {
      is: LibraryLoanButton
    });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
  }

  it("hides the internal borrower picker when embedded (bookId set)", async () => {
    const element = createComponent({ bookId: "b1" });
    await flushPromises();
    expect(
      element.shadowRoot.querySelector("lightning-record-picker")
    ).toBeNull();
  });

  it("shows the borrower picker in standalone use (recordId, no bookId)", async () => {
    const element = createComponent({ recordId: "b1" });
    await flushPromises();
    expect(
      element.shadowRoot.querySelector("lightning-record-picker")
    ).not.toBeNull();
  });

  it("disables the button until both book and borrower are known", async () => {
    const element = createComponent({ bookId: "b1" });
    await flushPromises();
    expect(element.shadowRoot.querySelector("lightning-button").disabled).toBe(
      true
    );

    element.borrowerId = "003000000000001";
    await flushPromises();
    expect(element.shadowRoot.querySelector("lightning-button").disabled).toBe(
      false
    );
  });

  it("registers the loan and emits loancreated on success", async () => {
    requestLoan.mockResolvedValue("loan-1");
    const element = createComponent({
      bookId: "b1",
      bookTitle: "Dune",
      borrowerId: "003"
    });
    await flushPromises();

    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);
    const loanCreatedHandler = jest.fn();
    element.addEventListener("loancreated", loanCreatedHandler);

    element.shadowRoot
      .querySelector("lightning-button")
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(requestLoan).toHaveBeenCalledWith({
      bookId: "b1",
      borrowerId: "003"
    });
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("success");
    expect(loanCreatedHandler.mock.calls[0][0].detail).toEqual({
      bookId: "b1",
      loanId: "loan-1"
    });
  });

  it("shows an error toast and does not emit loancreated on failure", async () => {
    requestLoan.mockRejectedValue({ body: { message: "No copies available" } });
    const element = createComponent({ bookId: "b1", borrowerId: "003" });
    await flushPromises();

    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);
    const loanCreatedHandler = jest.fn();
    element.addEventListener("loancreated", loanCreatedHandler);

    element.shadowRoot
      .querySelector("lightning-button")
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("error");
    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "No copies available"
    );
    expect(loanCreatedHandler).not.toHaveBeenCalled();
  });

  it("uses the internally selected borrower in standalone mode", async () => {
    requestLoan.mockResolvedValue("loan-2");
    const element = createComponent({ recordId: "bk1" });
    await flushPromises();

    element.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "003x" } })
      );
    await flushPromises();

    const button = element.shadowRoot.querySelector("lightning-button");
    expect(button.disabled).toBe(false);
    button.dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(requestLoan).toHaveBeenCalledWith({
      bookId: "bk1",
      borrowerId: "003x"
    });
  });

  it("normalizes array-shaped and plain error payloads", async () => {
    const element = createComponent({ bookId: "b1", borrowerId: "003" });
    await flushPromises();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    requestLoan.mockRejectedValueOnce({
      body: [{ message: "a" }, { message: "b" }]
    });
    element.shadowRoot
      .querySelector("lightning-button")
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();
    expect(toastHandler.mock.calls[0][0].detail.message).toBe("a, b");

    requestLoan.mockRejectedValueOnce({ message: "plain failure" });
    element.shadowRoot
      .querySelector("lightning-button")
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();
    expect(toastHandler.mock.calls[1][0].detail.message).toBe("plain failure");
  });
});
