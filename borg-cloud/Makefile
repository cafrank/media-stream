# =============================================================================
# Makefile — BorgCloud 3-node k3s cluster + data tier lifecycle (VirtualBox + Vagrant)
# =============================================================================

# ---- Vagrant ----
VAGRANT := vagrant

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---- Variables (read from vars.sh — single source of truth) ----
var = $(shell source ./vars.sh && echo "$$$(1)")

VBOX_GROUP     := $(call var,VBOX_GROUP)
NODE1_IP       := $(call var,NODE1_IP)
NODE2_IP       := $(call var,NODE2_IP)
NODE3_IP       := $(call var,NODE3_IP)
NODE1_NAME     := $(call var,NODE1_NAME)
NODE2_NAME     := $(call var,NODE2_NAME)
NODE3_NAME     := $(call var,NODE3_NAME)
NODES          := $(NODE1_NAME) $(NODE2_NAME) $(NODE3_NAME)
KUBECONFIG_OUT := $(call var,KUBECONFIG_OUT)
DB_NAMESPACE   := $(call var,DB_NAMESPACE)

VM_MEMORY ?= $(call var,VM_MEMORY)
VM_CPUS   ?= $(call var,VM_CPUS)
export VM_MEMORY VM_CPUS

SSH_USER := $(call var,SSH_USER)
SSH_KEY  := $(HOME)/.ssh/cluster_id_rsa
SSH_OPTS := -i $(SSH_KEY) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -o ConnectTimeout=10

KUBECTL := KUBECONFIG=$(KUBECONFIG_OUT) kubectl

# ============================================================
.PHONY: help
help:
	@echo ""
	@echo "BorgCloud 3-Node k3s Cluster  (VirtualBox group: $(VBOX_GROUP))"
	@echo "================================================================"
	@echo ""
	@echo "  First-time setup:"
	@echo "  make up                  Everything: vagrant-up + cluster + databases"
	@echo "  make vagrant-up          1. Create + provision all 3 VMs"
	@echo "  make cluster             2. Base OS prep + k3s HA install + kubeconfig"
	@echo "  make provision-databases 3. Postgres + MongoDB + Redis (3 members each)"
	@echo ""
	@echo "  Vagrant lifecycle:"
	@echo "  make vagrant-up          Create/start VMs + run provisioner"
	@echo "  make vagrant-start       Start existing VMs without re-provisioning"
	@echo "  make vagrant-halt        Graceful shutdown"
	@echo "  make vagrant-suspend     Suspend (save state)"
	@echo "  make vagrant-resume      Resume suspended VMs"
	@echo "  make vagrant-status      Show VM states"
	@echo "  make vagrant-provision   Re-run /etc/hosts + SSH key provisioner"
	@echo "  make vagrant-destroy     Destroy all VMs (irreversible)"
	@echo "  make vagrant-ssh-node1/2/3  Shell into a node via vagrant ssh"
	@echo ""
	@echo "  Provision steps (run after vagrant-up):"
	@echo "  make provision-base      01: swap off, kernel modules, sysctl, packages"
	@echo "  make provision-k3s       02: k3s HA (3 servers, embedded etcd) + kubeconfig"
	@echo "  make k3s-uninstall       Remove k3s from all nodes (keeps VMs)"
	@echo ""
	@echo "  Databases (namespace $(DB_NAMESPACE), one member per node):"
	@echo "  make provision-databases 03: operators + Postgres, MongoDB, Redis"
	@echo "  make provision-postgres  One database (also: provision-mongo, provision-redis)"
	@echo "  make db-status           Members, primaries and roles"
	@echo "  make db-info             In-cluster connection strings + credentials"
	@echo "  make db-test             Write on primary, read on every replica"
	@echo "  make db-failover-test    Delete each primary, verify promotion (disruptive)"
	@echo "  make db-uninstall        Delete databases, their data and operators"
	@echo ""
	@echo "  Convenience:"
	@echo "  make ssh-node1/2/3       SSH into a node with the cluster key"
	@echo "  make kubeconfig          Re-fetch kubeconfig → $(KUBECONFIG_OUT)"
	@echo "  make cluster-status      kubectl get nodes / pods -A"
	@echo ""
	@echo "  Nodes:"
	@echo "  $(NODE1_NAME)  $(NODE1_IP)"
	@echo "  $(NODE2_NAME)  $(NODE2_IP)"
	@echo "  $(NODE3_NAME)  $(NODE3_IP)"
	@echo "  k8s API:    https://$(NODE1_IP):6443"
	@echo "  VM size:    $(VM_MEMORY) MB / $(VM_CPUS) CPU  (override: make vagrant-up VM_MEMORY=8192 VM_CPUS=4)"
	@echo ""

.PHONY: up
up: vagrant-up cluster provision-databases

# ============================================================
# Vagrant VM lifecycle
# ============================================================

.PHONY: vagrant-up
vagrant-up:
	@if [ ! -f $(SSH_KEY) ]; then \
		echo ">>> Generating cluster SSH key ($(SSH_KEY))..."; \
		ssh-keygen -t ed25519 -f $(SSH_KEY) -N '' \
			-C "borg-cluster-$$(date +%Y%m%d)"; \
	fi
	@echo ">>> Bringing up 3 VMs in $(VBOX_GROUP)..."
	$(VAGRANT) up
	@echo ""
	@echo ">>> VMs ready. Next: make cluster"

