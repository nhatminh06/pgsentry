PROFILE ?= colocated
SCENARIO ?= primary-service-loss
TRIAL ?= 1
MODE ?= async
CHAOS_SCENARIO ?= primary-dcs-isolation
FILE ?= testdata/migrations/safe/staged.sql
PGSAFE ?= ./bin/pgsafe
RESTORE_MODE ?= latest
ALERT_TEST ?= replica-loss
TERRAFORM ?= terraform
TF_DIR := terraform/environments/$(PROFILE)
VALID_PROFILES := full colocated

.PHONY: tf-fmt tf-validate cluster-up cluster-down check-profile pg-configure pg-verify pg-failover pg-clean etcd-configure etcd-verify etcd-quorum-test etcd-clean patroni-configure patroni-verify haproxy-configure haproxy-verify patroni-failover-test failure-baseline failure-scenario failure-matrix failure-report failure-clean durability-set durability-verify durability-latency durability-failure-test durability-standby-loss durability-strict-test durability-matrix durability-report durability-clean chaos-baseline chaos-scenario chaos-matrix chaos-report chaos-clean pgsafe-build pgsafe-test pgsafe-check pgsafe-fixtures migration-baseline migration-runtime-test migration-clean backup-configure backup-check backup-full backup-info backup-archive-verify restore-latest restore-verify restore-clean pitr-test backup-acceptance backup-clean observability-configure observability-check observability-verify observability-alert-test observability-clean observability-static

tf-fmt:
	$(TERRAFORM) fmt -recursive terraform

tf-validate:
	$(TERRAFORM) fmt -check -recursive terraform
	@for profile in $(VALID_PROFILES); do \
		$(TERRAFORM) -chdir=terraform/environments/$$profile init -backend=false; \
		$(TERRAFORM) -chdir=terraform/environments/$$profile validate; \
	done

check-profile:
	@case " $(VALID_PROFILES) " in *" $(PROFILE) "*) ;; *) \
		echo "PROFILE must be one of: $(VALID_PROFILES)" >&2; exit 2;; esac

cluster-up: check-profile
	$(TERRAFORM) -chdir=$(TF_DIR) init
	$(TERRAFORM) -chdir=$(TF_DIR) apply

cluster-down: check-profile
	$(TERRAFORM) -chdir=$(TF_DIR) destroy -auto-approve
	@rm -rf .pgsentry

pg-configure: check-profile
	./scripts/postgres/configure.sh $(PROFILE)

pg-verify: check-profile
	./scripts/postgres/verify.sh $(PROFILE)

pg-failover: check-profile
	./scripts/postgres/failover.sh $(PROFILE)

pg-clean:
	rm -rf .pgsentry

etcd-configure: check-profile
	./scripts/etcd/configure.sh $(PROFILE)

etcd-verify: check-profile
	./scripts/etcd/verify.sh $(PROFILE)

etcd-quorum-test: check-profile
	./scripts/etcd/quorum-test.sh $(PROFILE)

etcd-clean:
	rm -rf .pgsentry/etcd

patroni-configure: check-profile
	./scripts/ha/configure-patroni.sh $(PROFILE)

patroni-verify: check-profile
	./scripts/ha/verify-patroni.sh $(PROFILE)

haproxy-configure: check-profile
	./scripts/ha/configure-haproxy.sh $(PROFILE)

haproxy-verify: check-profile
	./scripts/ha/verify-haproxy.sh $(PROFILE)

patroni-failover-test: check-profile
	./scripts/ha/failover-test.sh $(PROFILE)

failure-baseline: check-profile
	./scripts/failures/baseline.sh $(PROFILE)

failure-scenario: check-profile
	./scripts/failures/scenario.sh $(PROFILE) $(SCENARIO) $(TRIAL)

failure-matrix: check-profile
	./scripts/failures/run-matrix.sh $(PROFILE)

failure-report:
	python3 scripts/failures/report.py .pgsentry/results/m5

failure-clean:
	rm -rf .pgsentry/results/m5

durability-set: check-profile
	./scripts/durability/policy.sh $(PROFILE) $(MODE)

durability-verify: check-profile
	./scripts/durability/verify.sh $(PROFILE) $(MODE)

durability-latency: check-profile
	./scripts/durability/latency.sh $(PROFILE) $(MODE)

