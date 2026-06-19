# Makefile for OTC-P2P contract deployment and management.

.PHONY: all build test clean install format lint gas-report test-coverage setup-env check dev-setup help
.PHONY: deploy-protocol-local deploy-protocol-sepolia deploy-protocol-mainnet deploy-protocol-polygon deploy-protocol-bsc
.PHONY: deploy-registry-local deploy-registry-sepolia deploy-registry-mainnet deploy-registry-polygon deploy-registry-bsc
.PHONY: deploy-factory-local deploy-factory-sepolia deploy-factory-mainnet deploy-factory-polygon deploy-factory-bsc
.PHONY: deploy-vault-local deploy-vault-sepolia deploy-vault-mainnet deploy-vault-polygon deploy-vault-bsc
.PHONY: deploy-protocol-dry-run-local deploy-protocol-dry-run-sepolia deploy-protocol-dry-run-mainnet deploy-protocol-dry-run-polygon deploy-protocol-dry-run-bsc
.PHONY: deploy-registry-dry-run-local deploy-registry-dry-run-sepolia deploy-registry-dry-run-mainnet deploy-registry-dry-run-polygon deploy-registry-dry-run-bsc
.PHONY: deploy-factory-dry-run-local deploy-factory-dry-run-sepolia deploy-factory-dry-run-mainnet deploy-factory-dry-run-polygon deploy-factory-dry-run-bsc
.PHONY: deploy-vault-dry-run-local deploy-vault-dry-run-sepolia deploy-vault-dry-run-mainnet deploy-vault-dry-run-polygon deploy-vault-dry-run-bsc
.PHONY: verify-registry verify-factory verify-client-vault verify-client-vault-light

-include .env
.EXPORT_ALL_VARIABLES:

LOCAL_RPC_URL := http://127.0.0.1:8545

SEPOLIA_RPC := ${RPC_URL_SEPOLIA}
MAINNET_RPC := ${RPC_URL_MAINNET}
POLYGON_RPC := ${RPC_URL_POLYGON}
BSC_RPC := ${RPC_URL_BSC}

DEPLOY_SCRIPT_PROTOCOL := script/DeployOTCProtocol.s.sol:DeployOTCProtocolScript
DEPLOY_SCRIPT_REGISTRY := script/DeployRegistry.s.sol:DeployRegistryScript
DEPLOY_SCRIPT_FACTORY := script/DeployFactory.s.sol:DeployFactoryScript
DEPLOY_SCRIPT_VAULT := script/DeployClientVault.s.sol:DeployClientVaultScript

PRIVATE_KEY := ${PRIVATE_KEY}

all: help

install:
	@echo "Installing dependencies..."
	forge install
	@echo "Dependencies installed successfully!"

build:
	@echo "Building contracts..."
	forge build
	@echo "Build completed successfully!"

test:
	@echo "Running tests..."
	forge test -vvv
	@echo "Tests completed!"

test-coverage:
	@echo "Running tests with coverage..."
	forge coverage
	@echo "Coverage report generated!"

clean:
	@echo "Cleaning build artifacts..."
	forge clean
	@echo "Clean completed!"

format:
	@echo "Formatting code..."
	forge fmt
	@echo "Code formatted!"

lint:
	@echo "Running linter..."
	forge fmt --check
	@echo "Linting completed!"

gas-report:
	@echo "Generating gas report..."
	forge test --gas-report
	@echo "Gas report generated!"

setup-env:
	@if [ ! -f .env ]; then \
		echo "Creating .env file from .env.example..."; \
		cp .env.example .env; \
		echo ".env file created. Please edit it with your deployment configuration."; \
	else \
		echo ".env file already exists."; \
	fi

define run_script
	forge clean
	forge script $(1) --rpc-url $(2) --private-key ${PRIVATE_KEY} $(3) -vvv
endef

define run_script_verify
	forge clean
	forge script $(1) --rpc-url $(2) --private-key ${PRIVATE_KEY} --broadcast --verify --etherscan-api-key $(3) --verifier etherscan $(4) -vvv
endef

