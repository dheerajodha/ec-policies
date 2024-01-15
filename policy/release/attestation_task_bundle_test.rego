package policy.release.attestation_task_bundle_test

import future.keywords.in

import data.lib
import data.lib.tkn_test
import data.lib_test
import data.policy.release.attestation_task_bundle
import future.keywords.if

mock_data(task) := {"statement": {"predicate": {
	"buildConfig": {"tasks": [task]},
	"buildType": lib.tekton_pipeline_run,
}}}

test_bundle_not_exists if {
	name := "my-task"
	attestations := [
		mock_data({
			"name": name,
			"ref": {"name": "my-task"},
		}),
		lib_test.mock_slsav1_attestation_with_tasks([tkn_test.slsav1_task("my-task")]),
	]

	expected_msg := "Pipeline task 'my-task' does not contain a bundle reference"
	lib.assert_equal_results(attestation_task_bundle.deny, {{
		"code": "attestation_task_bundle.tasks_defined_in_bundle",
		"msg": expected_msg,
	}}) with input.attestations as attestations with data["task-bundles"] as task_bundles

	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as attestations
}

test_bundle_not_exists_empty_string if {
	name := "my-task"
	image := ""

	attestations := [
		mock_data({
			"name": name,
			"ref": {"name": "my-task", "bundle": image},
		}),
		lib_test.mock_slsav1_attestation_with_tasks([tkn_test.slsav1_task_bundle("my-task", image)]),
	]

	expected_msg := sprintf("Pipeline task '%s' uses an empty bundle image reference", [name])
	lib.assert_equal_results(attestation_task_bundle.deny, {{
		"code": "attestation_task_bundle.task_ref_bundles_not_empty",
		"msg": expected_msg,
	}}) with input.attestations as attestations with data["task-bundles"] as task_bundles

	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as attestations
}

test_bundle_unpinned if {
	name := "my-task"
	image := "reg.com/repo:latest"
	attestations := [
		mock_data({
			"name": name,
			"ref": {
				"name": "my-task",
				"bundle": image,
			},
		}),
		lib_test.mock_slsav1_attestation_with_tasks([tkn_test.slsav1_task_bundle("my-task", image)]),
	]

	expected_msg := sprintf("Pipeline task '%s' uses an unpinned task bundle reference '%s'", [name, image])
	lib.assert_equal_results(attestation_task_bundle.warn, {{
		"code": "attestation_task_bundle.task_ref_bundles_pinned",
		"msg": expected_msg,
	}}) with input.attestations as attestations with data["task-bundles"] as []
}

test_bundle_reference_valid if {
	name := "my-task"
	image := "reg.com/repo:latest@sha256:abc"
	attestations := [
		mock_data({
			"name": name,
			"ref": {
				"name": "my-task",
				"bundle": image,
			},
		}),
		lib_test.mock_slsav1_attestation_with_tasks([tkn_test.slsav1_task_bundle("my-task", image)]),
	]

	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as attestations
		with data["task-bundles"] as task_bundles

	lib.assert_empty(attestation_task_bundle.deny) with input.attestations as attestations
		with data["task-bundles"] as task_bundles
}

test_bundle_reference_digest_doesnt_match if {
	name := "my-task"
	image := "reg.com/repo:latest@sha256:xyz"
	attestations := [
		mock_data({
			"name": name,
			"ref": {
				"name": "my-task",
				"bundle": image,
			},
		}),
		lib_test.mock_slsav1_attestation_with_tasks([tkn_test.slsav1_task_bundle("my-task", image)]),
	]

	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as attestations
		with data["task-bundles"] as task_bundles

	lib.assert_equal_results(attestation_task_bundle.deny, {{
		"code": "attestation_task_bundle.task_ref_bundles_acceptable",
		"msg": "Pipeline task 'my-task' uses an unacceptable task bundle 'reg.com/repo:latest@sha256:xyz'",
	}}) with input.attestations as attestations
		with data["task-bundles"] as task_bundles
}

