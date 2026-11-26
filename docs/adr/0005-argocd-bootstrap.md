# ADR 0005: ArgoCD per Terraform und Helm

- Status: akzeptiert
- Datum: 2026-11-23

## Kontext

Nach dem Aufbau des Clusters muss ArgoCD hinein. Ab dann zieht ArgoCD alles Weitere aus Git
(App-of-Apps). Offen war, wie ArgoCD selbst installiert wird. Zur Wahl standen:

| Weg | Prinzip |
|---|---|
| A | Terraform mit Helm-Provider installiert ArgoCD und eine Wurzel-Application |
| B | Ein Skript im Workflow installiert ArgoCD per `helm` und `kubectl` |
| C | `az aks command invoke` führt `helm`/`kubectl` über die Azure-API aus |
| D | AKS-GitOps-Erweiterung (Flux) |

## Entscheidungen

### 1. Weg A: Terraform mit Helm-Provider

ArgoCD und die Wurzel-Application werden per `helm_release` installiert. Alles Weitere
(cert-manager, external-dns, Anwendungen) verwaltet ArgoCD aus Git.

### 2. Zwei Module mit zwei States

| Modul | Inhalt | Spricht mit |
|---|---|---|
| `infra/cluster` | AKS, Federated Credentials | nur Azure-API |
| `infra/platform` | Helm-Provider, ArgoCD, Wurzel-Application | Kubernetes-API |

Beide stehen in `ON_DEMAND_MODULES`. Aufbau: `cluster → platform`. Abbau: `platform → cluster`.

`infra/platform` liest den Cluster per Datenquelle und meldet sich per Entra ID an
(`kubelogin` nach `azure/login`). Die Apply-Identität hat dafür
`Azure Kubernetes Service RBAC Cluster Admin` auf `rg-aks` (ADR 0006).

### 3. `infra/platform` wird in Pull Requests nicht geplant

In Pull Requests läuft für `infra/platform` nur `fmt -check` und `validate`. Den Plan zeigt der
Aufbau-Workflow vor dem Apply.

### 4. Kein Plan ohne Cluster

Der Aufbau-Workflow prüft vor `infra/platform` mit `az aks show`, ob der Cluster existiert.
Gibt es ihn nicht, wird das Modul mit einem Hinweis übersprungen.

### 5. Umsetzung

- Zwei Releases in `infra/platform`: `argo-cd` (Namespace `argocd`) und `argocd-apps` mit der
  Wurzel-Application `root`. Die zweite hängt von der ersten ab, weil die CRD für
  `Application` mit `argo-cd` kommt. Chart-Versionen sind als Variablen gepinnt.
- `root` synchronisiert `gitops/apps` in diesem Repository (Branch `main`, rekursiv,
  `prune` und `selfHeal`). Das Repository ist öffentlich, ArgoCD braucht keine Zugangsdaten.
- Kein `resources-finalizer` an `root`: Beim Abbau löscht Terraform nur ArgoCD selbst, der
  Cluster verschwindet danach ohnehin.
- Dex und Notifications sind abgeschaltet. Zugriff per `kubectl port-forward` mit dem
  initialen Admin-Passwort, bis es einen Ingress und SSO gibt.
- Anmeldung: lokal `kubelogin -l azurecli` nach `az login`. In der Pipeline
  `kubelogin -l workloadidentity` mit einem frischen GitHub-OIDC-Token vor Plan und Apply
  (`TF_VAR_kubelogin_login`). Das Token hinter `azure/login` gilt nur wenige Minuten und ist
  abgelaufen, wenn der Cluster nach etwa zehn Minuten steht; die Azure CLI könnte dann kein
  Token für die AKS-API mehr holen.
- kubelogin wird im Workflow per Version heruntergeladen und per SHA256 geprüft. Eine Action
  dafür stünde nicht in der Allowlist (ADR 0007).
- In Pull Requests steht `infra/platform` in `NO_PR_PLAN_MODULES` (nur `fmt` und `validate`).
  Einen Plan vor der Freigabe gibt es nicht (ADR 0004); der Plan steht in der Zusammenfassung
  des Laufs.

## Begründung

- Weg A ist deklarativ, reproduzierbar und braucht kein zweites Werkzeug. Der Zustand von
  ArgoCD steht im State wie alle anderen Ressourcen.
- Ein Provider, der aus einer Ressource im selben State konfiguriert wird, ist eine bekannte
  Fehlerquelle: Beim ersten Aufbau existiert der Cluster noch nicht, beim Abbau ist die
  Reihenfolge heikel. Zwei States lösen das.
- Helm speichert den Zustand von Releases in Kubernetes-Secrets. Die Plan-Identität dürfte sie
  nur mit deutlich mehr Rechten im Cluster lesen. Nach dem ersten Aufbau ändert sich
  `infra/platform` kaum, weil ArgoCD übernimmt. Ein Plan in Pull Requests bringt wenig.
- Der Cluster ist meistens abgebaut. Ein Plan gegen einen fehlenden Cluster würde den
  Pull-Request-Check grundlos rot färben.

## Verworfene Alternativen

- **B, Skript im Workflow:** einfach, aber imperativ. Was installiert ist, steht in keinem
  State, und Änderungen sind nicht als Plan prüfbar.
- **C, `az aks command invoke`:** funktioniert auch bei privaten Clustern, ist aber langsam und
  sperrig. Der Cluster ist öffentlich (ADR 0004), der Vorteil zählt hier nicht.
- **D, AKS-GitOps-Erweiterung:** braucht keinen API-Zugriff, installiert aber Flux statt ArgoCD.
  Das Projekt soll ArgoCD zeigen.
- **Ein Modul für Cluster und ArgoCD:** Provider-Konfiguration aus einer Ressource im selben
  State, siehe Begründung.

## Konsequenzen

- Die Apply-Identität braucht Zugriff auf die Kubernetes-API mit Cluster-Admin-Rechten. Wer
  `apply` kontrolliert, kontrolliert den Cluster. Schutz bietet die Freigabe in `prod`.
- Der Runner muss den öffentlichen API-Endpunkt erreichen (ADR 0004).
- Änderungen an `infra/platform` sind im Pull Request nicht als Plan sichtbar, nur im
  Aufbau-Workflow vor dem Apply.
- Der Abbau muss `infra/platform` vor `infra/cluster` zerstören. Sonst bleibt ein State mit
  Helm-Releases zurück, deren Cluster nicht mehr existiert.
- Wird der Cluster außerhalb des Workflows gelöscht, überspringt `down` das Modul
  `infra/platform`, und sein State bleibt mit verwaisten Releases zurück. Abhilfe:
  `terraform state rm` für beide Releases in `infra/platform`.
