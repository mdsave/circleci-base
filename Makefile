IMAGE_NAME     ?= public.ecr.aws/g8w4z0q4/circleci-base
TAG            ?= local
IMAGE          := $(IMAGE_NAME):$(TAG)
TRIVY_SEVERITY   ?= HIGH,CRITICAL,MEDIUM,LOW
# trivy only auto-detects '.trivyignore'; the YAML form must be passed explicitly.
TRIVY_IGNOREFILE ?= .trivyignore.yaml
PLATFORM       ?= linux/amd64

REPORT := trivy-report.json

AWS_PROFILE    ?= tendo-marketplace
AWS_REGION     ?= us-east-1
AWS_ACCOUNT    ?= 515909623945
SSO_SESSION    ?= sso-session-oldhouse
ECR_REGISTRY   := $(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com
ECR_REPO       ?= circleci-base
VERSION        ?= $(shell git rev-parse --abbrev-ref HEAD)
ECR_IMAGE      := $(ECR_REGISTRY)/$(ECR_REPO):$(VERSION)
CONTAINER_NAME ?= circleci-base-dev

INFRA_DIR           := infra
CIRCLECI_ORG_ID     ?=
CIRCLECI_PROJECT_ID ?=
CDK_CONTEXT         :=
ifneq ($(CIRCLECI_ORG_ID),)
CDK_CONTEXT         += -c circleciOrgId=$(CIRCLECI_ORG_ID)
endif
ifneq ($(CIRCLECI_PROJECT_ID),)
CDK_CONTEXT         += -c circleciProjectId=$(CIRCLECI_PROJECT_ID)
endif

CYAN  := \033[1;36m
RESET := \033[0m

.PHONY: help build validate trivy trivy-config trivy-fs trivy-image trivy-vendor trivy-unfixed renovate copa ci zscaler-cert \
        docker-build docker-start docker-shell docker-status docker-log docker-stop docker-deploy \
        infra-info infra-install infra-build infra-synth infra-diff infra-deploy infra-undeploy infra-bootstrap infra-clean \
        check-docker check-trivy check-renovate check-copa check-cosign check-aws check-ecr-login \
        check-pnpm

help:
	@printf "$(CYAN)Build:$(RESET)\n"
	@echo "  build          - docker build --platform $(PLATFORM) --provenance=false --sbom=false -t $(IMAGE) ."
	@echo ""
	@printf "$(CYAN)Validate:$(RESET)\n"
	@echo "  validate       - lint Dockerfile with hadolint"
	@echo ""
	@printf "$(CYAN)Container lifecycle:$(RESET)\n"
	@echo "  docker-build   - alias for build"
	@echo "  docker-start   - start detached container '$(CONTAINER_NAME)' (idempotent)"
	@echo "  docker-shell   - exec an interactive bash shell into '$(CONTAINER_NAME)'"
	@echo "  docker-status  - show whether '$(CONTAINER_NAME)' is up or down"
	@echo "  docker-log     - follow logs of '$(CONTAINER_NAME)'"
	@echo "  docker-stop    - remove the '$(CONTAINER_NAME)' container"
	@echo "  docker-deploy  - push + cosign-sign $(ECR_IMAGE)"
	@echo ""
	@printf "$(CYAN)Infrastructure (CDK, in $(INFRA_DIR)/):$(RESET)\n"
	@echo "  infra-info     - print resource names this stack will create (no AWS needed)"
	@echo "  infra-install  - pnpm install CDK deps (idempotent)"
	@echo "  infra-build    - typecheck the CDK app"
	@echo "  infra-synth    - synth CloudFormation (no AWS creds needed)"
	@echo "  infra-diff     - diff against deployed stack"
	@echo "  infra-deploy   - deploy ECR repo + KMS signing key + publish role"
	@echo "  infra-undeploy - destroy the stack (prompts; ECR repo + KMS key are retained)"
	@echo "  infra-clean    - remove $(INFRA_DIR)/node_modules and cdk.out"
	@echo "  infra-bootstrap- cdk bootstrap aws://$(AWS_ACCOUNT)/$(AWS_REGION)"
	@echo "                   (add CIRCLECI_ORG_ID=<uuid> to also trust CircleCI OIDC)"
	@echo ""
	@printf "$(CYAN)Security scanning (Trivy):$(RESET)\n"
	@echo "  trivy          - config + fs + image (gate) + vendor (report)"
	@echo "  trivy-config   - trivy misconfig scan of Dockerfile"
	@echo "  trivy-fs       - trivy vuln + secret scan of repo filesystem"
	@echo "  trivy-image    - GATE: OS-package vulns in $(IMAGE) (builds first)"
	@echo "  trivy-vendor   - report-only: vulns in vendor binaries (never fails)"
	@echo "  trivy-unfixed  - everything incl. unfixed + accepted, bypasses $(TRIVY_IGNOREFILE)"
	@echo ""
	@printf "$(CYAN)Remediation:$(RESET)\n"
	@echo "  copa           - patch OS vulns in $(IMAGE) with copa, then re-scan"
	@echo ""
	@printf "$(CYAN)Dependency updates:$(RESET)\n"
	@echo "  renovate       - validate .github/renovate.json"
	@echo ""
	@printf "$(CYAN)Local dev setup:$(RESET)\n"
	@echo "  zscaler-cert   - export Zscaler root CA from macOS keychain to zscaler-root-ca.crt"
	@echo ""
	@printf "$(CYAN)Aggregate:$(RESET)\n"
	@echo "  ci             - validate + trivy + renovate"

check-docker:
	@command -v docker >/dev/null 2>&1 || { echo "docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "docker daemon not running. Start Docker Desktop and retry."; exit 1; }

check-trivy:
	@command -v trivy >/dev/null 2>&1 || { \
		echo "trivy not found."; \
		if command -v brew >/dev/null 2>&1; then echo "Installing via Homebrew..."; brew install trivy; \
		else echo "Install manually: https://trivy.dev/latest/getting-started/installation/"; exit 1; fi; \
	}

check-renovate:
	@command -v renovate-config-validator >/dev/null 2>&1 || { \
		echo "renovate-config-validator not found."; \
		if command -v brew >/dev/null 2>&1; then echo "Installing via Homebrew..."; brew install renovate; \
		else echo "Install manually: npm i -g renovate"; exit 1; fi; \
	}

check-copa:
	@command -v copa >/dev/null 2>&1 || { \
		echo "copa not found."; \
		if command -v brew >/dev/null 2>&1; then echo "Installing via Homebrew..."; brew install copa; \
		else echo "Install manually: https://project-copacetic.github.io/copacetic/website/installation"; exit 1; fi; \
	}

check-cosign:
	@command -v cosign >/dev/null 2>&1 || { \
		echo "cosign not found."; \
		if command -v brew >/dev/null 2>&1; then echo "Installing via Homebrew..."; brew install cosign; \
		else echo "Install manually: https://docs.sigstore.dev/cosign/system_config/installation/"; exit 1; fi; \
	}

check-ecr-login:
	@command -v docker-credential-ecr-login >/dev/null 2>&1 || { \
		echo "docker-credential-ecr-login not found."; \
		if command -v brew >/dev/null 2>&1; then echo "Installing via Homebrew..."; brew install docker-credential-helper-ecr; \
		else echo "Install manually: https://github.com/awslabs/amazon-ecr-credential-helper"; exit 1; fi; \
	}

check-pnpm:
	@command -v pnpm >/dev/null 2>&1 || { \
		echo "pnpm not found."; \
		if command -v brew >/dev/null 2>&1; then echo "Installing via Homebrew..."; brew install pnpm; \
		else echo "Install manually: https://pnpm.io/installation"; exit 1; fi; \
	}

check-aws:
	@command -v aws >/dev/null 2>&1 || { echo "aws cli not found. Install: https://aws.amazon.com/cli/"; exit 1; }
	@aws sts get-caller-identity --profile $(AWS_PROFILE) >/dev/null 2>&1 || { \
		echo "AWS session for profile '$(AWS_PROFILE)' is not valid."; \
		echo "Run: aws sso login --sso-session $(SSO_SESSION)"; exit 1; }

zscaler-cert: zscaler-root-ca.crt

zscaler-root-ca.crt:
	@command -v security >/dev/null 2>&1 || { echo "'security' not found (macOS only). Export your corporate root CA to $@ manually."; exit 1; }
	security find-certificate -c "Zscaler Root CA" -p /Library/Keychains/System.keychain > $@

build: check-docker
	docker build --platform $(PLATFORM) --provenance=false --sbom=false -t $(IMAGE) .

validate: check-docker
	docker run --rm -i hadolint/hadolint < Dockerfile

docker-build: build

docker-start: build
	@docker inspect -f '{{.State.Running}}' $(CONTAINER_NAME) 2>/dev/null | grep -q true \
		|| { docker rm -f $(CONTAINER_NAME) >/dev/null 2>&1; \
		     docker run -d --name $(CONTAINER_NAME) --platform $(PLATFORM) $(IMAGE) sleep infinity; }

docker-shell: docker-start
	docker exec -it $(CONTAINER_NAME) bash

docker-status: check-docker
	@if docker inspect $(CONTAINER_NAME) >/dev/null 2>&1; then \
		detail=$$(docker ps -a --filter "name=^/$(CONTAINER_NAME)$$" --format '{{.Status}}'); \
		if [ "$$(docker inspect -f '{{.State.Running}}' $(CONTAINER_NAME))" = "true" ]; then \
			printf "🟢 %s — up (%s)\n" "$(CONTAINER_NAME)" "$$detail"; \
		else \
			printf "🔴 %s — down (%s)\n" "$(CONTAINER_NAME)" "$$detail"; \
		fi; \
	else \
		printf "⚪ %s — down (no container; run 'make docker-start')\n" "$(CONTAINER_NAME)"; \
	fi

docker-log: check-docker
	docker logs -f $(CONTAINER_NAME)

docker-stop: check-docker
	docker rm -f $(CONTAINER_NAME)

docker-deploy: check-docker check-aws check-ecr-login check-cosign build
	aws ecr get-login-password --region $(AWS_REGION) --profile $(AWS_PROFILE) \
		| docker login --username AWS --password-stdin $(ECR_REGISTRY)
	docker tag $(IMAGE) $(ECR_IMAGE)
	docker push $(ECR_IMAGE)
	@digest=$$(aws ecr describe-images --repository-name $(ECR_REPO) --image-ids imageTag=$(VERSION) \
		--query 'imageDetails[0].imageDigest' --output text \
		--region $(AWS_REGION) --profile $(AWS_PROFILE)); \
	echo "Signing $(ECR_REGISTRY)/$(ECR_REPO)@$$digest"; \
	cosign sign --yes $(ECR_REGISTRY)/$(ECR_REPO)@$$digest

infra-info:
	@printf "$(CYAN)Resources defined by $(INFRA_DIR)/cdk.json:$(RESET)\n"
	@node -e "\
	const fs=require('fs'); const p=process.argv; \
	const c=JSON.parse(fs.readFileSync(p[1],'utf8')).context; \
	const repo=c.ecrRepoName, acct=c.account, reg=c.region; \
	const stack=repo+'-ecr-publish'; const role=repo+'-publisher'; \
	const rows=[ \
	  ['Stack', stack], \
	  ['ECR repository', repo], \
	  ['ECR repo URI', acct+'.dkr.ecr.'+reg+'.amazonaws.com/'+repo], \
	  ['IAM role', role], \
	  ['IAM role ARN', 'arn:aws:iam::'+acct+':role/'+role], \
	  ['KMS key', '(auto-generated UUID; addressed via alias)'], \
	  ['KMS alias', 'alias/cosign/'+repo], \
	  ['cosign key URI', 'awskms:///alias/cosign/'+repo], \
	  ['SSO permission set', c.ssoPermissionSet], \
	  ['Account / Region', acct+' / '+reg], \
	  ['CircleCI OIDC', p[2] ? 'enabled (org '+p[2]+')' : 'disabled (pass CIRCLECI_ORG_ID=<uuid>)'] \
	]; \
	rows.forEach(r => console.log('  '+r[0].padEnd(20)+r[1])); \
	const req=['TEAM_OWNER_NAME','TEAM_OWNER_EMAIL','PRODUCT_OWNER_NAME','PRODUCT_OWNER_EMAIL','JIRA_PROJECT','SLACK_CHANNEL','PRODUCT_NAME','PRODUCT_REPO']; \
	const tg=c.tags||{}; \
	console.log(''); console.log('  Ownership tags (applied to every resource):'); \
	req.forEach(k => console.log('    '+k.padEnd(22)+(tg[k]||'** MISSING **'))); \
	const extra=Object.keys(tg).filter(k => !req.includes(k)); \
	extra.forEach(k => console.log('    '+k.padEnd(22)+tg[k])); \
	if (p[3] && p[3]!==acct) console.log('  WARNING: Makefile AWS_ACCOUNT='+p[3]+' differs from cdk.json account='+acct); \
	if (p[4] && p[4]!==repo) console.log('  WARNING: Makefile ECR_REPO='+p[4]+' differs from cdk.json ecrRepoName='+repo); \
	" $(INFRA_DIR)/cdk.json "$(CIRCLECI_ORG_ID)" "$(AWS_ACCOUNT)" "$(ECR_REPO)"

infra-install: $(INFRA_DIR)/node_modules

$(INFRA_DIR)/node_modules: $(INFRA_DIR)/package.json | check-pnpm
	cd $(INFRA_DIR) && pnpm install
	@touch $@

infra-build: infra-install
	cd $(INFRA_DIR) && pnpm exec tsc --noEmit

infra-synth: infra-install
	cd $(INFRA_DIR) && pnpm exec cdk synth $(CDK_CONTEXT)

infra-diff: infra-install check-aws
	cd $(INFRA_DIR) && pnpm exec cdk diff $(CDK_CONTEXT) --profile $(AWS_PROFILE)

infra-deploy: infra-install check-aws
	cd $(INFRA_DIR) && pnpm exec cdk deploy $(CDK_CONTEXT) --profile $(AWS_PROFILE)

infra-clean:
	rm -rf $(INFRA_DIR)/node_modules $(INFRA_DIR)/cdk.out

infra-undeploy: infra-install check-aws
	@printf "$(CYAN)Destroying stack $(ECR_REPO)-ecr-publish$(RESET)\n"
	@echo "  DELETED : IAM role $(ECR_REPO)-publisher (+ its policy)"
	@echo "            KMS alias alias/cosign/$(ECR_REPO)"
	@echo "  RETAINED: ECR repo $(ECR_REPO) and all its images"
	@echo "            the KMS key itself (orphaned, no longer aliased)"
	@echo ""
	@echo "  After this, 'awskms:///alias/cosign/$(ECR_REPO)' no longer resolves."
	@echo "  A later infra-deploy creates a NEW key; images signed with the old"
	@echo "  key will only verify against the orphaned key ARN."
	@echo ""
	cd $(INFRA_DIR) && pnpm exec cdk destroy $(CDK_CONTEXT) --profile $(AWS_PROFILE)

infra-bootstrap: infra-install check-aws
	cd $(INFRA_DIR) && pnpm exec cdk bootstrap aws://$(AWS_ACCOUNT)/$(AWS_REGION) --profile $(AWS_PROFILE)

trivy-config: check-trivy
	trivy config --exit-code 1 --severity $(TRIVY_SEVERITY) .

trivy-fs: check-trivy
	trivy fs --scanners vuln,secret --ignore-unfixed --ignorefile $(TRIVY_IGNOREFILE) \
		--exit-code 1 --severity $(TRIVY_SEVERITY) .

# Hard gate: OS packages only. These we control by choosing what the Dockerfile
# installs, so a finding here is actionable.
trivy-image: check-trivy build
	trivy image --pkg-types os --ignore-unfixed --ignorefile $(TRIVY_IGNOREFILE) \
		--exit-code 1 --severity $(TRIVY_SEVERITY) $(IMAGE)

# Report only: findings inside vendor-distributed binaries, which are fixed by
# the vendor rebuilding, not by anything in this repo. Never fails the build.
trivy-vendor: check-trivy build
	@printf "$(CYAN)Vendor binaries (report only; accepted entries in $(TRIVY_IGNOREFILE) suppressed)$(RESET)\n"
	trivy image --pkg-types library --ignore-unfixed --ignorefile $(TRIVY_IGNOREFILE) \
		--severity $(TRIVY_SEVERITY) $(IMAGE)

# Everything, bypassing the ignore file: the escape hatch for re-review.
trivy-unfixed: check-trivy build
	trivy image --ignorefile /dev/null --severity $(TRIVY_SEVERITY) $(IMAGE)

trivy: trivy-config trivy-fs trivy-image trivy-vendor

renovate: check-renovate
	renovate-config-validator .github/renovate.json

copa: check-copa check-trivy build
	trivy image --vuln-type os --ignore-unfixed -f json -o $(REPORT) $(IMAGE)
	@output=$$(copa patch -i $(IMAGE) -r $(REPORT) -t $(TAG)-patched --platform $(PLATFORM) 2>&1); status=$$?; \
	echo "$$output"; \
	if echo "$$output" | grep -q "no package updates found"; then \
		echo "No OS vulnerabilities to patch -- image is already clean."; \
	elif [ $$status -ne 0 ]; then \
		exit $$status; \
	else \
		trivy image --vuln-type os --ignore-unfixed --exit-code 1 --severity $(TRIVY_SEVERITY) $(IMAGE_NAME):$(TAG)-patched; \
	fi

ci: validate trivy renovate