test_bundle_reference_repo_not_present if {
	name := "my-task"
	image := "reg.com/super-custom-repo@sha256:abc"
	attestations := [
		mock_data({
			"name": name,
			"ref": {
				"name": "my-task",
				"bundle": image,
			},
		}),
		lib_test.mock_slsav1_attestation_with_tasks([tkn_test.slsav1_task_bundle("my-task", image)]),
	]

	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as attestations
		with data["task-bundles"] as task_bundles

	lib.assert_equal_results(attestation_task_bundle.deny, {{
		"code": "attestation_task_bundle.task_ref_bundles_acceptable",
		"msg": "Pipeline task 'my-task' uses an unacceptable task bundle 'reg.com/super-custom-repo@sha256:abc'",
	}}) with input.attestations as attestations
		with data["task-bundles"] as task_bundles
}

# All good when the most recent bundle is used.
test_acceptable_bundle_up_to_date if {
	image := "reg.com/repo@sha256:abc"
	attestations := [
		lib_test.mock_slsav02_attestation_bundles([image]),
		lib_test.mock_slsav1_attestation_with_tasks([tkn_test.slsav1_task_bundle("my-task", image)]),
	]

	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as attestations
		with data["task-bundles"] as task_bundles

	lib.assert_empty(attestation_task_bundle.deny) with input.attestations as attestations
		with data["task-bundles"] as task_bundles
}

# Warn about out of date bundles that are still acceptable.
test_acceptable_bundle_out_of_date_past if {
	images := ["reg.com/repo@sha256:bcd"]
	attestations := [
		lib_test.mock_slsav02_attestation_bundles(images),
		lib_test.mock_slsav1_attestation_bundles(images, "task-run-0"),
	]

	lib.assert_equal_results(attestation_task_bundle.warn, {{
		"code": "attestation_task_bundle.task_ref_bundles_current",
		"msg": "Pipeline task 'task-run-0' uses an out of date task bundle 'reg.com/repo@sha256:bcd'",
	}}) with input.attestations as attestations
		with data["task-bundles"] as task_bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2022-03-12T00:00:00Z")

	lib.assert_empty(attestation_task_bundle.deny) with input.attestations as attestations
		with data["task-bundles"] as task_bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2022-03-12T00:00:00Z")
}

# Deny bundles that are no longer active.
test_acceptable_bundle_expired if {
	image := ["reg.com/repo@sha256:def"]
	attestations := [
		lib_test.mock_slsav02_attestation_bundles(image),
		lib_test.mock_slsav1_attestation_bundles(image, "task-run-0"),
	]
	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as attestations
		with data["task-bundles"] as task_bundles

	lib.assert_equal_results(attestation_task_bundle.deny, {{
		"code": "attestation_task_bundle.task_ref_bundles_acceptable",
		"msg": "Pipeline task 'task-run-0' uses an unacceptable task bundle 'reg.com/repo@sha256:def'",
	}}) with input.attestations as attestations
		with data["task-bundles"] as task_bundles
}

test_acceptable_bundles_provided if {
	expected := {{
		"code": "attestation_task_bundle.acceptable_bundles_provided",
		"msg": "Missing required task-bundles data",
	}}
	lib.assert_equal_results(expected, attestation_task_bundle.deny) with data["task-bundles"] as []
}

