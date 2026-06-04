# Makefile for OTC contract deployment and management

.PHONY: all build test clean install format lint gas-report test-coverage setup-env check dev-setup help
.PHONY: deploy-otc deploy-otcv2 deploy-local deploy-sepolia deploy-mainnet deploy-polygon deploy-bsc
.PHONY: deploy-otc-local deploy-otc-sepolia deploy-otc-mainnet deploy-otc-polygon deploy-otc-bsc
.PHONY: deploy-otcv2-local deploy-otcv2-sepolia deploy-otcv2-mainnet deploy-otcv2-polygon deploy-otcv2-bsc
.PHONY: deploy-dry-run deploy-dry-run-local deploy-dry-run-sepolia deploy-dry-run-mainnet deploy-dry-run-polygon deploy-dry-run-bsc
.PHONY: deploy-otc-dry-run-local deploy-otc-dry-run-sepolia deploy-otc-dry-run-mainnet deploy-otc-dry-run-polygon deploy-otc-dry-run-bsc
.PHONY: deploy-otcv2-dry-run-local deploy-otcv2-dry-run-sepolia deploy-otcv2-dry-run-mainnet deploy-otcv2-dry-run-polygon deploy-otcv2-dry-run-bsc
.PHONY: verify verify-sepolia verify-mainnet verify-polygon verify-bsc
.PHONY: verify-otc verify-otcv2 verify-otc-sepolia verify-otc-mainnet verify-otc-polygon verify-otc-bsc
.PHONY: verify-otcv2-sepolia verify-otcv2-mainnet verify-otcv2-polygon verify-otcv2-bsc

-include .env

LOCAL_RPC_URL := http://127.0.0.1:8545

SEPOLIA_RPC := ${RPC_URL_SEPOLIA}
MAINNET_RPC := ${RPC_URL_MAINNET}
POLYGON_RPC := ${RPC_URL_POLYGON}
BSC_RPC := ${RPC_URL_BSC}

DEPLOY_SCRIPT_OTC := script/OTC.s.sol:OTCScript
DEPLOY_SCRIPT_OTCv2 := script/OTCv2.s.sol:OTCv2Script

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
	rm -f deployment-*.txt
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
		echo ".env file created. Please edit it with your configuration."; \
	else \
		echo ".env file already exists."; \
	fi

