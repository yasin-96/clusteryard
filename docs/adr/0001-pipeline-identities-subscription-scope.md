# ADR 0001: Pipeline-Identitäten mit Rollen auf Abonnement-Ebene

- Status: akzeptiert
- Datum: 2026-11-17

## Kontext

GitHub Actions meldet sich per OIDC (Federated Credentials, keine Secrets) bei Azure an.
Es gibt zwei Identitäten (`infra/identity/`):

- **plan**: Pull Requests (`repo:<owner>/<repo>:pull_request`), Rolle `Reader` auf das Abonnement.
- **apply**: nur über das GitHub Environment `prod` mit Freigabe (`repo:<owner>/<repo>:environment:prod`), Rolle `Contributor` auf das Abonnement.

Beide erhalten `Storage Blob Data Contributor` auf den State-Container, weil auch `plan` den Lock (Blob-Lease) schreibt.

## Entscheidung

Die Rollen `Reader` und `Contributor` werden auf das **gesamte Abonnement** vergeben.

## Begründung

Lernprojekt auf einem privaten Abonnement, das ausschließlich für clusteryard genutzt wird.
Ressourcengruppen entstehen und verschwinden mit dem Cluster; Rollen pro Ressourcengruppe
müssten jedes Mal mitgepflegt werden.

## Konsequenzen

- `apply` kann alle Ressourcen im Abonnement ändern oder löschen (Contributor ist breit).
- `apply` kann **keine** Rollenzuweisungen anlegen. Sobald AKS oder andere Module Rollenzuweisungen
  erzeugen, braucht `apply` zusätzlich z. B. `Role Based Access Control Administrator` mit
  Bedingungen (nur bestimmte Rollen, nur an bestimmte Principal-Typen). Wird geklärt, wenn es so weit ist.
- Später: Einschränkung auf die Ressourcengruppen des Projekts statt des ganzen Abonnements.
