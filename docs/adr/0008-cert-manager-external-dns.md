# ADR 0008: cert-manager und external-dns per GitOps

- Status: akzeptiert
- Datum: 2026-11-26

## Kontext

Dienste im Cluster sollen unter `*.k8s.clusteryard.dev` per HTTPS erreichbar sein. Dafür
braucht es DNS-Einträge, die mit jedem Neuaufbau des Clusters (neue Load-Balancer-IP) neu
gesetzt werden, und TLS-Zertifikate. Die Azure-Seite steht bereits:

- DNS-Zone `k8s.clusteryard.dev` in `rg-dns` (ADR 0003).
- Workload Identities `id-cert-manager` und `id-external-dns` mit `DNS Zone Contributor` auf
  genau dieser Zone (ADR 0006).
- Federated Credentials für `system:serviceaccount:cert-manager:cert-manager` und
  `system:serviceaccount:external-dns:external-dns`, bei jedem Aufbau neu angelegt (ADR 0004).

Offen war die Installation im Cluster.

## Entscheidungen

### 1. Beide als ArgoCD-Applications in `gitops/apps`

| Application | Quelle | Namespace |
|---|---|---|
| `cert-manager` | Chart `jetstack/cert-manager` v1.21.3 | `cert-manager` |
| `cert-manager-issuers` | `gitops/platform/cert-manager-issuers` | `cert-manager` |
| `external-dns` | Chart `external-dns` 1.23.0 und `gitops/platform/external-dns` | `external-dns` |

- `gitops/apps` enthält nur Applications (App-of-Apps, ADR 0005). Weitere Manifeste liegen in
  `gitops/platform/<name>`, das die Wurzel-Application nicht direkt synchronisiert.
- Chart-Versionen sind gepinnt. Werte stehen in der Application (`valuesObject`), nicht in
  eigenen Dateien.
- Namespace, Release-Name und Service Account heißen wie die Komponente. Die Federated
  Credentials vertrauen genau diesen Namen.

### 2. Workload Identity statt Secrets

- Service Account mit Annotation `azure.workload.identity/client-id`, Pod mit Label
  `azure.workload.identity/use: "true"`. Der AKS-Webhook injiziert das Token.
- Im Cluster liegen keine Azure-Zugangsdaten. Die `azure.json` von external-dns ist eine
  ConfigMap mit Tenant-, Subscription- und Ressourcengruppen-ID, ohne Geheimnis
  (`useWorkloadIdentityExtension`).

### 3. Zertifikate über DNS-01, zwei ClusterIssuers

- `letsencrypt-staging` zum Testen, `letsencrypt-prod` für echte Zertifikate.
- DNS-01 statt HTTP-01: funktioniert ohne öffentlich erreichbaren Ingress und erlaubt später
  Wildcard-Zertifikate.
- Keine E-Mail-Adresse im ACME-Konto. Let's Encrypt verschickt keine Ablauf-Mails mehr, und das
  Repository ist öffentlich.
- Die Issuers sind eine eigene Application. Sie brauchen die CRDs von cert-manager; bis die da
  sind, schlägt der Sync fehl und wird wiederholt (`SkipDryRunOnMissingResource`, `retry`).
- `crds.keep: true`: Wird cert-manager entfernt, bleiben die CRDs und damit alle Zertifikate.

### 4. external-dns mit `sync` und festem Owner

- `domainFilters: [k8s.clusteryard.dev]`, Quellen `service` und `ingress`.
- `policy: sync`: Einträge verschwinden, wenn ihr Ingress oder Service weg ist.
- `txtOwnerId: aks-clusteryard`, fest über alle Neuaufbauten. Ein neuer Cluster erkennt die
  Einträge seines Vorgängers als eigene und räumt sie auf.

### 5. IDs im öffentlichen Repository (akzeptiert)

Tenant-ID, Subscription-ID und die Client-IDs der Workload Identities stehen im Klartext in
`gitops/`. Es sind Bezeichner, keine Zugangsdaten. Anmelden kann sich nur, wer ein Token mit
passendem Issuer (OIDC-URL des Clusters) und Subject (Service Account) vorlegt. Die
Alternative, die Werte von Terraform zur Laufzeit in den Cluster zu schreiben, würde jede
Komponente an `infra/platform` koppeln.

## Begründung

- Seit ADR 0005 ist ArgoCD für alles im Cluster zuständig. Terraform bleibt beim Bootstrap.
- Die Azure-Rechte sind schon minimal und langlebig (ADR 0006). Im Cluster muss nur noch die
  Verbindung zur Identität hergestellt werden.

## Verworfene Alternativen

- **Installation per Terraform in `infra/platform`:** jede Änderung bräuchte einen Lauf von
  `cluster.yml`, und ArgoCD würde nicht genutzt.
- **Client Secret für die Identitäten:** widerspricht dem Ziel „keine Secrets“ (ADR 0001) und
  müsste rotiert werden.
- **HTTP-01:** braucht einen erreichbaren Ingress vor dem ersten Zertifikat, keine Wildcards.
- **AKS-Add-on „App Routing“:** bringt eigenes DNS- und Zertifikats-Management mit, verbirgt aber
  genau das, was das Projekt zeigen soll.

## Konsequenzen

- Es gibt noch keinen Ingress-Controller. external-dns legt erst Einträge an, sobald es einen
  Ingress oder LoadBalancer-Service gibt.
- Die Client-IDs ändern sich nur, wenn `infra/cluster-identity` die Identitäten neu anlegt. Dann
  müssen sie in `gitops/` nachgezogen werden.
- Let's Encrypt begrenzt Zertifikate pro Domain. Getestet wird mit `letsencrypt-staging`.