# OTC Deploy commands
deploy-otc-local:
	forge clean
	@echo "Deploying OTC to local network..."
	forge script ${DEPLOY_SCRIPT_OTC} \
		--rpc-url ${LOCAL_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

deploy-otc-sepolia:
	forge clean
	@echo "Deploying OTC to Sepolia test network..."
	forge script ${DEPLOY_SCRIPT_OTC} \
		--rpc-url ${SEPOLIA_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		-vvv

deploy-otc-mainnet:
	forge clean
	@echo "Deploying OTC to Mainnet..."
	forge script ${DEPLOY_SCRIPT_OTC} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		-vvv

deploy-otc-polygon:
	forge clean
	@echo "Deploying OTC to Polygon network..."
	forge script ${DEPLOY_SCRIPT_OTC} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv

deploy-otc-bsc:
	forge clean
	@echo "Deploying OTC to BSC network..."
	forge script ${DEPLOY_SCRIPT_OTC} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		-vvv

# OTCv2 Deploy commands
deploy-otcv2-local:
	forge clean
	@echo "Deploying OTCv2 to local network..."
	forge script ${DEPLOY_SCRIPT_OTCv2} \
		--rpc-url ${LOCAL_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

deploy-otcv2-sepolia:
	forge clean
	@echo "Deploying OTCv2 to Sepolia test network..."
	forge script ${DEPLOY_SCRIPT_OTCv2} \
		--rpc-url ${SEPOLIA_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		-vvv

deploy-otcv2-mainnet:
	forge clean
	@echo "Deploying OTCv2 to Mainnet..."
	forge script ${DEPLOY_SCRIPT_OTCv2} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		-vvv

deploy-otcv2-polygon:
	forge clean
	@echo "Deploying OTCv2 to Polygon network..."
	forge script ${DEPLOY_SCRIPT_OTCv2} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv

deploy-otcv2-bsc:
	forge clean
	@echo "Deploying OTCv2 to BSC network..."
	forge script ${DEPLOY_SCRIPT_OTCv2} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		-vvv

# Legacy deploy commands (default to OTC)
deploy-local: deploy-otc-local
deploy-sepolia: deploy-otc-sepolia
deploy-mainnet: deploy-otc-mainnet
deploy-polygon: deploy-otc-polygon
deploy-bsc: deploy-otc-bsc

# OTC Deploy dry-run commands (simulate without broadcasting)
deploy-otc-dry-run-local:
	forge clean
	@echo "Simulating OTC deployment to local network..."
	forge script ${DEPLOY_SCRIPT_OTC} \
		--rpc-url ${LOCAL_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-otc-dry-run-sepolia:
	forge clean
	@echo "Simulating OTC deployment to Sepolia test network..."
	forge script ${DEPLOY_SCRIPT_OTC} \
		--rpc-url ${SEPOLIA_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-otc-dry-run-mainnet:
	forge clean
	@echo "Simulating OTC deployment to Mainnet..."
	forge script ${DEPLOY_SCRIPT_OTC} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-otc-dry-run-polygon:
	forge clean
	@echo "Simulating OTC deployment to Polygon network..."
	forge script ${DEPLOY_SCRIPT_OTC} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-otc-dry-run-bsc:
	forge clean
	@echo "Simulating OTC deployment to BSC network..."
	forge script ${DEPLOY_SCRIPT_OTC} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

# OTCv2 Deploy dry-run commands (simulate without broadcasting)
deploy-otcv2-dry-run-local:
	forge clean
	@echo "Simulating OTCv2 deployment to local network..."
	forge script ${DEPLOY_SCRIPT_OTCv2} \
		--rpc-url ${LOCAL_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-otcv2-dry-run-sepolia:
	forge clean
	@echo "Simulating OTCv2 deployment to Sepolia test network..."
	forge script ${DEPLOY_SCRIPT_OTCv2} \
		--rpc-url ${SEPOLIA_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-otcv2-dry-run-mainnet:
	forge clean
	@echo "Simulating OTCv2 deployment to Mainnet..."
	forge script ${DEPLOY_SCRIPT_OTCv2} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-otcv2-dry-run-polygon:
	forge clean
	@echo "Simulating OTCv2 deployment to Polygon network..."
	forge script ${DEPLOY_SCRIPT_OTCv2} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-otcv2-dry-run-bsc:
	forge clean
	@echo "Simulating OTCv2 deployment to BSC network..."
	forge script ${DEPLOY_SCRIPT_OTCv2} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

# Legacy dry-run commands (default to OTC)
deploy-dry-run-local: deploy-otc-dry-run-local
deploy-dry-run-sepolia: deploy-otc-dry-run-sepolia
deploy-dry-run-mainnet: deploy-otc-dry-run-mainnet
deploy-dry-run-polygon: deploy-otc-dry-run-polygon
deploy-dry-run-bsc: deploy-otc-dry-run-bsc

# OTC Verify commands
verify-otc-sepolia:
	@echo "Verifying OTC contract on Sepolia..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/OTC.sol:OTC \
		--chain-id $$(cast chain-id --rpc-url ${SEPOLIA_RPC}) \
		--etherscan-api-key ${ETHERSCAN_API_KEY}
	@echo "Verification completed!"

verify-otc-mainnet:
	@echo "Verifying OTC contract on Mainnet..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/OTC.sol:OTC \
		--chain-id $$(cast chain-id --rpc-url ${MAINNET_RPC}) \
		--etherscan-api-key ${ETHERSCAN_API_KEY}
	@echo "Verification completed!"

verify-otc-polygon:
	@echo "Verifying OTC contract on Polygon..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/OTC.sol:OTC \
		--chain-id $$(cast chain-id --rpc-url ${POLYGON_RPC}) \
		--etherscan-api-key ${ETHERSCAN_API_KEY}
	@echo "Verification completed!"

verify-otc-bsc:
	@echo "Verifying OTC contract on BSC..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/OTC.sol:OTC \
		--chain-id $$(cast chain-id --rpc-url ${BSC_RPC}) \
		--etherscan-api-key ${BSCSCAN_API_KEY}
	@echo "Verification completed!"

# OTCv2 Verify commands
verify-otcv2-sepolia:
	@echo "Verifying OTCv2 contract on Sepolia..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/OTCv2.sol:OTCv2 \
		--chain-id $$(cast chain-id --rpc-url ${SEPOLIA_RPC}) \
		--etherscan-api-key ${ETHERSCAN_API_KEY}
	@echo "Verification completed!"

verify-otcv2-mainnet:
	@echo "Verifying OTCv2 contract on Mainnet..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/OTCv2.sol:OTCv2 \
		--chain-id $$(cast chain-id --rpc-url ${MAINNET_RPC}) \
		--etherscan-api-key ${ETHERSCAN_API_KEY}
	@echo "Verification completed!"

verify-otcv2-polygon:
	@echo "Verifying OTCv2 contract on Polygon..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/OTCv2.sol:OTCv2 \
		--chain-id $$(cast chain-id --rpc-url ${POLYGON_RPC}) \
		--etherscan-api-key ${ETHERSCAN_API_KEY}
	@echo "Verification completed!"

verify-otcv2-bsc:
	@echo "Verifying OTCv2 contract on BSC..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set. Use: make verify-otcv2-bsc CONTRACT_ADDRESS=0x..."; \
		exit 1; \
	fi
	@if [ -z "${BSCSCAN_API_KEY}" ]; then \
		echo "Error: BSCSCAN_API_KEY not set in .env file"; \
		exit 1; \
	fi
	@if [ -z "${INPUT_TOKEN}" ]; then \
		echo "Error: INPUT_TOKEN not set in .env file (needed for constructor argument)"; \
		exit 1; \
	fi
	@if [ -z "${OUTPUT_TOKEN}" ]; then \
		echo "Error: OUTPUT_TOKEN not set in .env file (needed for constructor argument)"; \
		exit 1; \
	fi
	@if [ -z "${ADMIN_ADDRESS}" ]; then \
		echo "Error: ADMIN_ADDRESS not set in .env file (needed for constructor argument)"; \
		exit 1; \
	fi
	@if [ -z "${CLIENT_ADDRESS}" ]; then \
		echo "Error: CLIENT_ADDRESS not set in .env file (needed for constructor argument)"; \
		exit 1; \
	fi
	@echo "Encoding constructor arguments..."
	@CONSTRUCTOR_ARGS=$$(cast abi-encode "constructor(address,address,address,address,(uint256,uint256)[],uint256,uint256,uint256,bool)" ${INPUT_TOKEN} ${OUTPUT_TOKEN} ${ADMIN_ADDRESS} ${CLIENT_ADDRESS} "[]" ${BUYBACK_PRICE} ${MIN_OUTPUT_AMOUNT} ${MIN_INPUT_AMOUNT} ${IS_SUPPLY}); \
	forge verify-contract $(CONTRACT_ADDRESS) src/OTCv2.sol:OTCv2 \
		--chain bsc \
		--rpc-url ${BSC_RPC} \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--constructor-args "$$CONSTRUCTOR_ARGS"
	@echo "Verification completed!"

# Legacy verify commands (default to OTC)
verify-sepolia: verify-otc-sepolia
verify-mainnet: verify-otc-mainnet
verify-polygon: verify-otc-polygon
verify-bsc: verify-otc-bsc

# Development helpers
dev-setup: install setup-env build test
	@echo "Development environment setup completed!"

check: build test lint
	@echo "All checks passed!"

help:
	@echo "Available commands:"
	@echo "  make build                    - Build contracts"
	@echo "  make test                     - Run tests"
	@echo "  make test-coverage            - Run tests with coverage"
	@echo "  make clean                    - Clean build artifacts"
	@echo "  make format                   - Format code"
	@echo "  make lint                     - Run linter"
	@echo "  make gas-report               - Generate gas usage report"
	@echo "  make install                  - Install dependencies"
	@echo "  make setup-env                - Setup environment file from example"
	@echo "  make check                    - Run all checks (build, test, lint)"
	@echo "  make dev-setup                - Complete development setup"
	@echo ""
	@echo "OTC Deploy commands:"
	@echo "  make deploy-otc-local         - Deploy OTC to local network"
	@echo "  make deploy-otc-sepolia       - Deploy OTC to Sepolia with verification"
	@echo "  make deploy-otc-mainnet       - Deploy OTC to Mainnet with verification (use with caution!)"
	@echo "  make deploy-otc-polygon       - Deploy OTC to Polygon with verification"
	@echo "  make deploy-otc-bsc           - Deploy OTC to BSC with verification"
	@echo ""
	@echo "OTCv2 Deploy commands:"
	@echo "  make deploy-otcv2-local       - Deploy OTCv2 to local network"
	@echo "  make deploy-otcv2-sepolia     - Deploy OTCv2 to Sepolia with verification"
	@echo "  make deploy-otcv2-mainnet     - Deploy OTCv2 to Mainnet with verification (use with caution!)"
	@echo "  make deploy-otcv2-polygon      - Deploy OTCv2 to Polygon with verification"
	@echo "  make deploy-otcv2-bsc         - Deploy OTCv2 to BSC with verification"
	@echo ""
	@echo "Legacy deploy commands (default to OTC):"
	@echo "  make deploy-local             - Deploy OTC to local network"
	@echo "  make deploy-sepolia           - Deploy OTC to Sepolia with verification"
	@echo "  make deploy-mainnet            - Deploy OTC to Mainnet with verification"
	@echo "  make deploy-polygon            - Deploy OTC to Polygon with verification"
	@echo "  make deploy-bsc                - Deploy OTC to BSC with verification"
	@echo ""
	@echo "OTC Deploy dry-run commands (simulate without broadcasting):"
	@echo "  make deploy-otc-dry-run-local     - Simulate OTC deployment to local network"
	@echo "  make deploy-otc-dry-run-sepolia   - Simulate OTC deployment to Sepolia"
	@echo "  make deploy-otc-dry-run-mainnet   - Simulate OTC deployment to Mainnet"
	@echo "  make deploy-otc-dry-run-polygon   - Simulate OTC deployment to Polygon"
	@echo "  make deploy-otc-dry-run-bsc        - Simulate OTC deployment to BSC"
	@echo ""
	@echo "OTCv2 Deploy dry-run commands (simulate without broadcasting):"
	@echo "  make deploy-otcv2-dry-run-local     - Simulate OTCv2 deployment to local network"
	@echo "  make deploy-otcv2-dry-run-sepolia    - Simulate OTCv2 deployment to Sepolia"
	@echo "  make deploy-otcv2-dry-run-mainnet   - Simulate OTCv2 deployment to Mainnet"
	@echo "  make deploy-otcv2-dry-run-polygon    - Simulate OTCv2 deployment to Polygon"
	@echo "  make deploy-otcv2-dry-run-bsc        - Simulate OTCv2 deployment to BSC"
	@echo ""
	@echo "Legacy dry-run commands (default to OTC):"
	@echo "  make deploy-dry-run-local     - Simulate OTC deployment to local network"
	@echo "  make deploy-dry-run-sepolia     - Simulate OTC deployment to Sepolia"
	@echo "  make deploy-dry-run-mainnet    - Simulate OTC deployment to Mainnet"
	@echo "  make deploy-dry-run-polygon    - Simulate OTC deployment to Polygon"
	@echo "  make deploy-dry-run-bsc        - Simulate OTC deployment to BSC"
	@echo ""
	@echo "OTC Verify commands:"
	@echo "  make verify-otc-sepolia        - Verify OTC contract on Sepolia (requires CONTRACT_ADDRESS)"
	@echo "  make verify-otc-mainnet        - Verify OTC contract on Mainnet (requires CONTRACT_ADDRESS)"
	@echo "  make verify-otc-polygon        - Verify OTC contract on Polygon (requires CONTRACT_ADDRESS)"
	@echo "  make verify-otc-bsc            - Verify OTC contract on BSC (requires CONTRACT_ADDRESS)"
	@echo ""
	@echo "OTCv2 Verify commands:"
	@echo "  make verify-otcv2-sepolia      - Verify OTCv2 contract on Sepolia (requires CONTRACT_ADDRESS)"
	@echo "  make verify-otcv2-mainnet      - Verify OTCv2 contract on Mainnet (requires CONTRACT_ADDRESS)"
	@echo "  make verify-otcv2-polygon      - Verify OTCv2 contract on Polygon (requires CONTRACT_ADDRESS)"
	@echo "  make verify-otcv2-bsc          - Verify OTCv2 contract on BSC (requires CONTRACT_ADDRESS)"
	@echo ""
	@echo "Legacy verify commands (default to OTC):"
	@echo "  make verify-sepolia            - Verify OTC contract on Sepolia (requires CONTRACT_ADDRESS)"
	@echo "  make verify-mainnet            - Verify OTC contract on Mainnet (requires CONTRACT_ADDRESS)"
	@echo "  make verify-polygon             - Verify OTC contract on Polygon (requires CONTRACT_ADDRESS)"
	@echo "  make verify-bsc                - Verify OTC contract on BSC (requires CONTRACT_ADDRESS)"
	@echo ""
	@echo "Before deploying, make sure to set up the required environment variables in .env file:"
	@echo "  - PRIVATE_KEY: Your private key for deployment"
	@echo "  - RPC_URL_SEPOLIA, RPC_URL_MAINNET, RPC_URL_POLYGON, RPC_URL_BSC: RPC URLs for the networks"
	@echo "  - ETHERSCAN_API_KEY: Etherscan API key (for Ethereum networks)"
	@echo "  - BSCSCAN_API_KEY: BscScan API key (for BSC network)"
	@echo "  - CONTRACT_ADDRESS: Contract address (for verification)"
	@echo ""
	@echo "Note: Deployment parameters (INPUT_TOKEN, OUTPUT_TOKEN, CLIENT_ADDRESS, etc.)"
	@echo "      should be configured in the deployment scripts before running deploy commands:"
	@echo "      - script/OTC.s.sol"
	@echo "      - script/OTCv2.s.sol"


