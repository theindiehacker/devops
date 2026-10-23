terraform {
  # CI（style.yml の terraform job）は 1.16.0 で validate / test する
  required_version = ">= 1.16.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}
