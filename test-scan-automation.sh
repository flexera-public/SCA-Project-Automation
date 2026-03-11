#!/bin/bash

################################################################################
# Test Script for CodeInsight Scan Automation
# This script helps you test the automation script with sample configurations
################################################################################

# Check if running with bash
if [ -z "$BASH_VERSION" ]; then
    echo "ERROR: This script requires bash. Please run with: bash $0"
    echo "Or make executable and run directly: chmod +x $0 && ./$0"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

################################################################################
# Test 1: Verify Script Exists
################################################################################
test_script_exists() {
    print_header "Test 1: Verify Automation Script Exists"
    
    SCRIPT_PATH="./codeinsight-scan-automation.sh"
    
    if [[ -f "$SCRIPT_PATH" ]]; then
        print_success "Script found: $SCRIPT_PATH"
        
        if [[ -x "$SCRIPT_PATH" ]]; then
            print_success "Script is executable"
        else
            print_warning "Script exists but is not executable"
            print_info "Run: chmod +x $SCRIPT_PATH"
        fi
        return 0
    else
        print_error "Script not found: $SCRIPT_PATH"
        return 1
    fi
}

################################################################################
# Test 2: Check Dependencies
################################################################################
test_dependencies() {
    print_header "Test 2: Check Required Dependencies"
    
    local all_ok=true
    
    # Check bash
    if command -v bash &> /dev/null; then
        print_success "bash is installed: $(bash --version | head -1)"
    else
        print_error "bash is not installed"
        all_ok=false
    fi
    
    # Check curl
    if command -v curl &> /dev/null; then
        print_success "curl is installed: $(curl --version | head -1)"
    else
        print_error "curl is not installed"
        all_ok=false
    fi
    
    # Check grep
    if command -v grep &> /dev/null; then
        print_success "grep is installed: $(grep --version | head -1)"
    else
        print_error "grep is not installed"
        all_ok=false
    fi
    
    if $all_ok; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Test 3: Verify Server Connectivity
################################################################################
test_server_connectivity() {
    print_header "Test 3: Verify CodeInsight Server Connectivity"
    
    read -p "Enter CodeInsight Server URL (e.g., http://localhost:8888): " SERVER_URL
    
    if [[ -z "$SERVER_URL" ]]; then
        print_warning "No server URL provided, skipping connectivity test"
        return 0
    fi
    
    print_info "Testing connection to: $SERVER_URL/codeinsight/api"
    
    response=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "${SERVER_URL}/codeinsight/api/projects")
    
    if [[ "$response" == "401" ]] || [[ "$response" == "403" ]]; then
        print_success "Server is reachable (Authentication required: HTTP $response)"
        return 0
    elif [[ "$response" == "200" ]]; then
        print_success "Server is reachable (HTTP $response)"
        return 0
    else
        print_error "Server connectivity test failed (HTTP $response)"
        print_info "Check if CodeInsight server is running"
        return 1
    fi
}

################################################################################
# Test 4: Validate JWT Token
################################################################################
test_jwt_token() {
    print_header "Test 4: Validate JWT Token"
    
    read -p "Enter JWT Token (or press Enter to skip): " JWT_TOKEN
    
    if [[ -z "$JWT_TOKEN" ]]; then
        print_warning "No JWT token provided, skipping token validation"
        return 0
    fi
    
    read -p "Enter Server URL (e.g., http://localhost:8888): " SERVER_URL
    
    if [[ -z "$SERVER_URL" ]]; then
        print_warning "No server URL provided, cannot validate token"
        return 0
    fi
    
    print_info "Validating token against: ${SERVER_URL}/codeinsight/api/projects"
    
    response=$(curl -s -w "\n%{http_code}" -X GET \
        "${SERVER_URL}/codeinsight/api/projects" \
        -H "Authorization: Bearer ${JWT_TOKEN}" \
        -H "Accept: application/json")
    
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" -eq 200 ]]; then
        print_success "JWT token is valid and working"
        print_info "Sample response: $(echo "$body" | head -c 100)..."
        return 0
    elif [[ "$http_code" -eq 401 ]]; then
        print_error "JWT token is invalid or expired (HTTP 401)"
        return 1
    else
        print_error "Token validation failed (HTTP $http_code)"
        return 1
    fi
}

