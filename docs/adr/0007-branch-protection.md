# ADR 0007: Schutz von `main` und GitHub-Einstellungen als Code

- Status: akzeptiert
- Datum: 2026-11-24

## Kontext

Jeder Merge auf `main` löst das Apply der langlebigen Module aus (ADR 0001). Wer direkt auf
`main` pushen kann, ändert damit Azure-Ressourcen ohne geprüften Plan. Das Repository ist
öffentlich und hat einen einzigen Maintainer. Ein zweiter Reviewer, wie in Teams üblich,
fehlt.

Die Einstellungen waren bisher nur in der GitHub-Oberfläche gesetzt. Damit sind sie weder
nachvollziehbar noch reproduzierbar.

## Entscheidungen

### 1. Modul `infra/github`, nur lokal angewendet

- State `github/terraform.tfstate`, Provider `integrations/github`, in `LOCAL_ONLY_MODULES`.
- Anmeldung lokal mit `GITHUB_TOKEN=$(gh auth token)`.
- Die Pipeline hat kein Token mit Admin-Rechten auf das Repository. Sie kann ihre eigenen
  Schutzregeln nicht ändern.

### 2. Ruleset für `main` statt klassischer Branch Protection

| Regel | Wert | Wirkung |
|---|---|---|
| Pull Request | Pflicht | Kein direkter Push auf `main` |
| Erforderliche Freigaben | 0 | Siehe Abschnitt 3 |
| Offene Review-Threads | müssen gelöst sein | Kommentare werden nicht übergangen |
| Merge-Methode | nur Squash | Ein Commit pro Pull Request |
| Lineare Historie | Pflicht | Keine Merge-Commits |
| Status-Check | `terraform-plan`, nur von GitHub Actions | Kein Merge ohne grünen Plan |
| Branch aktuell | Pflicht (`strict`) | Der Plan im PR ist der Plan nach dem Merge |
| Force Push, Löschen | verboten | Historie von `main` bleibt erhalten |
| Bypass | niemand | Gilt auch für den Admin |

Der Status-Check ist an die App-ID von GitHub Actions gebunden. Ein Commit-Status mit demselben
Namen aus einer anderen Quelle erfüllt ihn nicht.

### 3. Keine Pflicht-Freigabe, solange es einen Maintainer gibt

GitHub erlaubt nicht, eigene Pull Requests freizugeben. Eine Pflicht-Freigabe würde jeden Merge
blockieren oder einen Bypass erzwingen. Die Kontrollpunkte sind stattdessen:

1. der grüne Plan im Pull Request,
2. die Freigabe der Umgebung `prod` vor dem Apply.

`CODEOWNERS` ist angelegt, wird aber nicht erzwungen. Mit einem zweiten Maintainer werden
`required_approving_review_count = 1`, `require_code_owner_review` und `prevent_self_review`
auf `prod` eingeschaltet.

### 4. Umgebung `prod`

- Deployments nur vom Branch `main`.
- Freigabe durch den Maintainer, kein Bypass für Admins.
- Die Apply-Identität vertraut genau dieser Umgebung (ADR 0001). Die Umgebung ist damit die
  Grenze zwischen Pull Request und Schreibrechten in Azure.

### 5. GitHub Actions eingeschränkt

- Nur Actions von GitHub sowie `azure/login` und `hashicorp/setup-terraform`.
- Actions müssen auf einen Commit-SHA gepinnt sein (`sha_pinning_required`).
- Das Workflow-Token ist standardmäßig nur lesend. Workflows dürfen keine Pull Requests
  freigeben.

### 6. Repository-Einstellungen

- Nur Squash-Merges, Branches werden nach dem Merge gelöscht.
- Secret Scanning mit Push Protection, Dependabot-Alerts.

## Begründung

- Rulesets sind der Nachfolger der klassischen Branch Protection. Sie gelten auch für Admins,
  ohne eigene Option, und lassen sich später auf Tags und weitere Branches ausdehnen.
- `strict` kostet gelegentlich ein „Update branch“. Ohne die Option könnte ein Plan grün sein,
  der auf einem veralteten Stand von `main` gerechnet wurde.
- Eine Allowlist für Actions mit SHA-Pinning schützt vor kompromittierten oder umgehängten Tags
  in fremden Actions, die mit OIDC Zugriff auf Azure bekämen.

## Verworfene Alternativen

- **Einstellungen nur in der Oberfläche:** nicht nachvollziehbar, Drift fällt nicht auf.
- **Skript mit `gh api`:** reproduzierbar, aber ohne Plan und ohne Drift-Erkennung.
- **Anwendung durch die Pipeline:** bräuchte ein Admin-Token als Secret. Die Pipeline könnte
  dann ihre eigenen Schutzregeln abschalten.
- **Pflicht-Freigabe mit Bypass für den Admin:** der Bypass würde zur Regel und die Freigabe
  zur Formalität.

## Konsequenzen

- Auch der Maintainer kann nicht mehr direkt auf `main` pushen. Bei einer defekten Pipeline
  muss das Ruleset lokal über `infra/github` gelockert werden; das ist sichtbar im State und
  in Git.
- Neue Actions müssen in die Allowlist aufgenommen werden, bevor ein Workflow sie nutzen kann.
- Kommen weitere Pflicht-Checks hinzu (tflint, Checkov), werden sie im Ruleset ergänzt.