# Full protocol deploy: registry + operator factory + optional first client vault.
deploy-protocol-local:
	@echo "Deploying OTC protocol to local network..."
	$(call run_script,${DEPLOY_SCRIPT_PROTOCOL},${LOCAL_RPC_URL},--broadcast)

deploy-protocol-sepolia:
	@echo "Deploying OTC protocol to Sepolia..."
	$(call run_script_verify,${DEPLOY_SCRIPT_PROTOCOL},${SEPOLIA_RPC},${ETHERSCAN_API_KEY},)

deploy-protocol-mainnet:
	@echo "Deploying OTC protocol to Mainnet..."
	$(call run_script_verify,${DEPLOY_SCRIPT_PROTOCOL},${MAINNET_RPC},${ETHERSCAN_API_KEY},)

deploy-protocol-polygon:
	@echo "Deploying OTC protocol to Polygon..."
	$(call run_script_verify,${DEPLOY_SCRIPT_PROTOCOL},${POLYGON_RPC},${POLYGONSCAN_API_KEY},--legacy)

deploy-protocol-bsc:
	@echo "Deploying OTC protocol to BSC..."
	$(call run_script_verify,${DEPLOY_SCRIPT_PROTOCOL},${BSC_RPC},${BSCSCAN_API_KEY},)

# Registry-only deploy.
deploy-registry-local:
	@echo "Deploying OTCFactoryRegistry to local network..."
	$(call run_script,${DEPLOY_SCRIPT_REGISTRY},${LOCAL_RPC_URL},--broadcast)

deploy-registry-sepolia:
	@echo "Deploying OTCFactoryRegistry to Sepolia..."
	$(call run_script_verify,${DEPLOY_SCRIPT_REGISTRY},${SEPOLIA_RPC},${ETHERSCAN_API_KEY},)

deploy-registry-mainnet:
	@echo "Deploying OTCFactoryRegistry to Mainnet..."
	$(call run_script_verify,${DEPLOY_SCRIPT_REGISTRY},${MAINNET_RPC},${ETHERSCAN_API_KEY},)

deploy-registry-polygon:
	@echo "Deploying OTCFactoryRegistry to Polygon..."
	$(call run_script_verify,${DEPLOY_SCRIPT_REGISTRY},${POLYGON_RPC},${POLYGONSCAN_API_KEY},--legacy)

deploy-registry-bsc:
	@echo "Deploying OTCFactoryRegistry to BSC..."
	$(call run_script_verify,${DEPLOY_SCRIPT_REGISTRY},${BSC_RPC},${BSCSCAN_API_KEY},)

# Add an operator factory to an existing registry.
deploy-factory-local:
	@echo "Deploying OTCOperatorFactory through existing registry on local network..."
	$(call run_script,${DEPLOY_SCRIPT_FACTORY},${LOCAL_RPC_URL},--broadcast)

deploy-factory-sepolia:
	@echo "Deploying OTCOperatorFactory through existing registry on Sepolia..."
	$(call run_script_verify,${DEPLOY_SCRIPT_FACTORY},${SEPOLIA_RPC},${ETHERSCAN_API_KEY},)

deploy-factory-mainnet:
	@echo "Deploying OTCOperatorFactory through existing registry on Mainnet..."
	$(call run_script_verify,${DEPLOY_SCRIPT_FACTORY},${MAINNET_RPC},${ETHERSCAN_API_KEY},)

deploy-factory-polygon:
	@echo "Deploying OTCOperatorFactory through existing registry on Polygon..."
	$(call run_script_verify,${DEPLOY_SCRIPT_FACTORY},${POLYGON_RPC},${POLYGONSCAN_API_KEY},--legacy)

deploy-factory-bsc:
	@echo "Deploying OTCOperatorFactory through existing registry on BSC..."
	$(call run_script_verify,${DEPLOY_SCRIPT_FACTORY},${BSC_RPC},${BSCSCAN_API_KEY},)

# Deploy a client vault through an existing operator factory.
deploy-vault-local:
	@echo "Deploying client vault through existing factory on local network..."
	$(call run_script,${DEPLOY_SCRIPT_VAULT},${LOCAL_RPC_URL},--broadcast)

