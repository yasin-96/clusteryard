# gitops/apps

The root Application (`infra/platform`, ADR 0005) syncs this directory
recursively. Each YAML file here is an ArgoCD `Application` for one component.
Only `.yaml`, `.yml` and `.json` files are applied; this README is ignored.

| Application | What | ADR |
|---|---|---|
| `cert-manager` | TLS certificates (Let's Encrypt, DNS-01 in Azure DNS) | 0008 |
| `cert-manager-issuers` | ClusterIssuers `letsencrypt-staging`, `letsencrypt-prod` | 0008 |
| `external-dns` | DNS records in `k8s.clusteryard.dev` for ingresses and services | 0008 |

Plain manifests that belong to a component (not Applications) live in
`gitops/platform/<name>` and are referenced from the Application here.
