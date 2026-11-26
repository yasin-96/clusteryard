# ArgoCD and the root Application. Everything else (cert-manager, external-dns,
# the services) is managed by ArgoCD from gitops/apps (ADR 0005).

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  values = [file("${path.module}/values/argocd.yaml")]

  wait    = true
  timeout = 600
}

# Separate release: the Application CRD comes with the argo-cd chart and must
# exist before this one is installed (and is destroyed after it).
resource "helm_release" "root_app" {
  name       = "argocd-root"
  namespace  = helm_release.argocd.namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace = helm_release.argocd.namespace
        project   = "default"
        # No resources-finalizer: removing the root Application must not
        # cascade-delete the apps. On teardown the cluster goes away anyway.
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = var.gitops_apps_path
          directory      = { recurse = true }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = helm_release.argocd.namespace
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
