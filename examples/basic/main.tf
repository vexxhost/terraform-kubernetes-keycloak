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
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
  }
}

resource "random_password" "root_password" {
  length = 32
}

resource "kubernetes_namespace" "namespace" {
  metadata {
    name = "infra"
  }
}

module "mariadb" {
  #checkov:skip=CKV_TF_1

  source  = "vexxhost/mariadb/kubernetes"
  version = "0.1.1"

  name          = "mariadb"
  namespace     = kubernetes_namespace.namespace.metadata[0].name
  root_password = random_password.root_password.result
}

module "database" {
  #checkov:skip=CKV_TF_1

  source  = "vexxhost/mysql-database/kubernetes"
  version = "0.1.0"

  depends_on = [
    module.mariadb
  ]

  hostname                  = "mariadb"
  job_namespace             = kubernetes_namespace.namespace.metadata[0].name
  root_password_secret_name = "mariadb"

  name = "keycloak"
}

resource "random_password" "keycloak_database_password" {
  length = 32
}

module "user" {
  #checkov:skip=CKV_TF_1

  source  = "vexxhost/mysql-user/kubernetes"
  version = "0.1.0"

  depends_on = [
    module.mariadb
  ]

  hostname                  = "mariadb"
  job_namespace             = kubernetes_namespace.namespace.metadata[0].name
  root_password_secret_name = "mariadb"

  username = "keycloak"
  password = random_password.keycloak_database_password.result
}

module "grant" {
  #checkov:skip=CKV_TF_1

  source  = "vexxhost/mysql-grant/kubernetes"
  version = "0.1.0"

  depends_on = [
    module.database,
    module.user
  ]

  hostname                  = "mariadb"
  job_namespace             = kubernetes_namespace.namespace.metadata[0].name
  root_password_secret_name = "mariadb"

  database = "keycloak"
  username = "keycloak"
}

resource "kubernetes_namespace" "auth-system" {
  metadata {
    name = "auth-system"
  }
}

resource "random_password" "keycloak_admin_password" {
  length = 32
}

module "keycloak" {
  source = "../../"

  depends_on = [
    module.grant
  ]

  namespace         = kubernetes_namespace.auth-system.metadata[0].name
  hostname          = "keycloak.foo.bar"
  database          = "mariadb"
  database_url      = "jdbc:mariadb://mariadb.infra:3306/keycloak"
  database_password = random_password.keycloak_database_password.result
  admin_password    = random_password.keycloak_admin_password.result
}
