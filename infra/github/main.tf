locals {
  # Job name of the plan job in .github/workflows/terraform.yml.
  required_check = "terraform-plan"

  # App ID of GitHub Actions. Pins the required check to Actions, so a commit
  # status with the same name from somewhere else cannot satisfy it.
  github_actions_app_id = 15368
}

# ---------------------------------------------------------------------------
# Repository settings: squash merges only, branches deleted after merge.
# ---------------------------------------------------------------------------

import {
  to = github_repository.this
  id = var.github_repo
}

resource "github_repository" "this" {
  name        = var.github_repo
  description = "Production grade AKS Platform"
  visibility  = "public"

  # Set explicitly: left unset, the provider would clear them on update.
  has_issues   = true
  has_projects = true

  allow_merge_commit          = false
  allow_rebase_merge          = false
  allow_squash_merge          = true
  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"
  delete_branch_on_merge      = true
  allow_update_branch         = true # "Update branch" button, needed with strict status checks

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true # Dependabot alerts
}

# ---------------------------------------------------------------------------
# Ruleset for main: changes only through pull requests with a green plan.
# ---------------------------------------------------------------------------

resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = "active"

  # No bypass actors: the rules apply to the repository admin as well.

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true

    pull_request {
      # Single maintainer: GitHub does not allow approving your own pull
      # request, so a required approval would block every merge. The plan
      # check and the prod environment approval are the gates instead.
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = true
      allowed_merge_methods             = ["squash"]
    }

    required_status_checks {
      # The branch must be up to date with main, so the plan shown in the pull
      # request is the plan that runs after the merge.
      strict_required_status_checks_policy = true

      required_check {
        context        = local.required_check
        integration_id = local.github_actions_app_id
      }
    }
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions: only pinned, known actions; read-only token by default.
# ---------------------------------------------------------------------------

resource "github_actions_repository_permissions" "this" {
  repository           = github_repository.this.name
  enabled              = true
  allowed_actions      = "selected"
  sha_pinning_required = true

  allowed_actions_config {
    github_owned_allowed = true # actions/checkout
    verified_allowed     = false
    patterns_allowed = [
      "azure/login@*",
      "hashicorp/setup-terraform@*",
    ]
  }
}

resource "github_workflow_repository_permissions" "this" {
  repository                       = github_repository.this.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

# ---------------------------------------------------------------------------
# prod environment: gates the apply job, only from main, with approval.
# The apply identity trusts exactly this environment (ADR 0001).
# ---------------------------------------------------------------------------

import {
  to = github_repository_environment.prod
  id = "${var.github_repo}:prod"
}

resource "github_repository_environment" "prod" {
  repository          = github_repository.this.name
  environment         = "prod"
  can_admins_bypass   = false
  prevent_self_review = false # single maintainer, see ruleset above

  reviewers {
    users = var.prod_reviewer_ids
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

import {
  to = github_repository_environment_deployment_policy.prod_main
  id = "${var.github_repo}:prod:67250858"
}

resource "github_repository_environment_deployment_policy" "prod_main" {
  repository     = github_repository.this.name
  environment    = github_repository_environment.prod.environment
  branch_pattern = "main"
}
