# tflint CI negative test

Date: 2026-10-18

Purpose: prove the tflint CI check can fail, and that a failing tflint blocks a merge, not only that it passes.

What was done: on a throwaway branch, one deliberately unused input variable (`unused_negative_test`) was added in its own file, `infra/zz-negative-test.tf`. The file was correctly formatted and valid Terraform, so only tflint should object. A pull request was opened (#6). It was never merged and never deployed. The branch was deleted afterwards.

Result:

- validate job: passed (code was valid and correctly formatted)
- security-scan job: passed (Checkov found nothing, the variable creates no resource)
- tflint job: FAILED, exit code 2
- Rule: terraform_unused_declarations (tflint terraform ruleset v0.15.0)
- Message: variable "unused_negative_test" is declared but not used
- tflint was a required status check at the time, and GitHub disabled the Merge button

Conclusion: the tflint check catches a code-quality problem that format check, validate and Checkov all let through, and the branch ruleset stops it reaching main. Pull request #6 remains viewable on GitHub as a closed pull request with the red check.
