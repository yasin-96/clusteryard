# ADR 0002: Netzwerk für den AKS-Cluster

- Status: akzeptiert
- Datum: 2026-11-20

## Kontext

Der AKS-Cluster wird regelmäßig abgebaut und neu angelegt (`ON_DEMAND_MODULES`), um Kosten zu
sparen (Budget: 20 USD im Monat). Das Netzwerk soll dabei stabil bleiben, damit Subnetz-IDs,
Adressbereiche und spätere Abhängigkeiten (z. B. Private Endpoints, Peerings) nicht jedes Mal
neu entstehen. Gleichzeitig soll das Netzwerk nichts kosten, solange kein Cluster läuft.

## Entscheidungen

### 1. Eigenes Modul `infra/network` mit eigener Ressourcengruppe

- Ressourcengruppe `rg-network`, State `network/terraform.tfstate`, Region `germanywestcentral`.
- Das Modul überlebt den Cluster-Abbau und steht in `AUTO_APPLY_MODULES` (nach `infra/dns`):
  die Pipeline wendet es nach Merge und Freigabe in `prod` an.
- Der Cluster bekommt das Subnetz später über `aks_nodes_subnet_id` (Output des Moduls).

### 2. Adressplan

| Bereich | CIDR | Zweck |
|---|---|---|
| VNet `vnet-clusteryard` | `10.0.0.0/16` | gesamter Adressraum, Platz für weitere Subnetze |
| Subnetz `snet-aks-nodes` | `10.0.0.0/24` | nur die AKS-Nodes (251 nutzbare IPs) |
| Pod-CIDR (Overlay) | außerhalb des VNets, z. B. `192.168.0.0/16` | wird im Cluster-Modul gesetzt |
| Service-CIDR | außerhalb des VNets, z. B. `172.16.0.0/16` | wird im Cluster-Modul gesetzt |

Weitere Subnetze (z. B. Ingress, Private Endpoints) bekommen die nächsten freien `/24` aus
`10.0.0.0/16`.

### 3. Azure CNI Overlay

Pods bekommen ihre IPs aus einem eigenen Overlay-Bereich, nicht aus dem Node-Subnetz.
Darum reicht ein `/24` für die Nodes, und die Zahl der Pods hängt nicht an der Subnetzgröße.

### 4. Kein Default Outbound Access

Das Node-Subnetz hat `default_outbound_access_enabled = false`. Ausgehender Verkehr läuft
explizit über den Load Balancer von AKS (`outbound_type = "loadBalancer"`). Azure schaltet den
impliziten Internetzugang für neue Subnetze ohnehin ab; so ist das Verhalten von Anfang an
festgelegt und nicht vom Erstellungsdatum abhängig.

### 5. `prevent_destroy` statt Management Lock

Ressourcengruppe und VNet haben `lifecycle { prevent_destroy = true }`, wie State-Speicher
(Bootstrap) und DNS-Zone. Es gibt **keinen** `azurerm_management_lock`.

## Begründung

- VNet, Subnetz und Ressourcengruppe kosten nichts. Sie dauerhaft stehen zu lassen ist gratis,
  spart Zeit beim Cluster-Aufbau und hält IDs stabil.
- Overlay ist die von Microsoft empfohlene Variante für neue Cluster und braucht kaum Adressraum
  im VNet.
- Ein Management Lock bräuchte `Owner` oder `User Access Administrator`. Die Apply-Identität hat
  nur `Contributor` (ADR 0001), das Apply in der Pipeline würde also scheitern.

## Verworfene Alternativen

- **Netzwerk im Cluster-Modul:** würde bei jedem Abbau mit gelöscht und neu angelegt.
- **Azure CNI ohne Overlay (Pod-IPs aus dem Subnetz):** jeder Pod verbraucht eine VNet-IP, das
  Subnetz müsste deutlich größer sein und vorausgeplant werden.
- **kubenet:** wird von Microsoft abgekündigt.
- **NAT Gateway für ausgehenden Verkehr:** feste Kosten von rund 30 USD im Monat plus Traffic,
  auch ohne laufenden Cluster. Sprengt das Budget. Der Load Balancer von AKS reicht für ein
  Lernprojekt.
- **Management Lock (`CanNotDelete`):** schützt auch vor Löschen im Portal, scheitert aber an
  den Rechten der Pipeline (siehe Begründung).

## Konsequenzen

- **Pod- und Service-CIDR dürfen sich nicht mit `10.0.0.0/16` überschneiden.** Der AKS-Standard
  für das Service-CIDR ist ebenfalls `10.0.0.0/16`. Das Cluster-Modul muss `service_cidr`,
  `dns_service_ip` und `pod_cidr` deshalb **explizit** setzen, sonst schlägt das Anlegen fehl.
- `prevent_destroy` schützt nur vor Terraform. Löschen im Portal oder mit `az` ist weiterhin
  möglich. Ein Lock kann bei Bedarf einmalig lokal angelegt werden (z. B. mit `az lock create`).
- `prevent_destroy` blockiert auch Änderungen, die ein Neuanlegen erzwingen (z. B. ein anderer
  Adressraum). Solche Änderungen müssen bewusst erfolgen: Schutz kurz entfernen, anwenden,
  Schutz wieder setzen.
- VMs ohne AKS-Load-Balancer in diesem Subnetz haben keinen Internetzugang.
- Die Identität des Clusters braucht später `Network Contributor` auf dem Subnetz. Das ist eine
  Rollenzuweisung und hängt an der offenen Frage aus ADR 0001 (Rechte von `apply` für
  Rollenzuweisungen).
