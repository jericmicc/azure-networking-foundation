# tflint on the modules: CI negative test

Date: 2026-11-09

Purpose: prove that the tflint CI check now looks inside `infra/modules/tier`, and can fail there. Before this change the job ran plain `tflint` in `infra`, which does not enter the module, so a mistake inside the module would have passed all four required checks.

## What was changed

Pull request #29 changed one line of `.github/workflows/terraform-ci.yml`: the step "Run tflint" now runs `tflint --recursive` instead of `tflint`. All four checks passed and it was merged.

## What was tested

On a throwaway branch, one deliberately unused input variable (`unused_negative_test`) was added in its own file, `infra/modules/tier/zz-negative-test.tf`. The file was valid Terraform and correctly formatted (`terraform fmt -check -recursive` printed nothing), so only tflint should object. Pull request #30 was opened. It was never merged and never deployed, and the branch was deleted afterwards.

## Result

Local run, from inside `infra`:

| Command | Exit code | Finding |
| --- | --- | --- |
| `tflint --recursive` | 2 | variable "unused_negative_test" is declared but not used |
| `tflint` (the old command) | 0 | none, the module is not checked |

CI run on the pull request:

- validate job: passed
- security-scan job: passed
- plan job: passed
- tflint job: FAILED after 10 seconds, exit code 2
- Failing step: "Run tflint", running `tflint --recursive`
- Rule: `terraform_unused_declarations` (tflint terraform ruleset v0.15.0)
- Location: `modules/tier/zz-negative-test.tf`, line 1
- tflint is a required status check, and GitHub disabled the Merge button

## Conclusion

The tflint check now catches a code-quality problem inside the module that format check, validate, Checkov and the plan all let through, and the branch ruleset stops it reaching `main`. Pull request #30 remains viewable on GitHub as a closed pull request with the red check.

## What this does not prove

- Only one rule was exercised (`terraform_unused_declarations`). The other tflint rules, including the Azure ruleset, were not tested against the module.
- The finding was reported as a warning. tflint exits with 2 on any finding, which is what fails the job. A tflint configuration that changed this would change the result.
- Only `infra/modules/tier` exists. A module added in another folder is covered by `--recursive` in the same way, but that was not tested.
