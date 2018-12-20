# Configure the GitHub Provider
provider "github" {
  token        = "${var.github_access_token}"
  organization = "${var.github_organization}"
}

resource "github_repository" "monorepo" {
  name        = "monorepo"
  description = "Monorepo for muvin.in ."

  has_issues = true
  license_template = "mit"
  allow_merge_commit = true
  allow_squash_merge = true
  allow_rebase_merge = true
  auto_init = true
}
