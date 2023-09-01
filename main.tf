# Copyright (c) 2023 VEXXHOST, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.23.0"
    }
  }
}

locals {
  labels = merge(var.labels, {
    "app.kubernetes.io/instance"   = var.name
    "app.kubernetes.io/managed-by" = "terraform-kubernetes-keycloak"
  })
}

resource "kubernetes_service_account" "service_account" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }
}

resource "kubernetes_secret" "config" {
  metadata {
    name      = "${var.name}-config"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    JAVA_OPTS_APPEND          = "-Djgroups.dns.query=${kubernetes_service.infinispan.metadata[0].name}.${kubernetes_service.infinispan.metadata[0].namespace}.svc"
    KC_CACHE_STACK            = "kubernetes"
    KC_DB                     = var.database
    KC_DB_URL                 = var.database_url
    KC_DB_USERNAME            = "keycloak"
    KC_DB_PASSWORD            = var.database_password
    KC_TRANSACTION_XA_ENABLED = "false"
    KC_HOSTNAME               = var.hostname
    KC_HEALTH_ENABLED         = "true"
    KC_PROXY                  = "edge"
    KEYCLOAK_ADMIN            = "admin"
    KEYCLOAK_ADMIN_PASSWORD   = var.admin_password
  }
}

resource "kubernetes_service" "http" {
  metadata {
    name      = "${var.name}-http"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    selector = local.labels

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_service" "infinispan" {
  metadata {
    name      = "${var.name}-infinispan"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    cluster_ip                  = "None"
    selector                    = local.labels
    publish_not_ready_addresses = true

    port {
      name        = "infinispan"
      port        = 7800
      target_port = "infinispan"
    }
  }
}

resource "kubernetes_stateful_set" "keycloak" {
  #ts:skip=AC_K8S_0064 https://github.com/tenable/terrascan/issues/1610

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas              = 1
    pod_management_policy = "Parallel"

    service_name = kubernetes_service.http.metadata[0].name

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
        annotations = {
          "checksum/config" = sha256(jsonencode(kubernetes_secret.config.data))
        }
      }

      spec {
        service_account_name = kubernetes_service_account.service_account.metadata[0].name

        security_context {
          fs_group = 1001
        }

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_labels = local.labels
                }
              }
            }
          }
        }

        container {
          name  = "keycloak"
          image = var.image

          command = [
            "/opt/keycloak/bin/kc.sh",
            "start",
          ]

          security_context {
            run_as_non_root = true
            run_as_user     = 1001
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.config.metadata[0].name
            }
          }

          port {
            name           = kubernetes_service.http.spec[0].port[0].name
            container_port = 8080
            protocol       = kubernetes_service.infinispan.spec[0].port[0].protocol
          }

          port {
            name           = kubernetes_service.infinispan.spec[0].port[0].name
            container_port = 7800
            protocol       = kubernetes_service.infinispan.spec[0].port[0].protocol
          }

          liveness_probe {
            initial_delay_seconds = 300
            period_seconds        = 1
            timeout_seconds       = 5
            failure_threshold     = 3
            success_threshold     = 1

            http_get {
              path = "/health/live"
              port = kubernetes_service.http.spec[0].port[0].name
            }
          }

          readiness_probe {
            initial_delay_seconds = 60
            period_seconds        = 10
            timeout_seconds       = 1
            failure_threshold     = 6
            success_threshold     = 1

            http_get {
              path = "/health/ready"
              port = kubernetes_service.http.spec[0].port[0].name
            }
          }
        }
      }
    }
  }
}
