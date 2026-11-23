# ADR 0003: Delegierte DNS-Zone `k8s.clusteryard.dev` in Azure DNS

- Status: akzeptiert
- Datum: 2026-11-19 (nachträglich dokumentiert am 2026-11-23)

## Kontext

Die Domain `clusteryard.dev` wird bei Cloudflare verwaltet. Der Cluster braucht DNS-Namen für
Ingresses (external-dns) und TLS-Zertifikate über DNS-01-Challenges (cert-manager). Beide sollen
sich per Workload Identity anmelden, ohne API-Token oder Secrets.

## Entscheidungen

### 1. Subzone in Azure DNS, delegiert aus Cloudflare

- Azure-DNS-Zone `k8s.clusteryard.dev` in `infra/dns`, eigene Ressourcengruppe `rg-dns`
  (angelegt in `infra/identity`, ADR 0001), State `dns/terraform.tfstate`.
- In Cloudflare stehen vier `NS`-Einträge für `k8s`, die auf die Azure-Nameserver zeigen
  (`ns1-02.azure-dns.com`, `ns2-02.azure-dns.net`, `ns3-02.azure-dns.org`,
  `ns4-02.azure-dns.info`). NS-Einträge werden von Cloudflare nie über den Proxy geleitet
  („DNS only“).
- Die Hauptdomain `clusteryard.dev` bleibt bei Cloudflare.

### 2. Die Zone ist langlebig und geschützt

Die Zone steht in `AUTO_APPLY_MODULES` und überlebt den Cluster-Abbau. Sie hat
`prevent_destroy`.

## Begründung

- external-dns und cert-manager können sich bei Azure DNS per Workload Identity anmelden
  (`DNS Zone Contributor`, ADR 0006). Für Cloudflare bräuchten sie einen API-Token als Secret.
- Die Delegation einer Subzone trennt sauber: Der Cluster kann nur unter `k8s.clusteryard.dev`
  Einträge anlegen, nie an der Hauptdomain.
- Eine Zone kostet rund 0,50 USD im Monat und passt ins Budget.
- Wird die Zone neu angelegt, kann Azure andere Nameserver vergeben. Die Delegation in Cloudflare
  wäre dann still kaputt. Deshalb `prevent_destroy` und ein dauerhaftes Modul.

## Verworfene Alternativen

- **Alles in Cloudflare (external-dns und cert-manager mit Cloudflare-Provider):** braucht
  einen API-Token als Kubernetes-Secret, das rotiert werden muss. Ein Token mit Rechten auf die
  ganze Zone `clusteryard.dev` wäre breiter als nötig.
- **Ganze Domain zu Azure DNS umziehen:** Cloudflare-Funktionen (Proxy, Weiterleitungen) für
  die Hauptdomain gingen verloren, und Fehler im Cluster könnten die ganze Domain treffen.
- **Zone im Cluster-Modul:** würde bei jedem Abbau gelöscht, mit neuen Nameservern beim
  Neuaufbau.

## Konsequenzen

- Die NS-Einträge in Cloudflare werden von Hand gepflegt, nicht von Terraform. Ändern sich die
  Azure-Nameserver, muss Cloudflare nachgezogen werden. Prüfen mit
  `dig NS k8s.clusteryard.dev @cass.ns.cloudflare.com +noall +authority`.
- Für den Namen `k8s` selbst darf es in Cloudflare keine anderen Einträge geben. Einträge wie
  `app.k8s.clusteryard.dev` entstehen in Azure.
- Die Ausgabe `zone_id` von `infra/dns` ist der Scope für `DNS Zone Contributor` in
  `infra/cluster-identity`.
