terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13.0"
    }
  }
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "Target namespace for Online Boutique"
  type        = string
  default     = "default"
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# 1. Traefik v3 Helm Deployment with Gateway API Provider
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  namespace        = "traefik"
  create_namespace = true
  version          = "34.4.1"

  set {
    name  = "providers.kubernetesGateway.enabled"
    value = "true"
  }

  set {
    name  = "gatewayClass.enabled"
    value = "true"
  }

  set {
    name  = "gateway.enabled"
    value = "true"
  }

  set {
    name  = "service.type"
    value = "NodePort"
  }

  set {
    name  = "ports.web.nodePort"
    value = "30080"
  }
}

output "traefik_status" {
  value       = helm_release.traefik.status
  description = "Status of the Traefik Gateway deployment"
}