test_warn_cases if {
	bundles := {"q.io/r//task-buildah": [
		{
			"digest": "sha256:c37e54",
			"effective_on": "2023-11-06T00:00:00Z",
			"tag": "0.1",
		},
		{
			"digest": "sha256:97f216",
			"effective_on": "2023-10-25T00:00:00Z",
			"tag": "0.1",
		},
		{
			"digest": "sha256:487b82",
			"effective_on": "2023-10-21T00:00:00Z",
			"tag": "0.1",
		},
	]}

	attestation_c37e54 := mock_data({"ref": {
		"name": "buildah",
		"bundle": "q.io/r//task-buildah@sha256:c37e54",
	}})

	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as [attestation_c37e54]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-11-07T00:00:00Z")
	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as [attestation_c37e54]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-11-06T00:00:00Z")
	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as [attestation_c37e54]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-11-05T00:00:00Z")

	attestation_97f216 := mock_data({"name": "buildah", "ref": {
		"name": "buildah",
		"bundle": "q.io/r//task-buildah@sha256:97f216",
	}})

	expected_97f216 := {{
		"code": "attestation_task_bundle.task_ref_bundles_current",
		"msg": "Pipeline task 'buildah' uses an out of date task bundle 'q.io/r//task-buildah@sha256:97f216'",
	}}

	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as [attestation_97f216]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-11-07T00:00:00Z")
	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as [attestation_97f216]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-11-06T00:00:00Z")
	lib.assert_equal_results(
		expected_97f216,
		attestation_task_bundle.warn,
	) with input.attestations as [attestation_97f216]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-11-05T00:00:00Z")
	lib.assert_equal_results(
		expected_97f216,
		attestation_task_bundle.warn,
	) with input.attestations as [attestation_97f216]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-10-25T00:00:00Z")

	attestation_487b82 := mock_data({"name": "buildah", "ref": {
		"name": "buildah",
		"bundle": "q.io/r//task-buildah@sha256:487b82",
	}})

	expected_487b82 := {{
		"code": "attestation_task_bundle.task_ref_bundles_current",
		"msg": "Pipeline task 'buildah' uses an out of date task bundle 'q.io/r//task-buildah@sha256:487b82'",
	}}

	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as [attestation_487b82]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-11-07T00:00:00Z")
	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as [attestation_487b82]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-11-06T00:00:00Z")
	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as [attestation_487b82]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-11-05T00:00:00Z")
	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as [attestation_487b82]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-10-25T00:00:00Z")
	lib.assert_equal_results(
		expected_487b82,
		attestation_task_bundle.warn,
	) with input.attestations as [attestation_487b82]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-10-21T00:00:00Z")
	lib.assert_equal_results(
		expected_487b82,
		attestation_task_bundle.warn,
	) with input.attestations as [attestation_487b82]
		with data["task-bundles"] as bundles
		with data.config.policy.when_ns as time.parse_rfc3339_ns("2023-10-22T00:00:00Z")
}

test_ec316 if {
	image_ref := "registry.io/repository/image:0.3@sha256:abc"
	attestations := [
		mock_data({
			"name": "my-task",
			"ref": {"name": "my-task", "bundle": image_ref},
		}),
		lib_test.mock_slsav1_attestation_with_tasks([tkn_test.slsav1_task_bundle("my-task", image_ref)]),
	]

	acceptable_bundles := {"registry.io/repository/image": [
		{
			"digest": "sha256:abc",
			"effective_on": "2024-02-02T00:00:00Z",
			"tag": "0.1",
		},
		{
			"digest": "sha256:abc",
			"effective_on": "2024-02-02T00:00:00Z",
			"tag": "0.2",
		},
		{
			"digest": "sha256:abc",
			"effective_on": "2024-02-02T00:00:00Z",
			"tag": "0.3",
		},
		{
			"digest": "sha256:abc",
			"effective_on": "2024-01-21T00:00:00Z",
			"tag": "0.3",
		},
		{
			"digest": "sha256:abc",
			"effective_on": "2024-01-21T00:00:00Z",
			"tag": "0.3",
		},
	]}

	lib.assert_empty(attestation_task_bundle.warn) with input.attestations as attestations
		with data["task-bundles"] as acceptable_bundles

	lib.assert_empty(attestation_task_bundle.deny) with input.attestations as attestations
		with data["task-bundles"] as acceptable_bundles
}

task_bundles := {"reg.com/repo": [
	{
		# Latest v2
		"digest": "sha256:abc",
		"tag": "v2",
		"effective_on": "2022-04-11T00:00:00Z",
	},
	{
		# Older v2
		"digest": "sha256:bcd",
		"tag": "v2",
		"effective_on": "2022-03-11T00:00:00Z",
	},
	{
		# Latest v1
		"digest": "sha256:cde",
		"tag": "v1",
		"effective_on": "2022-02-01T00:00:00Z",
	},
	{
		# Older v1
		"digest": "sha256:def",
		"tag": "v1",
		"effective_on": "2021-01-01T00:00:00Z",
	},
]}
