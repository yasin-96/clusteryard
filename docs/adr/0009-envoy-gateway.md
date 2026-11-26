# ADR 0009: Envoy Gateway und Gateway API statt Ingress

- Status: akzeptiert
- Datum: 2026-11-26

## Kontext

Dienste sollen von außen unter `*.k8s.clusteryard.dev` per HTTPS erreichbar sein. DNS und
Zertifikate liefern external-dns und cert-manager (ADR 0008). Es fehlt der Eintrittspunkt in
den Cluster.

- Der Community-Controller **ingress-nginx** ist seit März 2026 eingestellt: keine Releases,
  keine Sicherheitsupdates mehr.
- Die NGINX-Variante des AKS-Add-ons **App Routing** verliert nach November 2026 den Support.
  Microsoft empfiehlt Gateway API.

## Entscheidungen

### 1. Gateway API mit Envoy Gateway

- Envoy Gateway (CNCF, Chart `gateway-helm` v1.9.3) als ArgoCD-Application `envoy-gateway`
  in `envoy-gateway-system`. Das Chart bringt die Gateway-API-CRDs mit.
- Das Chart gibt es nur als OCI-Artefakt. ArgoCD kennt das Repository `docker.io/envoyproxy`
  als OCI-Helm-Repository aus seinen Werten in `infra/platform` (öffentlich, ohne Zugangsdaten).

### 2. Ein öffentlicher Gateway für alle Dienste

Application `gateway` mit den Manifesten aus `gitops/platform/gateway`:

| Ressource | Zweck |
|---|---|
| GatewayClass `envoy` | verbindet Gateways mit Envoy Gateway |
| Gateway `public` (Namespace `gateway`) | Listener `http` (80) und `https` (443) für `*.k8s.clusteryard.dev` |
| Certificate `wildcard-k8s-clusteryard-dev` | Wildcard-Zertifikat von `letsencrypt-prod`, DNS-01 |
| HTTPRoute `https-redirect` | leitet jede HTTP-Anfrage per 301 auf HTTPS um |

- Envoy Gateway legt für den Gateway einen Envoy-Proxy und einen Service vom Typ
  `LoadBalancer` an, also eine öffentliche IP am AKS-Load-Balancer.
- TLS endet am Gateway. Dienste brauchen kein eigenes Zertifikat.
- Routen dürfen sich nur aus Namespaces mit dem Label `clusteryard.dev/gateway-access=true`
  an den HTTPS-Listener hängen. Ein beliebiger Namespace kann sich so nicht unter der Domain
  veröffentlichen.

### 3. DNS über die HTTPRoutes

external-dns bekommt die Quelle `gateway-httproute` und legt für jeden Hostnamen einer Route
einen Eintrag auf die Adresse ihres Gateways an. Die Umleitungsroute hat keinen eigenen
Hostnamen und erbt den des Listeners. Dadurch entsteht zusätzlich der Wildcard-Eintrag
`*.k8s.clusteryard.dev`. Unbekannte Namen landen damit am Gateway und bekommen eine 404, mit
gültigem Zertifikat.

## Begründung

- Gateway API ist der Nachfolger von Ingress. Es trennt die Rollen: Plattform (GatewayClass,
  Gateway, Zertifikat) und Dienste (HTTPRoute im eigenen Namespace).
- Envoy Gateway implementiert Gateway API direkt, ohne Annotations als Erweiterungssprache, und
  läuft wie alles andere über ArgoCD.
- Ein Wildcard-Zertifikat am Gateway hält die Dienste frei von TLS und spart Zertifikate bei
  Let's Encrypt.

## Verworfene Alternativen

- **ingress-nginx:** eingestellt, keine Sicherheitsupdates.
- **AKS App Routing mit Istio:** verwaltet, aber `istiod` belegt Ressourcen auf dem einzigen
  Apps-Node, und das Add-on verbirgt, was das Projekt zeigen soll.
- **Traefik:** unterstützt Ingress und Gateway API, wäre der kleinste Umstieg. Gateway API ist
  bei Envoy Gateway aber die einzige Schnittstelle, nicht eine von mehreren.
- **Application Gateway for Containers:** eigene Azure-Ressource mit festen Kosten pro Stunde,
  passt nicht ins Budget.
- **Zertifikat pro Dienst:** mehr Zertifikate, mehr Rate-Limit-Verbrauch, kein Vorteil hier.

## Konsequenzen

- Let's Encrypt erlaubt 5 Zertifikate pro identischem Namenssatz in 7 Tagen. Jeder Neuaufbau
  holt ein neues Wildcard-Zertifikat, weil das Secret mit dem Cluster verschwindet. Bei mehr als
  etwa 5 Aufbauten pro Woche muss das Certificate vorübergehend auf `letsencrypt-staging`.
- Eine zweite öffentliche IP (≈ 0,005 USD pro Stunde, ADR 0004).
- Ein Dienst braucht künftig: Namespace mit Label `clusteryard.dev/gateway-access=true`, ein
  HTTPRoute mit `parentRefs: public` (Namespace `gateway`, Listener `https`) und seinen
  Hostnamen.
- Die Application `gateway` braucht die CRDs von Envoy Gateway und cert-manager. Bis sie da
  sind, schlägt der Sync fehl und wird wiederholt.
- Bestätigt beim ersten Aufbau (2026-11-26): Der Health Probe des Azure-Load-Balancers erkennt
  den Envoy-Proxy ohne zusätzliche Service-Annotations als gesund. Das Wildcard-Zertifikat war
  nach weniger als einer Minute ausgestellt.
