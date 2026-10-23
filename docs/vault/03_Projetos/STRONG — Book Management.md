---
type: projeto
dominio: salesforce
cliente: STRONG
status: ativo
inicio: 2026-09-01
org: Production + 2 sandboxes (DEV, UAT)
stakeholders:
  - Ana Prado (PO)
  - Bruno Lima (Tech Lead)
tags:
  - projeto
---
# STRONG — Book Management

## Escopo & arquitetura
DigiLibrary, a corporate digital library. aims to provide its employees with a seamless way to
access, borrow, and return books. You have been tasked with developing a core Apex-based
system to manage the library's inventory, book search, and loan processes efficiently.

**1. Loan Registration:**
	**○** A user can only register a loan if copies of the book are available. Appropriate
	error handling should be implemented.
	○ When a loan is registered, the inventory of available copies should be decreased.
	○ When a loan is removed, the inventory of available copies should be increased.
**2.** Book Search and Details:
	○ Create an interface (Visualforce Page or Lightning Web Component) that allows
	users to search for books by title or author.
	○ The interface should show book details, including the number of available copies
	and a button to request a loan.

## Ambientes / orgs
- **DEV** — Salesforce Developer Edition Org.

## Decisões importantes
- Componentes LWC sempre com dados vindos de Apex `@wire` (cacheável), nunca
  chamadas imperativas para listagens.
- Padrão de refresh de listas definido em [[LWC-Aura · Atualizar lista com refreshApex]].

## Tarefas do projeto
```dataview
TABLE status, prioridade, prazo
FROM "02_Tarefas"
WHERE projeto = [[STRONG — Book Management]]
SORT prazo ASC
```
