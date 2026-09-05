PROFILE ?= colocated
TERRAFORM ?= terraform
TF_DIR := terraform/environments/$(PROFILE)
VALID_PROFILES := full colocated

.PHONY: tf-fmt tf-validate cluster-up cluster-down check-profile

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
	$(TERRAFORM) -chdir=$(TF_DIR) destroy
