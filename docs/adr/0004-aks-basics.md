# ADR 0004: AKS-Grundentscheidungen

- Status: akzeptiert
- Datum: 2026-11-23
- Aktualisiert: 2026-11-23 (Cilium, zwei Node-Pools, Größen und Version entschieden)

## Kontext

clusteryard braucht einen Kubernetes-Cluster für ArgoCD und die Anwendungen. Das Budget liegt
bei 20 USD im Monat, ein dauerhaft laufender Cluster ist damit nicht drin. Der Cluster wird
deshalb bei Bedarf aufgebaut und wieder abgebaut. Alles, was diesen Zyklus überleben muss
(Netzwerk, DNS, Identitäten, Rollen), liegt in eigenen, langlebigen Modulen.

## Entscheidungen

### 1. Cluster bei Bedarf, in einer langlebigen Ressourcengruppe

- Modul `infra/cluster`, State `cluster/terraform.tfstate`, in `ON_DEMAND_MODULES`.
- In Pull Requests wird es geplant, aber nie automatisch angewendet. Auf- und Abbau laufen
  über einen eigenen Workflow mit `workflow_dispatch` (`up`/`down`).
- Der Cluster liegt in `rg-aks` (angelegt in `infra/cluster-identity`). Die Gruppe und alle
  Rollen darauf bleiben bestehen, wenn der Cluster gelöscht wird.

### 2. Netzwerk: Azure CNI Overlay mit Cilium im bestehenden Subnetz

- Nodes in `snet-aks-nodes`, Pod-CIDR, Service-CIDR und DNS-Service-IP aus den Outputs von
  `infra/network` (ADR 0002). Die AKS-Standardwerte werden nie verwendet.
- `network_data_plane = "cilium"` und `network_policy = "cilium"`: eBPF-Datenebene und
  Durchsetzung von Kubernetes-NetworkPolicies. Ohne Network Policy darf jeder Pod jeden
  erreichen; Data Plane und Policy-Engine lassen sich nach dem Anlegen nur mit Aufwand ändern.
- `outbound_type = "loadBalancer"`, kein NAT Gateway.

### 3. Nur benutzerzugewiesene, langlebige Identitäten

- Control Plane: `id-aks-control-plane`. Kubelet: `id-aks-kubelet`.
- Beide aus `infra/cluster-identity`. Der Cluster referenziert sie nur. Begründung in ADR 0006.

### 4. Anmeldung nur über Entra ID, Rechte über Azure RBAC

- `local_account_disabled = true`: kein statisches Admin-Kubeconfig.
- Entra-Integration mit `azure_rbac_enabled = true`: Rechte in Kubernetes kommen aus
  Azure-Rollenzuweisungen (`Azure Kubernetes Service RBAC Cluster Admin` auf `rg-aks` für die
  Apply-Identität und den Administrator, ADR 0006).
- Anmeldung per `kubelogin`: in der Pipeline nach `azure/login`, lokal mit
  `kubelogin convert-kubeconfig -l azurecli`.

### 5. Workload Identity

- `oidc_issuer_enabled = true` und `workload_identity_enabled = true`.
- `infra/cluster` legt die Federated Credentials für cert-manager und external-dns an, mit der
  Issuer-URL des jeweils neuen Clusters.

### 6. Öffentlicher API-Endpunkt (akzeptiertes Risiko)

Der API-Server ist öffentlich erreichbar, ohne IP-Einschränkung. Abgesichert ist er nur durch
die Entra-Anmeldung und Azure RBAC.

### 7. Zwei Node-Pools: System und Apps

| Pool | Modus | VM | Nodes | Läuft dort |
|---|---|---|---|---|
| `system` | System, Taint `CriticalAddonsOnly` | `Standard_B2s` (2 vCPU, 4 GiB) | 1 | `kube-system`, AKS-Add-ons, Cilium |
| `apps` | User | `Standard_B2ms` (2 vCPU, 8 GiB) | 1 | ArgoCD, Ingress, cert-manager, external-dns, Observability, Services |

- Beide Pools im Node-Subnetz, OS-Datenträger 32 GB Managed (Standard wären 128 GB Premium).
- Tags auch an den Pools, damit die VM-Kosten in `rg-aks-nodes` dem Projekt zugeordnet werden.
- Nur die klassische B-Serie hat Quota in `germanywestcentral` (10 vCPU). Die Pools brauchen 4,
  bei Upgrades mit `max_surge = 1` kurzzeitig 6.

### 8. Tarif, Version und Upgrades

- `sku_tier = "Free"`: keine SLA für den Control Plane.
- `kubernetes_version = "1.36"`: nur die Minor-Version, eine hinter der neuesten (1.37).
  Jeder Neuaufbau bekommt den neuesten Patch.
- Keine automatischen Upgrades (`node_os_upgrade_channel = "None"`, kein Upgrade-Kanal).
  Der Cluster lebt nur Stunden; der Neuaufbau ist das Upgrade.

### 9. Demo-Profil als Variablen

