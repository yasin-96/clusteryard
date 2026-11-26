# gitops/apps

The root Application (`infra/platform`, ADR 0005) syncs this directory
recursively. Each YAML file here is an ArgoCD `Application` for one component,
for example cert-manager or external-dns.

Only `.yaml`, `.yml` and `.json` files are applied; this README is ignored.
