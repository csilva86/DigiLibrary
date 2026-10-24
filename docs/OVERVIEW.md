# What DigiLibrary does

DigiLibrary is a Salesforce app for managing a corporate digital library:
tracking which books exist, how many copies are available, and who currently
has one on loan.

It was built for StrongCRM's "Apex Developer Challenge," which asked for book
inventory management, search by title or author, and loan registration —
plus an extra integration with the public [Open Library](https://openlibrary.org)
API.

## What a user can do

- **Search for a book** by title or author. The search checks the library's
  own catalogue and, at the same time, looks it up on Open Library, so a book
  the library doesn't own yet still shows up in the results.
- **Import a book** found only on Open Library into the local catalogue with
  one click, making it immediately available to loan.
- **Request a loan** of any book that has at least one copy available. The
  system won't let a loan go through if there are no copies left — it fails
  with a clear message instead of over-committing the catalogue.
- **See the current catalogue and active loans** in two live lists on the
  app's Home page, which update automatically whenever a loan, import, or
  return happens anywhere else in the app.
- **Return a book** by deleting its loan record, which puts the copy back
  into circulation right away.

## What happens behind the scenes

- Every book keeps a running count of **total copies** and **available
  copies**. Registering a loan decreases the available count; deleting a loan
  (a return) increases it back — and this stays correct even if many loans
  are created or removed in the same batch operation.
- A book can never be loaned past its available copies — that rule is
  enforced on the server, not just in the interface, so it can't be bypassed.
- If the external Open Library API is slow or unavailable, search still
  works using the local catalogue only; the integration degrades gracefully
  instead of breaking the page.

## Where to look next

- [`docs/artifacts/deliverables-inventory.html`](artifacts/deliverables-inventory.html) — full technical inventory of every object, Apex class, and component delivered.
- [`docs/artifacts/loan-flow-swimlane.html`](artifacts/loan-flow-swimlane.html) — step-by-step diagram of a loan request.
- [`docs/artifacts/field-guide.html`](artifacts/field-guide.html) — an in-depth study guide to the code and the reasoning behind it.
