PROFILE ?= colocated
TERRAFORM ?= terraform
TF_DIR := terraform/environments/$(PROFILE)
VALID_PROFILES := full colocated

.PHONY: tf-fmt tf-validate cluster-up cluster-down check-profile pg-configure pg-verify pg-failover pg-clean etcd-configure etcd-verify etcd-quorum-test etcd-clean patroni-configure patroni-verify haproxy-configure haproxy-verify patroni-failover-test

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
