# ADR 0011: Monitoring mit kube-prometheus-stack

- Status: akzeptiert
- Datum: 2026-11-26

## Kontext

Die Plattform läuft (ADR 0009, 0010), aber niemand sieht, wie es ihr geht. Das Backend stellt
Metriken unter `/actuator/prometheus` bereit, nur im Cluster erreichbar (ADR 0010).

Die Grenze setzt der einzige Apps-Node (`Standard_B2s_v2`, 1900m CPU und etwa 5,8 GiB
zuteilbar, ADR 0004). Vor dem Monitoring waren davon etwa 830m CPU und 1,8 GiB angefordert.

## Entscheidungen

### 1. kube-prometheus-stack als ArgoCD-Application `monitoring`

- Chart `prometheus-community/kube-prometheus-stack` 93.2.2 (Operator v0.95.2) im Namespace
  `monitoring`: Prometheus Operator, Prometheus, Grafana, kube-state-metrics, node-exporter.
- Requests zusammen etwa 330m CPU und 800 MiB, Speicherlimits für jede Komponente.
- Prometheus liest ServiceMonitors, PodMonitors und Regeln aus allen Namespaces
  (`*SelectorNilUsesHelmValues: false`). Ein Workload liefert seine eigene Überwachung mit.

### 2. Kein Speicher, kurze Aufbewahrung

`emptyDir` statt Datenträger, Aufbewahrung 12 Stunden. Der Cluster lebt nur Stunden; ein
Managed Disk kostete Geld und müsste den Neuaufbau überleben oder verschwinden.

### 3. Nur, was AKS bereitstellt

Controller Manager, Scheduler und etcd verwaltet AKS und stellt sie nicht bereit. kube-proxy
ersetzt Cilium. Ihre Scrapes und Standardregeln sind abgeschaltet, sonst stünden sie dauerhaft
auf „down“.

### 4. Alerts ohne Alertmanager

Regeln werden ausgewertet und sind in Prometheus sichtbar. Ohne Empfänger (Mail, Chat) wäre
Alertmanager nur ein weiterer Pod. Das Admission-Webhook des Operators ist ebenfalls aus: es
prüft nur PrometheusRules und bräuchte eigene Zertifikate.

### 5. Grafana nur per Port-Forward

- Wie ArgoCD nicht über den Gateway veröffentlicht.
- Das Admin-Passwort erzeugt das Chart pro Cluster zufällig, es steht nicht in Git. ArgoCD
  ignoriert das Feld (`ignoreDifferences`), sonst würde jeder Sync ein neues Passwort setzen.
- Dashboards als Code: „JVM (Micrometer)“ (grafana.com 4701, Revision 10) über die Werte des
  Charts.

### 6. Überwachung des Backends im Workload

In `gitops/workloads/backend`:

- ServiceMonitor auf `/actuator/prometheus`. Er setzt das Label `application=backend`, das das
  JVM-Dashboard erwartet und Spring Boot nicht von sich aus setzt.
- PrometheusRule mit `BackendDown` und `BackendHeapHigh` als Beispiel.
- NetworkPolicy `allow-from-monitoring`: Ohne sie blockiert das Default Deny (ADR 0010) den
  Scrape.

## Begründung

- kube-prometheus-stack ist der verbreitete Standard und bringt Regeln und Dashboards für
  Kubernetes mit.
- Die Ressourcengrenzen halten das Monitoring auf dem kleinen Node, ohne die Plattform zu
  verdrängen.

## Verworfene Alternativen

- **Azure Monitor managed Prometheus und Azure Managed Grafana:** weniger Betrieb, aber
  Kosten außerhalb des Clusters, die auch ohne laufenden Cluster anfallen können, und weniger
  sichtbar, was passiert.
- **Grafana über den Gateway:** bräuchte eine Anmeldung, die nicht im Repository steht, etwa
  SSO. Später möglich.
- **Datenträger für Prometheus:** Kosten und Lebenszyklus passen nicht zu einem Cluster für
  Stunden.

## Konsequenzen

- Metriken gehen mit jedem Abbau verloren. Für einen Vergleich über Tage bräuchte es einen
  externen Speicher (etwa Azure Monitor Workspace).
- Alerts benachrichtigt niemand. Mit einem Empfänger kommt Alertmanager dazu.
- ArgoCD, cert-manager und external-dns haben keine Resource Requests. Unter Speicherdruck
  würden sie zuerst verdrängt. Das wird gesondert nachgezogen.
- Grafana lädt das Dashboard beim Start von grafana.com. Ohne Internetzugang fehlt es.
