SHELL := /bin/bash
.PHONY: test syntax

syntax:
	@find scripts tests -type f \( -name '*.sh' -o -name 'local-k3s' \) -print0 | xargs -0 -n1 bash -n
	@bash -n install.sh

test: syntax
	@./tests/integration/global_cli_test.sh
	@./tests/integration/update_test.sh
	@./tests/integration/mock_build_test.sh
	@./tests/integration/mock_failure_cleanup_test.sh
	@./tests/integration/incomplete_cluster_test.sh
	@./tests/integration/cluster_index_test.sh
	@./tests/integration/custom_resources_test.sh
	@./tests/integration/safe_destroy_test.sh
	@./tests/integration/fake_gpu_failure_test.sh
	@./tests/integration/fake_gpu_wait_test.sh