deploy-vault-sepolia:
	@echo "Deploying client vault through existing factory on Sepolia..."
	$(call run_script,${DEPLOY_SCRIPT_VAULT},${SEPOLIA_RPC},--broadcast)

deploy-vault-mainnet:
	@echo "Deploying client vault through existing factory on Mainnet..."
	$(call run_script,${DEPLOY_SCRIPT_VAULT},${MAINNET_RPC},--broadcast)

deploy-vault-polygon:
	@echo "Deploying client vault through existing factory on Polygon..."
	$(call run_script,${DEPLOY_SCRIPT_VAULT},${POLYGON_RPC},--broadcast --legacy)

deploy-vault-bsc:
	@echo "Deploying client vault through existing factory on BSC..."
	$(call run_script,${DEPLOY_SCRIPT_VAULT},${BSC_RPC},--broadcast)

# Dry-runs simulate without broadcasting.
deploy-protocol-dry-run-local:
	@echo "Simulating OTC protocol deployment to local network..."
	$(call run_script,${DEPLOY_SCRIPT_PROTOCOL},${LOCAL_RPC_URL},)

deploy-protocol-dry-run-sepolia:
	@echo "Simulating OTC protocol deployment to Sepolia..."
	$(call run_script,${DEPLOY_SCRIPT_PROTOCOL},${SEPOLIA_RPC},)

deploy-protocol-dry-run-mainnet:
	@echo "Simulating OTC protocol deployment to Mainnet..."
	$(call run_script,${DEPLOY_SCRIPT_PROTOCOL},${MAINNET_RPC},)

deploy-protocol-dry-run-polygon:
	@echo "Simulating OTC protocol deployment to Polygon..."
	$(call run_script,${DEPLOY_SCRIPT_PROTOCOL},${POLYGON_RPC},)

deploy-protocol-dry-run-bsc:
	@echo "Simulating OTC protocol deployment to BSC..."
	$(call run_script,${DEPLOY_SCRIPT_PROTOCOL},${BSC_RPC},)

deploy-registry-dry-run-local:
	@echo "Simulating OTCFactoryRegistry deployment to local network..."
	$(call run_script,${DEPLOY_SCRIPT_REGISTRY},${LOCAL_RPC_URL},)

deploy-registry-dry-run-sepolia:
	@echo "Simulating OTCFactoryRegistry deployment to Sepolia..."
	$(call run_script,${DEPLOY_SCRIPT_REGISTRY},${SEPOLIA_RPC},)

deploy-registry-dry-run-mainnet:
	@echo "Simulating OTCFactoryRegistry deployment to Mainnet..."
	$(call run_script,${DEPLOY_SCRIPT_REGISTRY},${MAINNET_RPC},)

deploy-registry-dry-run-polygon:
	@echo "Simulating OTCFactoryRegistry deployment to Polygon..."
	$(call run_script,${DEPLOY_SCRIPT_REGISTRY},${POLYGON_RPC},)

deploy-registry-dry-run-bsc:
	@echo "Simulating OTCFactoryRegistry deployment to BSC..."
	$(call run_script,${DEPLOY_SCRIPT_REGISTRY},${BSC_RPC},)

deploy-factory-dry-run-local:
	@echo "Simulating OTCOperatorFactory deployment to local network..."
	$(call run_script,${DEPLOY_SCRIPT_FACTORY},${LOCAL_RPC_URL},)

deploy-factory-dry-run-sepolia:
	@echo "Simulating OTCOperatorFactory deployment to Sepolia..."
	$(call run_script,${DEPLOY_SCRIPT_FACTORY},${SEPOLIA_RPC},)

deploy-factory-dry-run-mainnet:
	@echo "Simulating OTCOperatorFactory deployment to Mainnet..."
	$(call run_script,${DEPLOY_SCRIPT_FACTORY},${MAINNET_RPC},)

deploy-factory-dry-run-polygon:
	@echo "Simulating OTCOperatorFactory deployment to Polygon..."
	$(call run_script,${DEPLOY_SCRIPT_FACTORY},${POLYGON_RPC},)

