# ADR 0001: Pipeline-Identitäten für GitHub Actions

- Status: akzeptiert
- Datum: 2026-11-17
- Aktualisiert: 2026-11-19 (State-Zugriff von Plan auf Lesen reduziert, OIDC-Subject mit festen IDs)

## Kontext

Die Terraform-Pipeline (`.github/workflows/terraform.yml`) muss sich bei Azure anmelden, um
Pull Requests zu planen und nach dem Merge auf `main` anzuwenden. Gesucht ist ein Weg, der

- ohne langlebige Secrets in GitHub auskommt,
- Pull Requests keine Schreibrechte in Azure gibt,
- jede Änderung an Azure an eine menschliche Freigabe bindet,
- für ein Lernprojekt auf einem privaten Abonnement mit wenig Pflegeaufwand auskommt.

## Entscheidungen

### 1. OIDC statt Client Secrets

GitHub Actions meldet sich per OpenID Connect (Federated Identity Credentials) an.
Issuer ist `https://token.actions.githubusercontent.com`, Audience `api://AzureADTokenExchange`.
Die App-Registrierungen haben **kein** Client Secret. In GitHub liegen nur Client-IDs,
Tenant-ID und Subscription-ID als Variablen, also keine geheimen Werte.

### 2. Zwei getrennte Identitäten

| | plan | apply |
|---|---|---|
| Verwendet von | Job `terraform-plan` bei Pull Requests | Job `terraform-apply` nach Push auf `main` |
| OIDC-Subject | `repo:<owner>@<id>/<repo>@<id>:pull_request` | `repo:<owner>@<id>/<repo>@<id>:environment:prod` |
| Abonnement | `Reader` | `Contributor` |
| State-Container | `Storage Blob Data Reader` | `Storage Blob Data Contributor` |

Ein Pull Request kann sich nie als `apply` anmelden, weil sein Token ein anderes Subject trägt.
`apply` ist nur über das GitHub Environment `prod` erreichbar, das eine Freigabe verlangt.

### 3. OIDC-Subject mit festen IDs

Das Subject enthält Owner- und Repository-ID (`github_oidc_repo`, z. B. `owner@123/repo@456`),
nicht nur die Namen. Wird das Repository gelöscht und unter gleichem Namen neu angelegt oder
übernimmt jemand anderes einen frei gewordenen Namen, passt das Subject nicht mehr. Ein fremdes
Repository mit demselben Namen kann die Identitäten also nicht übernehmen.

### 4. Plan liest den State nur, ohne Lock

`plan` läuft mit `-lock=false` und bekommt deshalb nur `Storage Blob Data Reader`.
Der Lock ist ein Blob-Lease und bräuchte Schreibrechte. Wer Pull Requests öffnen kann,
kann damit den State weder verändern noch löschen.

Der Zugriff auf den State läuft über Entra ID (`ARM_USE_AZUREAD=true`), nicht über die
Zugriffsschlüssel des Storage Accounts. `Reader` darf die Schlüssel ohnehin nicht abrufen.

### 5. Rollen auf Abonnement-Ebene

`Reader` und `Contributor` werden auf das **gesamte Abonnement** vergeben, nicht auf
einzelne Ressourcengruppen.

### 6. Identitäten werden lokal angelegt

`infra/identity/` hat eigenen State (`identity/terraform.tfstate`) und wird lokal mit `az login`
angewendet. Die Pipeline kann ihre eigene Identität nicht anlegen, bevor sie eine hat, und
sie soll ihre eigenen Rechte nicht erweitern können. Im Workflow steht das Modul deshalb in
`LOCAL_ONLY_MODULES`, genau wie `infra/bootstrap/`.

## Begründung

- Das Abonnement wird ausschließlich für clusteryard genutzt. Ressourcengruppen entstehen und
  verschwinden mit dem Cluster; Rollen pro Ressourcengruppe müssten jedes Mal mitgepflegt werden.
- Zwei Identitäten kosten kaum Aufwand (ein `for_each` in `infra/identity/main.tf`), trennen
  aber Lesen und Schreiben sauber.
- Kein Secret bedeutet: nichts, das ablaufen, rotiert werden oder leaken kann.

## Verworfene Alternativen

- **Ein Service Principal mit Client Secret:** Das Secret muss in GitHub gespeichert und rotiert
  werden, und jeder Job hätte dieselben Rechte.
- **Eine einzige OIDC-Identität für Plan und Apply:** Pull Requests hätten Schreibrechte in Azure.
- **`plan` mit Lock (`Storage Blob Data Contributor`):** schützt gegen parallele Läufe, aber
  Pull Requests könnten den State verändern. Da `apply` ohnehin über `concurrency` serialisiert
  ist und `plan` nichts ändert, überwiegt der Nutzen nicht.
- **Subject nur mit Namen (`repo:<owner>/<repo>`):** einfacher zu lesen, aber anfällig, wenn ein
  Name später von jemand anderem belegt wird.

## Konsequenzen

- `apply` kann alle Ressourcen im Abonnement ändern oder löschen (Contributor ist breit).
  Schutz bieten nur die Freigabe in `prod` und `prevent_destroy` an wichtigen Ressourcen
  (State-Speicher, DNS-Zone).
- `apply` kann **keine** Rollenzuweisungen anlegen. Sobald AKS, external-dns oder cert-manager
  Rollenzuweisungen brauchen, bekommt `apply` zusätzlich `Role Based Access Control Administrator`
  mit Bedingungen (nur bestimmte Rollen, nur an bestimmte Principal-Typen). Wird entschieden,
  wenn es so weit ist; dann neues ADR oder Nachtrag hier.
- Ein Plan ohne Lock kann einen State sehen, den ein laufendes Apply gerade ändert. Der Plan ist
  dann ungenau, aber harmlos: `apply` plant beim Lauf neu.
- Nach einer Umbenennung von Owner oder Repository bleiben die IDs gleich, die Anmeldung
  funktioniert weiter. Nach einem Neuanlegen des Repositorys muss `github_oidc_repo` angepasst
  und `infra/identity/` lokal neu angewendet werden.
- Später: Einschränkung auf die Ressourcengruppen des Projekts statt des ganzen Abonnements.
