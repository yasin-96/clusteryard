# ADR 0010: Erste Anwendung und Regeln für Workloads

- Status: akzeptiert
- Datum: 2026-11-26

## Kontext

Plattform, DNS, Zertifikate und Gateway stehen (ADR 0005, 0008, 0009). Als erste Anwendung
läuft das Spring-Boot-Backend aus `three-tier-app-azure`: `GET /api` liefert „hello world“,
Actuator (`health`, `info`, `prometheus`) liegt auf demselben Port 8080. Es hat keine
Datenbank und keine Secrets.

Diese ADR legt fest, wie Workloads auf die Plattform kommen. Weitere Dienste folgen demselben
Muster.

## Entscheidungen

### 1. Image aus GitHub Container Registry, gebaut im Anwendungs-Repository

- `three-tier-app-azure` baut und testet das Backend und veröffentlicht
  `ghcr.io/yasin-96/three-tier-backend:<commit>` (Workflow `publish-backend-ghcr.yml`).
- Anmeldung an GHCR mit dem `GITHUB_TOKEN` des Laufs, kein gespeichertes Secret. Nur Actions
  von GitHub, auf Commit-SHAs gepinnt.
- Das Package ist öffentlich. Der Cluster braucht kein Pull-Secret, die Kubelet-Identität
  kein `AcrPull` (ADR 0004).

### 2. Tag gleich Commit, nie ein bewegliches Tag

`gitops/workloads/backend/deployment.yaml` nennt den Commit des Anwendungs-Repositorys als Tag
und zusätzlich den Digest (`<tag>@sha256:…`). Der Digest garantiert das exakte Image, auch wenn
das Tag neu gepusht würde. Eine
neue Version ist ein Pull Request in clusteryard. Was läuft, steht damit immer in Git, und
ein Rollback ist ein Revert. `:main` wird zwar mit veröffentlicht, aber nicht verwendet.

### 3. Aufbau eines Workloads

Eine Application in `gitops/apps`, Manifeste in `gitops/workloads/<name>`:

| Ressource | Regel |
|---|---|
| Namespace | Label `clusteryard.dev/gateway-access=true` (sonst lehnt der Gateway die Route ab), Pod Security `restricted` |
| Deployment | ohne Root, nur lesbares Dateisystem, keine Capabilities, kein Service-Account-Token, Probes auf Liveness und Readiness |
| Service | `ClusterIP`, Port 80 |
| HTTPRoute | am Listener `https` des Gateways `public`, nur die öffentlichen Pfade |
| NetworkPolicy | Default Deny für eingehenden Verkehr, Ausnahme nur für den Namespace `envoy-gateway-system` |

### 4. Nur `/api` ist öffentlich

Die Route leitet nur `/api` weiter. `/actuator` mit Health und Metriken bleibt im Cluster und
ist später für Prometheus gedacht.

### 5. Ressourcen ohne CPU-Limit

Requests `100m` CPU und `256Mi` Speicher, Limit nur für Speicher (`512Mi`). Ein CPU-Limit
bremst vor allem den Start der JVM auf dem kleinen B-Serien-Node. Die Heap-Größe folgt dem
Speicherlimit (`-XX:MaxRAMPercentage=75`).

## Begründung

- Build im Anwendungs-Repository, Deployment im Plattform-Repository: die übliche Trennung bei
  GitOps. Die Pipeline der Anwendung braucht keinen Zugang zum Cluster.
- Gepinnte Tags machen jeden Stand reproduzierbar. Mit `:main` wüsste niemand, welche Version
  nach einem Neuaufbau läuft.
- Default Deny und die Pod-Security-Regeln verhindern, dass ein Fehler im Manifest still eine
  offene Tür hinterlässt.

## Verworfene Alternativen

- **Azure Container Registry:** feste Kosten pro Tag und `AcrPull` für die Kubelet-Identität;
  GHCR ist für öffentliche Images kostenlos.
- **Automatische Tag-Aktualisierung (ArgoCD Image Updater):** später möglich. Für den Anfang
  reicht ein Pull Request pro Version und ist nachvollziehbarer.
- **Ganzer Pfad `/` öffentlich:** würde `/actuator/prometheus` ins Internet stellen.

## Konsequenzen

- Jede neue Version des Backends braucht einen Pull Request in clusteryard mit dem neuen Tag.
- Das Image läuft standardmäßig als root. Der Cluster erzwingt eine andere UID
  (`runAsUser: 10001`). Ein `USER` im Dockerfile wäre sauberer.
- Bestätigt beim ersten Aufbau (2026-11-26): Cilium lässt die Kubelet-Probes trotz Default Deny
  durch, die Envoy-Proxys laufen in `envoy-gateway-system`, und ein Pod aus einem anderen
  Namespace erreicht das Backend nicht.