deploy-factory-dry-run-bsc:
	@echo "Simulating OTCOperatorFactory deployment to BSC..."
	$(call run_script,${DEPLOY_SCRIPT_FACTORY},${BSC_RPC},)

deploy-vault-dry-run-local:
	@echo "Simulating client vault deployment to local network..."
	$(call run_script,${DEPLOY_SCRIPT_VAULT},${LOCAL_RPC_URL},)

deploy-vault-dry-run-sepolia:
	@echo "Simulating client vault deployment to Sepolia..."
	$(call run_script,${DEPLOY_SCRIPT_VAULT},${SEPOLIA_RPC},)

deploy-vault-dry-run-mainnet:
	@echo "Simulating client vault deployment to Mainnet..."
	$(call run_script,${DEPLOY_SCRIPT_VAULT},${MAINNET_RPC},)

deploy-vault-dry-run-polygon:
	@echo "Simulating client vault deployment to Polygon..."
	$(call run_script,${DEPLOY_SCRIPT_VAULT},${POLYGON_RPC},)

deploy-vault-dry-run-bsc:
	@echo "Simulating client vault deployment to BSC..."
	$(call run_script,${DEPLOY_SCRIPT_VAULT},${BSC_RPC},)

define verify_contract
	@if [ -z "${CONTRACT_ADDRESS}" ]; then echo "Error: CONTRACT_ADDRESS not set"; exit 1; fi
	forge verify-contract ${CONTRACT_ADDRESS} $(1) --etherscan-api-key $(2) --constructor-args "${CONSTRUCTOR_ARGS}"
endef

verify-registry:
	$(call verify_contract,src/OTCFactoryRegistry.sol:OTCFactoryRegistry,${ETHERSCAN_API_KEY})

verify-factory:
	$(call verify_contract,src/OTCOperatorFactory.sol:OTCOperatorFactory,${ETHERSCAN_API_KEY})

verify-client-vault:
	$(call verify_contract,src/OTCClientVault.sol:OTCClientVault,${ETHERSCAN_API_KEY})

verify-client-vault-light:
	$(call verify_contract,src/OTCClientVaultLight.sol:OTCClientVaultLight,${ETHERSCAN_API_KEY})

dev-setup: install setup-env build test
	@echo "Development environment setup completed!"

check: build test lint
	@echo "All checks passed!"

help:
	@echo "Available commands:"
	@echo "  make build                         - Build contracts"
	@echo "  make test                          - Run tests"
	@echo "  make test-coverage                 - Run coverage"
	@echo "  make format                        - Format Solidity"
	@echo "  make lint                          - Check Solidity formatting"
	@echo "  make setup-env                     - Create .env from .env.example"
	@echo ""
	@echo "Full protocol deploy:"
	@echo "  make deploy-protocol-local"
	@echo "  make deploy-protocol-sepolia"
	@echo "  make deploy-protocol-mainnet"
	@echo "  make deploy-protocol-polygon"
	@echo "  make deploy-protocol-bsc"
	@echo ""
	@echo "Smaller deploy scripts:"
	@echo "  make deploy-registry-<network>"
	@echo "  make deploy-factory-<network>"
	@echo "  make deploy-vault-<network>"
	@echo ""
	@echo "Dry-run examples:"
	@echo "  make deploy-protocol-dry-run-local"
	@echo "  make deploy-registry-dry-run-sepolia"
	@echo "  make deploy-factory-dry-run-mainnet"
	@echo "  make deploy-vault-dry-run-bsc"
	@echo ""
	@echo "Standalone verification targets:"
	@echo "  make verify-registry CONTRACT_ADDRESS=0x... CONSTRUCTOR_ARGS=0x..."
	@echo "  make verify-factory CONTRACT_ADDRESS=0x... CONSTRUCTOR_ARGS=0x..."
	@echo "  make verify-client-vault CONTRACT_ADDRESS=0x..."
	@echo "  make verify-client-vault-light CONTRACT_ADDRESS=0x..."