################################################################################
# Test 5: Check Configuration in Script
################################################################################
test_script_configuration() {
    print_header "Test 5: Check Script Configuration"
    
    SCRIPT_PATH="./codeinsight-scan-automation.sh"
    
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        print_error "Script not found"
        return 1
    fi
    
    # Check if AUTH_TOKEN has been updated
    if grep -q 'AUTH_TOKEN="your-jwt-token-here"' "$SCRIPT_PATH"; then
        print_warning "AUTH_TOKEN still has default value - MUST BE UPDATED"
    else
        print_success "AUTH_TOKEN has been customized"
    fi
    
    # Extract and display current configuration
    print_info "Current configuration in script:"
    
    server_host=$(grep '^SERVER_HOST=' "$SCRIPT_PATH" | head -1 | cut -d'"' -f2)
    server_port=$(grep '^SERVER_PORT=' "$SCRIPT_PATH" | head -1 | cut -d'"' -f2)
    scan_profile=$(grep '^SCAN_PROFILE_NAME=' "$SCRIPT_PATH" | head -1 | cut -d'"' -f2)
    policy_profile=$(grep '^POLICY_PROFILE_NAME=' "$SCRIPT_PATH" | head -1 | cut -d'"' -f2)
    scanner_alias=$(grep '^SCAN_SERVER_ALIAS=' "$SCRIPT_PATH" | head -1 | cut -d'"' -f2)
    
    echo "  • Server: ${server_host}:${server_port}"
    echo "  • Scan Profile: ${scan_profile}"
    echo "  • Policy Profile: ${policy_profile}"
    echo "  • Scanner Alias: ${scanner_alias}"
    
    return 0
}

################################################################################
# Test 6: Create Sample Codebase Zip
################################################################################
test_create_sample_codebase() {
    print_header "Test 6: Create Sample Codebase for Testing"
    
    read -p "Create a sample test codebase? (y/n): " create_sample
    
    if [[ "$create_sample" != "y" ]]; then
        print_info "Skipping sample codebase creation"
        return 0
    fi
    
    SAMPLE_DIR="./test-codebase"
    SAMPLE_ZIP="./test-codebase.zip"
    
    # Create sample directory structure
    mkdir -p "$SAMPLE_DIR/src/main/java/com/example"
    mkdir -p "$SAMPLE_DIR/src/test/java/com/example"
    mkdir -p "$SAMPLE_DIR/lib"
    
    # Create sample files
    cat > "$SAMPLE_DIR/README.md" <<'EOF'
# Test Codebase

This is a sample codebase for testing CodeInsight scan automation.

## Contents
- Sample Java source files
- Empty lib directory
- Build configuration
EOF

    cat > "$SAMPLE_DIR/pom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>test-app</artifactId>
    <version>1.0.0</version>
    <dependencies>
        <dependency>
            <groupId>org.apache.commons</groupId>
            <artifactId>commons-lang3</artifactId>
            <version>3.12.0</version>
        </dependency>
    </dependencies>
</project>
EOF

    cat > "$SAMPLE_DIR/src/main/java/com/example/Application.java" <<'EOF'
package com.example;

public class Application {
    public static void main(String[] args) {
        System.out.println("Hello, CodeInsight!");
    }
}
EOF

    # Create zip file
    if command -v zip &> /dev/null; then
        cd "$(dirname "$SAMPLE_DIR")"
        zip -r "$(basename "$SAMPLE_ZIP")" "$(basename "$SAMPLE_DIR")" > /dev/null 2>&1
        cd -
        
        if [[ -f "$SAMPLE_ZIP" ]]; then
            print_success "Sample codebase created: $SAMPLE_ZIP"
            print_info "Size: $(du -h "$SAMPLE_ZIP" | cut -f1)"
            print_info "You can use this file to test the automation script"
            return 0
        else
            print_error "Failed to create zip file"
            return 1
        fi
    else
        print_error "zip command not found, cannot create sample codebase"
        return 1
    fi
}

################################################################################
# Test 7: Dry Run Test
################################################################################
test_dry_run() {
    print_header "Test 7: Dry Run (Configuration Preview)"
    
    print_info "This test validates inputs without actually running the automation"
    echo ""
    
    read -p "Enter sample codebase path: " codebase_path
    read -p "Enter sample project name: " project_name
    
    # Validate codebase path
    if [[ -z "$codebase_path" ]]; then
        print_error "Codebase path is required"
        return 1
    elif [[ ! -f "$codebase_path" ]]; then
        print_error "Codebase file does not exist: $codebase_path"
        return 1
    else
        print_success "Codebase file exists"
        print_info "File size: $(du -h "$codebase_path" | cut -f1)"
    fi
    
    # Validate project name
    if [[ -z "$project_name" ]]; then
        print_error "Project name is required"
        return 1
    else
        print_success "Project name is valid: $project_name"
    fi
    
    print_success "Dry run validation passed!"
    echo ""
    print_info "To run the actual automation, execute:"
    echo "  ./codeinsight-scan-automation.sh"
    
    return 0
}

################################################################################
# Main Test Execution
################################################################################
main() {
    clear
    print_header "CodeInsight Scan Automation - Test Suite"
    echo ""
    
    # Run all tests
    test_script_exists
    echo ""
    
    test_dependencies
    echo ""
    
    test_server_connectivity
    echo ""
    
    test_jwt_token
    echo ""
    
    test_script_configuration
    echo ""
    
    test_create_sample_codebase
    echo ""
    
    test_dry_run
    echo ""
    
    print_header "Test Suite Complete"
    echo ""
    print_info "If all tests passed, you're ready to run the automation script!"
    print_info "Execute: ./codeinsight-scan-automation.sh"
    echo ""
}

# Execute main function
main
