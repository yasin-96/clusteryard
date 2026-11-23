# ADR 0004: AKS-Grundentscheidungen

- Status: akzeptiert (Abschnitt „Offen“ wird mit `infra/cluster` entschieden)
- Datum: 2026-11-23

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

### 2. Netzwerk: Azure CNI Overlay im bestehenden Subnetz

- Nodes in `snet-aks-nodes`, Pod-CIDR, Service-CIDR und DNS-Service-IP aus den Outputs von
  `infra/network` (ADR 0002). Die AKS-Standardwerte werden nie verwendet.
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

### 7. Container-Images aus GitHub Container Registry

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

## Offen

Wird beim Schreiben von `infra/cluster` entschieden und hier nachgetragen:

- Node-Größe und Anzahl (Vorschlag: ein System-Node-Pool mit einer kleinen B-Serie-VM)
- Tarif des Control Plane (Vorschlag: `Free`)
- Kubernetes-Version und automatische Upgrades
- Name der Node-Ressourcengruppe