Größen, Anzahl, Tarif, Zonen und Version sind Variablen in `infra/cluster/variables.tf`. Die
Standardwerte sind das Demo-Profil. Ein Produktionsprofil wäre nur ein anderer Variablensatz,
etwa `Standard`-Tarif, drei Zonen, je drei Nodes mit `D`-Serie.

### 10. Container-Images aus GitHub Container Registry

Images liegen in GHCR, es gibt keine Azure Container Registry. Die Kubelet-Identität braucht
deshalb kein `AcrPull`.

## Begründung

- Auf- und Abbau bei Bedarf ist der einzige Weg, AKS mit 20 USD im Monat zu betreiben.
  Weil alle Rollen an langlebigen Identitäten und Gruppen hängen, ist ein Neuaufbau eine reine
  Pipeline-Aufgabe ohne lokale Schritte.
- Ohne lokale Konten gibt es kein Kubeconfig mit dauerhaftem Admin-Zugriff, das verloren gehen
  könnte. Zugriff entziehen heißt: Rollenzuweisung löschen.
- GitHub-Runner haben wechselnde IP-Adressen. Autorisierte IP-Bereiche wären kaum zu pflegen.
  Ein privater Cluster bräuchte `az aks command invoke` oder eigene Runner im VNet.
- Ein eigener System-Pool ist der von AKS empfohlene Aufbau: Last der Anwendungen kann
  CoreDNS, Metrics Server und Cilium nicht verdrängen. Gleichzeitig verteilt er den Speicher:
  8 GiB auf einem einzigen Node würden für Plattform, Observability und Services knapp.
- Cilium ist die Data Plane, die Microsoft für neue Cluster empfiehlt, und bringt Network
  Policies ohne zusätzliche Komponente.
- GHCR ist für ein öffentliches Repository kostenlos. Eine ACR kostet ab rund 5 USD im Monat,
  auch ohne laufenden Cluster.

## Verworfene Alternativen

- **Dauerhaft laufender Cluster:** sprengt das Budget.
- **Privater Cluster:** sicherer, braucht aber `az aks command invoke` (langsam, sperrig) oder
  self-hosted Runner im VNet (Kosten, Pflege).
- **Autorisierte IP-Bereiche für den API-Server:** mit den wechselnden IPs der GitHub-Runner
  nicht praktikabel.
- **Lokale Konten und Kubernetes-RBAC statt Azure RBAC:** Rechte stünden in Kubernetes-Objekten,
  die beim Neuaufbau verloren gehen und neu angelegt werden müssten.
- **Ein Node-Pool mit 1 × B2ms:** günstiger (≈ 0,13 statt ≈ 0,19 USD pro Stunde), aber System-
  und Anwendungslast auf einem Node mit 8 GiB, ohne Trennung.
- **2 × B2ms:** mehr Reserve im System-Pool, aber ≈ 0,23 USD pro Stunde (≈ 80 statt ≈ 105
  Cluster-Stunden im Monat). Der System-Pool braucht die 8 GiB nicht.
- **Azure Network Policy Manager oder Calico:** Network Policies ja, aber ohne eBPF-Datenebene;
  Microsoft empfiehlt für neue Cluster Cilium.
- **Azure Container Registry:** feste Kosten und eine zusätzliche Rollenzuweisung, ohne Vorteil
  gegenüber GHCR für dieses Projekt.

## Konsequenzen

- Der API-Server ist im Internet sichtbar. Wer gültige Entra-Anmeldedaten mit passender Rolle
  hat, kann zugreifen. Schwachstellen im API-Server selbst sind nicht durch Netzwerkgrenzen
  abgefangen. Akzeptiert für ein Lernprojekt ohne sensible Daten.
- Ohne laufenden Cluster gibt es keine Workload-Identity-Anmeldung für cert-manager und
  external-dns. Die Federated Credentials werden bei jedem Aufbau neu angelegt.
- Jeder Neuaufbau ändert die OIDC-Issuer-URL und den API-Endpunkt. Nichts außerhalb von
  `infra/cluster` und `infra/platform` darf davon abhängen.
- AKS legt eine eigene Ressourcengruppe für die Nodes an (`MC_…` bzw. `node_resource_group`).
  Sie entsteht und verschwindet mit dem Cluster und wird von AKS verwaltet.

## Kosten

| Posten | USD pro Stunde |
|---|---|
| B2s (System) | 0,048 |
| B2ms (Apps) | 0,096 |
| 2 × OS-Datenträger P4 | 0,016 |
| Standard Load Balancer (geschätzt) | 0,025 |
| Öffentliche IP | 0,005 |
| **Summe** | **≈ 0,19** |

Nach den festen Kosten des Fundaments (rund 1 USD im Monat) bleiben etwa 100 Cluster-Stunden
im Monat. Ein vergessener Cluster kostet rund 140 USD im Monat; der Auf-/Abbau-Workflow
soll ihn deshalb zusätzlich jede Nacht abbauen.