.PHONY: vagrant-start
vagrant-start:
	$(VAGRANT) up --no-provision

.PHONY: vagrant-halt
vagrant-halt:
	$(VAGRANT) halt

.PHONY: vagrant-suspend
vagrant-suspend:
	$(VAGRANT) suspend

.PHONY: vagrant-resume
vagrant-resume:
	$(VAGRANT) resume

.PHONY: vagrant-status
vagrant-status:
	$(VAGRANT) status

.PHONY: vagrant-provision
vagrant-provision:
	$(VAGRANT) provision

.PHONY: vagrant-destroy
vagrant-destroy:
	@echo "WARNING: This destroys all BorgCloud VMs and their disks. Ctrl-C to abort."
	@sleep 3
	$(VAGRANT) destroy -f
	rm -f .k3s-token

.PHONY: vagrant-ssh-node1
vagrant-ssh-node1:
	$(VAGRANT) ssh $(NODE1_NAME)

.PHONY: vagrant-ssh-node2
vagrant-ssh-node2:
	$(VAGRANT) ssh $(NODE2_NAME)

.PHONY: vagrant-ssh-node3
vagrant-ssh-node3:
	$(VAGRANT) ssh $(NODE3_NAME)

# ============================================================
# Full cluster provisioning (runs 01→02 in order)
# ============================================================

.PHONY: cluster
cluster: provision-base provision-k3s
	@echo ""
	@echo "================================================="
	@echo "  BorgCloud k3s cluster ready!"
	@echo "================================================="
	@echo "  k8s API:  https://$(NODE1_IP):6443"
	@echo ""
	@echo "  export KUBECONFIG=$(KUBECONFIG_OUT)"
	@echo "  kubectl get nodes"
	@echo ""

# ============================================================
# Individual provision steps
# ============================================================

.PHONY: provision-base
provision-base:
	@echo ">>> [01/03] Base OS setup..."
	bash 01-base/setup-base.sh
	@echo ">>> [01/03] Done."

.PHONY: provision-k3s
provision-k3s:
	@echo ">>> [02/03] k3s HA cluster..."
	bash 02-k3s/install-k3s.sh
	@echo ">>> [02/03] Done."

.PHONY: provision-databases
provision-databases:
	@echo ">>> [03/03] Databases (namespace $(DB_NAMESPACE))..."
	bash 03-databases/install-databases.sh all
	@echo ">>> [03/03] Done."

.PHONY: provision-postgres
provision-postgres:
	bash 03-databases/install-databases.sh postgres

.PHONY: provision-mongo
provision-mongo:
	bash 03-databases/install-databases.sh mongo

.PHONY: provision-redis
provision-redis:
	bash 03-databases/install-databases.sh redis

.PHONY: k3s-uninstall
k3s-uninstall:
	@echo "WARNING: This removes k3s and all cluster data from every node. Ctrl-C to abort."
	@sleep 3
	@for ip in $(NODE3_IP) $(NODE2_IP) $(NODE1_IP); do \
		echo ">>> Uninstalling k3s on $$ip..."; \
		ssh $(SSH_OPTS) $(SSH_USER)@$$ip \
			'[ -x /usr/local/bin/k3s-uninstall.sh ] && sudo /usr/local/bin/k3s-uninstall.sh || echo "  (not installed)"'; \
	done
	rm -f .k3s-token

# ============================================================
# Convenience
# ============================================================

.PHONY: ssh-node1
ssh-node1:
	ssh $(SSH_OPTS) $(SSH_USER)@$(NODE1_IP)

.PHONY: ssh-node2
ssh-node2:
	ssh $(SSH_OPTS) $(SSH_USER)@$(NODE2_IP)

.PHONY: ssh-node3
ssh-node3:
	ssh $(SSH_OPTS) $(SSH_USER)@$(NODE3_IP)

.PHONY: kubeconfig
kubeconfig:
	@echo ">>> Fetching kubeconfig from $(NODE1_NAME)..."
	@mkdir -p $(dir $(KUBECONFIG_OUT))
	ssh $(SSH_OPTS) $(SSH_USER)@$(NODE1_IP) 'cat /etc/rancher/k3s/k3s.yaml' \
		| sed -e 's|https://127.0.0.1:6443|https://$(NODE1_IP):6443|' \
		      -e 's|: default$$|: borg|' > $(KUBECONFIG_OUT)
	@chmod 600 $(KUBECONFIG_OUT)
	@echo ">>> Saved: $(KUBECONFIG_OUT)"
	@echo "    export KUBECONFIG=$(KUBECONFIG_OUT)"

.PHONY: cluster-status
cluster-status:
	$(KUBECTL) get nodes -o wide
	@echo ""
	$(KUBECTL) get pods -A

.PHONY: db-test
db-test:
	bash 03-databases/db-test.sh

.PHONY: db-status
db-status:
	@bash 03-databases/db-status.sh

.PHONY: db-info
db-info:
	@bash 03-databases/db-info.sh

.PHONY: db-failover-test
db-failover-test:
	@echo "WARNING: This deletes each database's primary pod. Ctrl-C to abort."
	@sleep 3
	bash 03-databases/db-failover-test.sh

.PHONY: db-uninstall
db-uninstall:
	@echo "WARNING: This deletes all databases and their data in namespace $(DB_NAMESPACE). Ctrl-C to abort."
	@sleep 3
	bash 03-databases/uninstall-databases.sh
