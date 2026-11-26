# ADR 0006: Rollenvergabe nur lokal, über langlebige Identitäten

- Status: akzeptiert
- Datum: 2026-11-23

## Kontext

Der Cluster und seine Komponenten brauchen Azure-Rollen: AKS auf dem Subnetz, cert-manager und
external-dns auf der DNS-Zone, die Pipeline auf der Kubernetes-API. Der Cluster wird
regelmäßig neu aufgebaut (ADR 0004). Die Pipeline soll dabei keine Rollen vergeben dürfen,
damit sie sich und anderen keine Rechte geben kann (ADR 0001).

Zunächst sah es so aus, als bräuchte die Pipeline `Role Based Access Control Administrator`,
weil die Federated Credentials der Workload Identities an der Issuer-URL des Clusters hängen,
die sich bei jedem Neuaufbau ändert. Das stimmt nicht: Ein Federated Credential ist keine
Rollenzuweisung, sondern eine Unterressource der Managed Identity. `Contributor` darf es anlegen.

## Entscheidungen

### 1. Alles mit Rollenzuweisung ist eine langlebige, benutzerzugewiesene Identität

Systemzugewiesene Identitäten werden nicht verwendet. Der Cluster referenziert die Identitäten
nur. Alle liegen in `rg-aks` und werden in `infra/cluster-identity` angelegt (lokal,
`LOCAL_ONLY_MODULES`).

### 2. Alle Rollenzuweisungen werden lokal angelegt

| Principal | Rolle | Scope | Zweck |
|---|---|---|---|
| `id-aks-control-plane` | Network Contributor | Subnetz `snet-aks-nodes` | AKS verwaltet NICs und Load Balancer |
| `id-aks-control-plane` | Managed Identity Operator | `id-aks-kubelet` | Pflicht bei eigener Kubelet-Identität |
| `id-cert-manager` | DNS Zone Contributor | Zone `k8s.clusteryard.dev` | DNS-01-Challenges |
| `id-external-dns` | DNS Zone Contributor | Zone `k8s.clusteryard.dev` | DNS-Einträge für Ingresses |
| Apply-Identität | Contributor | `rg-aks` | Cluster anlegen und löschen |
| Apply-Identität | Azure Kubernetes Service RBAC Cluster Admin | `rg-aks` | Helm-Installation (ADR 0005) |
| Administrator (Person) | Azure Kubernetes Service RBAC Cluster Admin | `rg-aks` | `kubectl`, Fehlersuche |
| Plan-Identität | Azure Kubernetes Service Cluster User Role | `rg-aks` | Plan im Pull Request bei laufendem Cluster (siehe 5.) |

Die Rollen von `apply` auf `rg-dns` und `rg-network` stehen in `infra/identity` (ADR 0001).

### 3. Die Pipeline legt nur Federated Credentials an

`infra/cluster` legt mit `azurerm_federated_identity_credential` für cert-manager und
external-dns je ein Federated Credential an. Es enthält die Issuer-URL des neuen Clusters und
den Service Account (`system:serviceaccount:<namespace>:<name>`). Dafür reicht `Contributor`
auf `rg-aks`.

### 4. Cluster-Admin-Rechte auf `rg-aks`, als getrennte Zuweisungen

- Scope ist `rg-aks`, nicht das Abonnement und nicht der Cluster selbst. Der Cluster ist beim
  Anlegen der Rolle noch nicht da, und auf dem Abonnement gälte die Rolle für jeden AKS-Cluster.
- Apply-Identität und Administrator bekommen je eine eigene Zuweisung (ein `for_each`), keine
  gemeinsame Entra-Gruppe.

### 5. Plan-Identität darf das Kubeconfig abrufen

Läuft ein Cluster, aktualisiert der Plan im Pull Request `azurerm_kubernetes_cluster`. Der
Provider liest dabei das Kubeconfig (`listClusterUserCredential`), das `Reader` nicht erlaubt.
Ohne die Rolle schlägt jeder Pull Request fehl, solange ein Cluster läuft (403, entdeckt in
PR #11).

`Azure Kubernetes Service Cluster User Role` erlaubt nur diese eine Aktion. Weil lokale Konten
abgeschaltet sind (ADR 0004), enthält das Kubeconfig kein Geheimnis, nur Endpunkt, CA und den
Aufruf von `kubelogin`. Rechte in Kubernetes kommen nur aus Azure RBAC, und die Plan-Identität
hat dort keine Rolle. Sie kann das Kubeconfig abrufen, im Cluster aber nichts tun.

## Begründung

- Eine Rollenzuweisung entsteht so genau einmal und bleibt über alle Neuaufbauten gültig.
  Systemzugewiesene Identitäten bekämen bei jedem Aufbau eine neue Principal-ID.
- Die Pipeline kann keine Rollen vergeben, auch keine eingeschränkten. Das Prinzip aus ADR 0001
  bleibt ohne Ausnahme bestehen.
- `Owner` enthält keine Rechte auf die Kubernetes-API (Data Actions). Bei
  `local_account_disabled = true` wäre auch der Administrator ohne eigene Zuweisung ausgesperrt.
- Getrennte Zuweisungen zeigen jeden Principal im Plan. Eine Gruppe ließe sich außerhalb von
  Terraform erweitern, ohne dass ein Plan es zeigt.

## Verworfene Alternativen

- **`Role Based Access Control Administrator` für `apply`, mit Bedingungen** (nur bestimmte
  Rollen, nur an `ServicePrincipal`): funktioniert, gibt der Pipeline aber ohne Not das Recht,
  Rollen zu vergeben. Bedingungen sind fehleranfällig. Wer vergisst, privilegierte Rollen
  auszuschließen, erlaubt der Pipeline faktisch `Owner`.
- **Systemzugewiesene Identitäten:** neue Principal-ID bei jedem Neuaufbau, die Rollen müssten
  jedes Mal neu vergeben werden, also von der Pipeline.
- **Cluster-Admin auf dem Abonnement:** gälte für jeden AKS-Cluster im Abonnement, auch für
  fremde Projekte.
- **Entra-Gruppe für Cluster-Admins:** ein weiteres Objekt, und die Mitgliedschaft wäre in
  Terraform nicht sichtbar.

## Konsequenzen

- Jede neue Komponente mit Azure-Zugriff (z. B. external-secrets) braucht eine lokale Änderung
  an `infra/cluster-identity`: neue Identität, neue Rollenzuweisung. Die Pipeline ergänzt nur
  das Federated Credential in `infra/cluster`.
- `infra/cluster-identity` braucht die States von `identity`, `dns` und `network`. Es wird nach
  diesen angewendet.
- Der Abbau des Clusters löscht die Federated Credentials mit. Die Identitäten und ihre Rollen
  bleiben bestehen.
- Die Object-ID des Administrators steht in `terraform.tfvars` (nicht im Repository).