durability-failure-test: check-profile
	./scripts/durability/scenario.sh $(PROFILE) $(MODE) primary-vm-loss $(TRIAL)

durability-standby-loss: check-profile
	./scripts/durability/scenario.sh $(PROFILE) sync synchronous-standby-loss $(TRIAL)

durability-strict-test: check-profile
	./scripts/durability/scenario.sh $(PROFILE) sync-strict no-synchronous-standby $(TRIAL)

durability-matrix: check-profile
	./scripts/durability/run-matrix.sh $(PROFILE)

durability-report:
	python3 scripts/durability/report.py .pgsentry/results/m6

durability-clean:
	rm -rf .pgsentry/results/m6

chaos-baseline: check-profile
	./scripts/chaos/baseline.sh $(PROFILE)

chaos-scenario: check-profile
	./scripts/chaos/scenario.sh $(PROFILE) $(CHAOS_SCENARIO) $(TRIAL)

chaos-matrix: check-profile
	./scripts/chaos/run-matrix.sh $(PROFILE)

chaos-report:
	python3 scripts/chaos/report.py .pgsentry/results/m7

chaos-clean:
	rm -rf .pgsentry/results/m7

pgsafe-build:
	mkdir -p bin
	go build -ldflags "-X main.version=m8" -o $(PGSAFE) ./cmd/pgsafe

pgsafe-test:
	go test ./...
	go vet ./...

pgsafe-check: pgsafe-build
	$(PGSAFE) check $(FILE)

pgsafe-fixtures: pgsafe-build
	$(PGSAFE) check testdata/migrations/safe/staged.sql
	@$(PGSAFE) check testdata/migrations/unsafe/risky.sql >/dev/null 2>&1; test $$? -eq 1
	@$(PGSAFE) check testdata/migrations/edge/malformed.sql >/dev/null 2>&1; test $$? -eq 2
	$(PGSAFE) check testdata/migrations/edge/suppressed.sql
	$(PGSAFE) check testdata/migrations/edge/quoted.sql --format=json >/dev/null

migration-baseline: check-profile
	./scripts/migrations/baseline.sh $(PROFILE)

migration-runtime-test: check-profile
	./scripts/migrations/runtime-test.sh $(PROFILE)

migration-clean: check-profile
	./scripts/migrations/clean.sh $(PROFILE)

# M9: backup-acceptance intentionally creates and DELETEs disposable m9_recovery data.
backup-configure: check-profile
	./scripts/backup/configure.sh $(PROFILE)

backup-check: check-profile
	./scripts/backup/check.sh $(PROFILE)

backup-full: check-profile
	./scripts/backup/full.sh $(PROFILE)

backup-info: check-profile
	./scripts/backup/info.sh $(PROFILE)

backup-archive-verify: check-profile
	./scripts/backup/archive-verify.sh $(PROFILE)

restore-latest: check-profile
	./scripts/backup/restore.sh $(PROFILE) latest

restore-verify: check-profile
	./scripts/backup/verify-restore.sh $(PROFILE) $(RESTORE_MODE)

restore-clean: check-profile
	./scripts/backup/clean.sh $(PROFILE) restore

pitr-test: check-profile
	./scripts/backup/restore.sh $(PROFILE) pitr
	./scripts/backup/verify-restore.sh $(PROFILE) pitr

backup-acceptance: check-profile
	@echo 'WARNING: creates, backs up, restores, and intentionally DELETEs disposable m9_recovery data'
	./scripts/backup/acceptance.sh $(PROFILE)

backup-clean: check-profile
	./scripts/backup/clean.sh $(PROFILE) all

observability-configure: check-profile
	./scripts/observability/configure.sh $(PROFILE)

observability-check: check-profile
	./scripts/observability/check.sh $(PROFILE)

observability-verify: check-profile
	./scripts/observability/verify.sh $(PROFILE)

# Explicitly destructive and self-restoring; ALERT_TEST=replica-loss|etcd-member-loss|haproxy-loss|replication-lag.
observability-alert-test: check-profile
	./scripts/observability/alert-test.sh $(PROFILE) $(ALERT_TEST)

observability-clean: check-profile
	./scripts/observability/clean.sh $(PROFILE)

observability-static:
	./scripts/observability/static-check.sh
