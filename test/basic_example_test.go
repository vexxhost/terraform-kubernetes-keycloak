// Copyright (c) 2023 VEXXHOST, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may
// not use this file except in compliance with the License. You may obtain
// a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations
// under the License.

package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/vexxhost/terratest-toolkit/kind"
)

func TestBasicExample(t *testing.T) {
	cluster := kind.NewCluster(t)

	cluster.Create()
	defer cluster.Delete()

	options := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../examples/basic",
		EnvVars:      cluster.EnvVars(),
	})
	defer terraform.Destroy(t, options)

	terraform.InitAndApply(t, options)
}
