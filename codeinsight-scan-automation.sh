#!/bin/bash

################################################################################
# CodeInsight Project Automation Script
# This script automates project creation, codebase upload, scanning, and 
# inventory validation using CodeInsight REST APIs
#
# Usage:
#   Interactive mode: ./codeinsight-scan-automation.sh
#   CLI mode: ./codeinsight-scan-automation.sh <codebase_path> <project_name> [scanner_alias] [server_url] [auth_token]
#   Jenkins mode: Use environment variables (CI_CODEBASE_PATH, CI_PROJECT_NAME, etc.)
################################################################################

# Check if running with bash
if [ -z "$BASH_VERSION" ]; then
    echo "ERROR: This script requires bash. Please run with: bash $0"
    echo "Or make executable and run directly: chmod +x $0 && ./$0"
    exit 1
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Function: Display usage help
################################################################################
show_usage() {
    echo "Usage: $0 [OPTIONS] [CODEBASE_PATH] [PROJECT_NAME] [SCANNER_ALIAS] [SERVER_URL] [AUTH_TOKEN]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Arguments (optional - will be prompted if not provided):"
    echo "  CODEBASE_PATH           Full path to zip file (e.g., /path/to/codebase.zip)"
    echo "  PROJECT_NAME            Name of the CodeInsight project"
    echo "  SCANNER_ALIAS           Scanner alias (default: 'scanner')"
    echo "  SERVER_URL              Full server URL (e.g., http://host:8888 or https://host:8443)"
    echo "  AUTH_TOKEN              JWT authentication token"
    echo ""
    echo "Environment Variables (for Jenkins/CI integration):"
    echo "  CI_CODEBASE_PATH        Path to codebase zip file"
    echo "  CI_PROJECT_NAME         Project name"
    echo "  CI_SCANNER_ALIAS        Scanner alias (optional)"
    echo "  CI_SERVER_URL           CodeInsight server URL (http://host:port or https://host:port)"
    echo "  CI_AUTH_TOKEN           JWT token for authentication"
    echo ""
    echo "Examples:"
    echo "  # Interactive mode (prompts for all inputs)"
    echo "  $0"
    echo ""
    echo "  # CLI mode with arguments"
    echo "  $0 /path/to/code.zip MyProject scanner http://localhost:8888 <token>"
    echo ""
    echo "  # Jenkins mode (using environment variables)"
    echo "  export CI_SERVER_URL=\"https://secure-server.com:8443\""
    echo "  export CI_AUTH_TOKEN=\"your-jwt-token\""
    echo "  export CI_CODEBASE_PATH=\"/path/to/code.zip\""
    echo "  export CI_PROJECT_NAME=\"MyProject\""
    echo "  $0"
    exit 0
}

# Parse help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_usage
fi

# Default Configuration (can be overridden by arguments or environment variables)
SERVER_URL="${CI_SERVER_URL:-http://scau20-mysql8.flexera.com:8888}"
AUTH_TOKEN="${CI_AUTH_TOKEN:-eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJhZG1pbiIsInVzZXJJZCI6MSwiaWF0IjoxNzcwNzA3MzE0fQ.UP40pvhzNnkBCdBuxB6dyu987mIoiVF77fZ-8Ag_Rh9L3cV-8sQdv19u_B4y_DxVl-oXw-tuWRRdD3lYXfnDVQ}"

# Build BASE_URL from SERVER_URL
BASE_URL="${SERVER_URL}/codeinsight/api"

# Detect SSL and set curl flags for certificate bypass
CURL_SSL_FLAGS=""
if [[ "$SERVER_URL" == https://* ]]; then
    CURL_SSL_FLAGS="-k"
fi

# Debug mode (set to true to see curl commands)
DEBUG_MODE=true

# Scan configuration (adjust as needed)
SCAN_PROFILE_NAME="Basic Scan Profile (Without CL)"
POLICY_PROFILE_NAME="Default License Policy Profile"
SCAN_SERVER_ALIAS="${CI_SCANNER_ALIAS:-scanner}"
AUTO_PUBLISH="true"
MARK_FILES_AS_REVIEWED="false"
PROJECT_OWNER="admin"
RISK_LEVEL="MEDIUM"
PRIVATE_PROJECT="false"

# Retry configuration for scan status check
RETRY_INTERVAL_MS=60000  # 60 seconds in milliseconds
RETRY_COUNT=20
RETRY_INTERVAL_SEC=$((RETRY_INTERVAL_MS / 1000))

# Parse command-line arguments if provided
if [[ -n "$1" ]] && [[ "$1" != "-"* ]]; then
    # Only override if argument is non-empty
    if [[ -n "$1" ]]; then CODEBASE_PATH="$1"; fi
    if [[ -n "$2" ]]; then PROJECT_NAME="$2"; fi
    if [[ -n "$3" ]]; then SCAN_SERVER_ALIAS="$3"; fi
    if [[ -n "$4" ]]; then 
        SERVER_URL="$4"
        # Rebuild BASE_URL if SERVER_URL changed
        BASE_URL="${SERVER_URL}/codeinsight/api"
        
        # Re-detect SSL if SERVER_URL changed
        if [[ "$SERVER_URL" == https://* ]]; then
            CURL_SSL_FLAGS="-k"
        else
            CURL_SSL_FLAGS=""
        fi
    fi
    if [[ -n "$5" ]]; then AUTH_TOKEN="$5"; fi
fi

################################################################################
# Function: Print colored messages (output to stderr to avoid command substitution capture)
################################################################################
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

print_debug() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1" >&2
    fi
}

################################################################################
# Function: Validate configuration
################################################################################
validate_configuration() {
    if [[ "$AUTH_TOKEN" == "your-jwt-token-here" ]] || [[ -z "$AUTH_TOKEN" ]]; then
        print_error "JWT token not configured!"
        print_error "Please edit the script and update the AUTH_TOKEN variable with a valid JWT token."
        echo "" >&2
        print_info "To get a JWT token:" >&2
        echo "  1. Log in to CodeInsight web UI" >&2
        echo "  2. Open browser developer tools (F12)" >&2
        echo "  3. Go to Application/Storage > Local Storage" >&2
        echo "  4. Find 'jwtToken' and copy its value" >&2
        echo "" >&2
        print_info "Or use the REST API to generate a token:" >&2
        echo "  curl -X POST http://localhost:8888/codeinsight/api/login \\" >&2
        echo "       -H 'Content-Type: application/json' \\" >&2
        echo "       -d '{\"username\":\"admin\",\"password\":\"yourpassword\"}'" >&2
        exit 1
    fi
}

################################################################################
# Function: Validate input parameters
################################################################################
validate_inputs() {
    if [[ -z "$CODEBASE_PATH" ]]; then
        print_error "Codebase path is required"
        exit 1
    fi

    if [[ ! -f "$CODEBASE_PATH" ]]; then
        print_error "Codebase file not found: $CODEBASE_PATH"
        exit 1
    fi

    if [[ -z "$PROJECT_NAME" ]]; then
        print_error "Project name is required"
        exit 1
    fi

    print_success "Input validation passed"
}

################################################################################
# Function: Check if project exists
################################################################################
check_project_exists() {
    local project_name=$1
    print_info "Checking if project '$project_name' exists..."

    # URL encode the project name
    local encoded_name=$(echo "$project_name" | sed 's/ /%20/g')

    print_debug "curl -X GET '${BASE_URL}/project/id?projectName=${encoded_name}' \\"
    print_debug "  -H 'Authorization: Bearer ${AUTH_TOKEN}' \\"
    print_debug "  -H 'Accept: application/json'"

    response=$(curl -s -w "\n%{http_code}" $CURL_SSL_FLAGS -X GET \
        "${BASE_URL}/project/id?projectName=${encoded_name}" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -H "Accept: application/json")

    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -eq 200 ]]; then
        # Extract project ID from response format: {"Content: ": 330}
        project_id=$(echo "$body" | grep -o '"Content: *" *: *[0-9]*' | grep -o '[0-9]*')
        if [[ -n "$project_id" ]]; then
            print_info "Project exists with ID: $project_id"
            echo "$project_id"
            return 0
        fi
    elif [[ "$http_code" -eq 400 ]]; then
        # Project doesn't exist (InvalidProjectNameParam error)
        print_info "Project does not exist (will be created)"
    else
        print_error "Unexpected response code: $http_code"
        print_error "Response: $body"
    fi

    echo ""
    return 1
}

################################################################################
# Function: Create new project
################################################################################
create_project() {
    local project_name=$1
    local description=${2:-"Created via automation script"}

    print_info "Creating new project: $project_name"

    json_payload=$(cat <<EOF
{
  "name": "$project_name",
  "description": "$description",
  "scanProfileName": "$SCAN_PROFILE_NAME",
  "policyProfileName": "$POLICY_PROFILE_NAME",
  "autoPublish": $AUTO_PUBLISH,
  "markAssociatedFilesAsReviewed": $MARK_FILES_AS_REVIEWED,
  "owner": "$PROJECT_OWNER",
  "risk": "$RISK_LEVEL",
  "privateProject": $PRIVATE_PROJECT,
  "scanServerAlias": "$SCAN_SERVER_ALIAS"
}
EOF
)

    print_debug "curl -X POST '${BASE_URL}/projects' \\"
    print_debug "  -H 'Authorization: Bearer ${AUTH_TOKEN}' \\"
    print_debug "  -H 'Content-Type: application/json' \\"
    print_debug "  -H 'Accept: application/json' \\"
    print_debug "  -d '${json_payload}'"

    response=$(curl -s -w "\n%{http_code}" $CURL_SSL_FLAGS -X POST \
        "${BASE_URL}/projects" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$json_payload")

    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -eq 201 ]]; then
        project_id=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
        if [[ -n "$project_id" ]]; then
            print_success "Project created successfully with ID: $project_id"
            echo "$project_id"
            return 0
        fi
    fi

    print_error "Failed to create project. HTTP Code: $http_code"
    print_error "Response: $body"
    exit 1
}

################################################################################
# Function: Upload codebase to project
################################################################################
upload_codebase() {
    local project_id=$1
    local codebase_path=$2

    print_info "Uploading codebase for project ID: $project_id"
    print_info "Codebase file: $codebase_path"

    print_debug "curl -X POST '${BASE_URL}/project/uploadProjectCodebase?projectId=${project_id}&deleteExistingFileOnServer=true&expansionLevel=1' \\"
    print_debug "  -H 'Authorization: Bearer ${AUTH_TOKEN}' \\"
    print_debug "  -H 'Accept: application/json' \\"
    print_debug "  -H 'Content-Type: application/octet-stream' \\"
    print_debug "  --data-binary '@${codebase_path}'"

    response=$(curl -s -w "\n%{http_code}" $CURL_SSL_FLAGS -X POST \
        "${BASE_URL}/project/uploadProjectCodebase?projectId=${project_id}&deleteExistingFileOnServer=true&expansionLevel=1" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${codebase_path}")

    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -eq 200 ]]; then
        print_success "Codebase uploaded successfully"
        return 0
    fi

    print_error "Failed to upload codebase. HTTP Code: $http_code"
    print_error "Response: $body"
    exit 1
}

################################################################################
# Function: Trigger project scan
################################################################################
trigger_scan() {
    local project_id=$1

    print_info "Triggering scan for project ID: $project_id"

    print_debug "curl -X POST '${BASE_URL}/scanResource/projectScan/${project_id}?fullRescan=false' \\"
    print_debug "  -H 'Authorization: Bearer ${AUTH_TOKEN}' \\"
    print_debug "  -H 'Accept: application/json'"

    response=$(curl -s -w "\n%{http_code}" $CURL_SSL_FLAGS -X POST \
        "${BASE_URL}/scanResource/projectScan/${project_id}?fullRescan=false" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -H "Accept: application/json")

    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -eq 200 ]]; then
        # Extract task ID from response (looking for numeric value)
        task_id=$(echo "$body" | grep -o '"Content: "[0-9]*' | grep -o '[0-9]*')
        if [[ -z "$task_id" ]]; then
            # Try alternative pattern
            task_id=$(echo "$body" | grep -o '[0-9]\+' | head -1)
        fi

        if [[ -n "$task_id" ]]; then
            print_success "Scan triggered successfully. Task ID: $task_id"
            echo "$task_id"
            return 0
        fi
    fi

    print_error "Failed to trigger scan. HTTP Code: $http_code"
    print_error "Response: $body"
    exit 1
}

################################################################################
# Function: Check scan status
################################################################################
check_scan_status() {
    local task_id=$1

    print_debug "curl -X GET '${BASE_URL}/project/scanStatus/${task_id}' \\"
    print_debug "  -H 'Authorization: Bearer ${AUTH_TOKEN}' \\"
    print_debug "  -H 'Accept: application/json'"

    response=$(curl -s -w "\n%{http_code}" $CURL_SSL_FLAGS -X GET \
        "${BASE_URL}/project/scanStatus/${task_id}" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -H "Accept: application/json")

    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    print_debug "Response body: $body"

    if [[ "$http_code" -eq 200 ]]; then
        # Extract status from response format: {"Content: ": "completed"}
        status=$(echo "$body" | grep -o '"Content: *" *: *"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/')
        
        if [[ -z "$status" ]]; then
            # Try alternative pattern for different API response format
            status=$(echo "$body" | grep -oP '(?<="taskState":")[^"]*' | head -1)
        fi
        
        if [[ -z "$status" ]]; then
            # Try simple extraction
            status=$(echo "$body" | grep -o '"[^"]*"' | tail -1 | tr -d '"')
        fi

        echo "$status"
        return 0
    fi

    echo "ERROR"
    return 1
}

################################################################################
# Function: Wait for scan completion
################################################################################
wait_for_scan_completion() {
    local task_id=$1

    print_info "Waiting for scan to complete (Task ID: $task_id)"
    print_info "Retry interval: ${RETRY_INTERVAL_SEC}s, Max retries: $RETRY_COUNT"

    for ((i=1; i<=RETRY_COUNT; i++)); do
        status=$(check_scan_status "$task_id")
        
        # Convert status to uppercase for comparison
        status_upper=$(echo "$status" | tr '[:lower:]' '[:upper:]')
        
        print_info "Attempt $i/$RETRY_COUNT: Scan status = $status"

        case "$status_upper" in
            "COMPLETED")
                print_success "Scan completed successfully!"
                return 0
                ;;
            "FAILED"|"TERMINATED")
                print_error "Scan $status_upper"
                exit 1
                ;;
            "SCHEDULED"|"ACTIVE"|"RUNNING"|"IN_PROGRESS")
                print_info "Scan in progress... waiting ${RETRY_INTERVAL_SEC} seconds"
                sleep "$RETRY_INTERVAL_SEC"
                ;;
            "ERROR")
                print_error "Error checking scan status"
                exit 1
                ;;
            "")
                print_warning "Empty status returned. Waiting ${RETRY_INTERVAL_SEC} seconds..."
                sleep "$RETRY_INTERVAL_SEC"
                ;;
            *)
                print_warning "Unknown status: $status. Continuing..."
                sleep "$RETRY_INTERVAL_SEC"
                ;;
        esac
    done

    print_error "Scan did not complete within the timeout period"
    exit 1
}

################################################################################
# Function: Get project inventory and check for HuggingFace Model Analyzer
################################################################################
check_inventory_for_huggingface() {
    local project_id=$1

    print_info "Fetching project inventory for project ID: $project_id"

    print_debug "curl -X GET '${BASE_URL}/project/inventory/${project_id}?skipVulnerabilities=false&published=true&size=100&page=1&includeFiles=true&includeCopyrights=false' \\"
    print_debug "  -H 'Authorization: Bearer ${AUTH_TOKEN}' \\"
    print_debug "  -H 'Accept: application/json'"

    response=$(curl -s -w "\n%{http_code}" $CURL_SSL_FLAGS -X GET \
        "${BASE_URL}/project/inventory/${project_id}?skipVulnerabilities=false&published=true&size=100&page=1&includeFiles=true&includeCopyrights=false" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -H "Accept: application/json")

    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -eq 200 ]]; then
        print_success "Inventory fetched successfully"
        
        # Save full inventory JSON for HTML report generation
        INVENTORY_JSON_FILE="inventory-${project_id}.json"
        echo "$body" > "$INVENTORY_JSON_FILE"
        print_info "Inventory saved to: $INVENTORY_JSON_FILE"
        
        # Check if "HuggingFace Model Analyzer" exists in the response
        if echo "$body" | grep -q "HuggingFace Model Analyzer"; then
            print_warning "HuggingFace Model Analyzer found in inventory!"
            
            # Extract inventory names detected by HuggingFace Model Analyzer
            INVENTORY_TEMP_FILE=$(mktemp)
            echo "$body" | grep -o '"name": *"[^"]*"' | sed 's/"name": *"\([^"]*\)"/\1/' > "${INVENTORY_TEMP_FILE}.names"
            
            echo "FOUND:${INVENTORY_TEMP_FILE}.names:${INVENTORY_JSON_FILE}"
            return 1
        else
            print_success "HuggingFace Model Analyzer NOT found in inventory"
            echo "PASS:${INVENTORY_JSON_FILE}"
            return 0
        fi
    fi

    print_error "Failed to fetch inventory. HTTP Code: $http_code"
    print_error "Response: $body"
    exit 1
}

################################################################################
# Function: Generate HTML Report from Inventory JSON
################################################################################
generate_html_report() {
    local json_file=$1
    local project_id=$2
    local project_name=$3
    local html_file="inventory-report-${project_id}.html"
    
    print_info "Generating HTML report: $html_file"
    
    # Create HTML header
    cat > "$html_file" << 'EOF_HEADER'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>CodeInsight Inventory Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .header {
            background-color: #2c3e50;
            color: white;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .header h1 {
            margin: 0;
            font-size: 24px;
        }
        .header p {
            margin: 5px 0 0 0;
            font-size: 14px;
            opacity: 0.9;
        }
        .summary {
            background-color: white;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .summary-item {
            display: inline-block;
            margin-right: 30px;
            padding: 10px;
        }
        .summary-label {
            font-weight: bold;
            color: #555;
            font-size: 12px;
            text-transform: uppercase;
        }
        .summary-value {
            font-size: 24px;
            color: #2c3e50;
            font-weight: bold;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border-radius: 5px;
            overflow: hidden;
        }
        th {
            background-color: #34495e;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            font-size: 14px;
            text-transform: uppercase;
        }
        td {
            padding: 12px;
            border-bottom: 1px solid #ecf0f1;
            font-size: 13px;
        }
        tr:hover {
            background-color: #f8f9fa;
        }
        tr:last-child td {
            border-bottom: none;
        }
        .ai-model-true {
            background-color: #e74c3c;
            color: white;
            padding: 4px 8px;
            border-radius: 3px;
            font-weight: bold;
            font-size: 11px;
        }
        .ai-model-false {
            background-color: #27ae60;
            color: white;
            padding: 4px 8px;
            border-radius: 3px;
            font-weight: bold;
            font-size: 11px;
        }
        .license {
            font-family: 'Courier New', monospace;
            background-color: #ecf0f1;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 12px;
        }
        .usage-guidance {
            max-width: 300px;
            font-size: 12px;
            color: #555;
        }
        .footer {
            text-align: center;
            margin-top: 20px;
            color: #7f8c8d;
            font-size: 12px;
        }
        .version-na {
            color: #95a5a6;
            font-style: italic;
        }
    </style>
</head>
<body>
EOF_HEADER
    
    # Extract project metadata from JSON
    local total_items=$(grep -o '"itemNumber"' "$json_file" | wc -l)
    local ai_model_count=$(grep -c 'HuggingFace Model Analyzer' "$json_file" || echo "0")
    
    # Add header and summary to HTML
    cat >> "$html_file" << EOF
    <div class="header">
        <h1>📊 CodeInsight Inventory Report</h1>
        <p>Project: <strong>${project_name}</strong> (ID: ${project_id})</p>
        <p>Generated: $(date '+%Y-%m-%d %H:%M:%S')</p>
    </div>
    
    <div class="summary">
        <div class="summary-item">
            <div class="summary-label">Total Components</div>
            <div class="summary-value">${total_items}</div>
        </div>
        <div class="summary-item">
            <div class="summary-label">AI Models Detected</div>
            <div class="summary-value" style="color: ${ai_model_count:-0} -gt 0 ? '#e74c3c' : '#27ae60';">${ai_model_count}</div>
        </div>
    </div>
    
    <table>
        <thead>
            <tr>
                <th>Component</th>
                <th>Version</th>
                <th>License</th>
                <th>AI Model</th>
                <th>Usage Guidance</th>
            </tr>
        </thead>
        <tbody>
EOF
    
    # Parse JSON and extract inventory items
    # Process each inventory item by splitting on itemNumber markers
    # This approach extracts complete blocks between "itemNumber" fields
    
    # Create a temp file to store processed items
    TEMP_ITEMS=$(mktemp)
    
    # Split JSON into individual inventory items using itemNumber as delimiter
    # Each item starts with "itemNumber" and we capture everything until the next one
    grep -n '"itemNumber"' "$json_file" | while IFS=: read -r line_num _; do
        # Get the next itemNumber line
        next_line=$(grep -n '"itemNumber"' "$json_file" | grep -A1 "^${line_num}:" | tail -1 | cut -d: -f1)
        
        if [[ -n "$next_line" ]] && [[ "$next_line" != "$line_num" ]]; then
            # Extract lines between current and next itemNumber
            sed -n "${line_num},$((next_line-1))p" "$json_file"
        else
            # This is the last item, extract until end of inventoryItems array
            sed -n "${line_num},\$p" "$json_file" | sed '/^  \]/q'
        fi
        echo "___ITEM_SEPARATOR___"
    done > "$TEMP_ITEMS"
    
    # Now process each item block
    item_count=0
    current_item=""
    while IFS= read -r line; do
        if [[ "$line" == "___ITEM_SEPARATOR___" ]]; then
            if [[ -n "$current_item" ]]; then
                # Process the complete item block
                component_name=$(echo "$current_item" | grep -o '"componentName": *"[^"]*"' | sed 's/"componentName": *"\([^"]*\)"/\1/' | head -1)
                version_name=$(echo "$current_item" | grep -o '"componentVersionName": *"[^"]*"' | sed 's/"componentVersionName": *"\([^"]*\)"/\1/' | head -1)
                license_spdx=$(echo "$current_item" | grep -o '"selectedLicenseSPDXIdentifier": *"[^"]*"' | sed 's/"selectedLicenseSPDXIdentifier": *"\([^"]*\)"/\1/' | head -1)
                detection_notes=$(echo "$current_item" | grep -o '"detectionNotes": *"[^"]*"' | sed 's/"detectionNotes": *"\([^"]*\)"/\1/' | head -1)
                usage_guidance=$(echo "$current_item" | grep -o '"usageGuidance": *"[^"]*"' | sed 's/"usageGuidance": *"\([^"]*\)"/\1/' | head -1)
                
                # Only process if we got a component name
                if [[ -n "$component_name" ]]; then
                    # Determine if detected by HuggingFace
                    if echo "$detection_notes" | grep -q "HuggingFace Model Analyzer"; then
                        ai_model='<span class="ai-model-true">TRUE</span>'
                    else
                        ai_model='<span class="ai-model-false">FALSE</span>'
                    fi
                    
                    # Handle N/A values
                    [[ "$version_name" == "N/A" || -z "$version_name" ]] && version_name='<span class="version-na">N/A</span>'
                    [[ -z "$license_spdx" || "$license_spdx" == "I don't know" ]] && license_spdx='<span class="version-na">Unknown</span>' || license_spdx="<span class=\"license\">$license_spdx</span>"
                    
                    # Clean up usage guidance HTML tags and truncate
                    usage_guidance=$(echo "$usage_guidance" | sed 's/<[^>]*>//g' | sed 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/\\n/ /g' | cut -c 1-200)
                    [[ -z "$usage_guidance" || "$usage_guidance" == "N/A" ]] && usage_guidance='<span class="version-na">No guidance available</span>'
                    
                    # Write table row
                    cat >> "$html_file" << EOF
            <tr>
                <td><strong>$component_name</strong></td>
                <td>$version_name</td>
                <td>$license_spdx</td>
                <td>$ai_model</td>
                <td class="usage-guidance">$usage_guidance</td>
            </tr>
EOF
                    item_count=$((item_count + 1))
                fi
            fi
            current_item=""
        else
            current_item="${current_item}${line}"$'\n'
        fi
    done < "$TEMP_ITEMS"
    
    # Clean up temp file
    rm -f "$TEMP_ITEMS"
    
    print_debug "Processed $item_count inventory items into HTML report"
    
    # Close HTML
    cat >> "$html_file" << 'EOF_FOOTER'
        </tbody>
    </table>
    
    <div class="footer">
        <p>Generated by CodeInsight Scan Automation Script</p>
    </div>
</body>
</html>
EOF_FOOTER
    
    print_success "HTML report generated: $html_file"
    echo "$html_file"
}

################################################################################
# Main Script Execution
################################################################################
main() {
    echo ""
    echo "============================================================================="
    echo "   CodeInsight Project Automation Script"
    echo "============================================================================="
    echo ""

    # Check if running in non-interactive mode (arguments or env vars provided)
    if [[ -z "$CODEBASE_PATH" ]] || [[ -z "$PROJECT_NAME" ]]; then
        # Interactive mode - prompt for missing parameters
        if [[ -z "$CODEBASE_PATH" ]]; then
            read -p "Enter Codebase Path (full path to zip file): " CODEBASE_PATH
        fi
        
        if [[ -z "$PROJECT_NAME" ]]; then
            read -p "Enter Project Name: " PROJECT_NAME
        fi
        
        read -p "Enter Scanner Alias (optional, press Enter for default '$SCAN_SERVER_ALIAS'): " SCANNER_INPUT
        if [[ -n "$SCANNER_INPUT" ]]; then
            SCAN_SERVER_ALIAS="$SCANNER_INPUT"
        fi
        
        read -p "Enter Server URL (optional, press Enter for default '$SERVER_URL'): " SERVER_INPUT
        if [[ -n "$SERVER_INPUT" ]]; then
            SERVER_URL="$SERVER_INPUT"
            BASE_URL="${SERVER_URL}/codeinsight/api"
            
            # Re-detect SSL
            if [[ "$SERVER_URL" == https://* ]]; then
                CURL_SSL_FLAGS="-k"
                print_info "SSL detected - Certificate verification will be bypassed"
            else
                CURL_SSL_FLAGS=""
            fi
        fi
        
        # Optionally allow token override in interactive mode
        read -s -p "Enter Auth Token (optional, press Enter to use configured token): " TOKEN_INPUT
        echo ""
        if [[ -n "$TOKEN_INPUT" ]]; then
            AUTH_TOKEN="$TOKEN_INPUT"
        fi
    fi

    echo ""
    print_info "Configuration:"
    echo "  - Server: ${SERVER_URL}"
    echo "  - Base URL: ${BASE_URL}"
    echo "  - Project Name: ${PROJECT_NAME}"
    echo "  - Codebase Path: ${CODEBASE_PATH}"
    echo "  - Scanner Alias: ${SCAN_SERVER_ALIAS}"
    if [[ -n "$CURL_SSL_FLAGS" ]]; then
        echo "  - SSL Mode: Enabled (certificate verification bypassed)"
    else
        echo "  - SSL Mode: Disabled (HTTP)"
    fi
    echo ""

    # Step 0: Validate configuration (JWT token)
    validate_configuration

    # Step 1: Validate inputs
    validate_inputs

    # Step 2: Check if project exists, create if not
    PROJECT_ID=$(check_project_exists "$PROJECT_NAME")
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(create_project "$PROJECT_NAME")
    else
        print_info "Using existing project ID: $PROJECT_ID"
    fi

    # Step 3: Upload codebase
    upload_codebase "$PROJECT_ID" "$CODEBASE_PATH"

    # Step 4: Trigger scan
    TASK_ID=$(trigger_scan "$PROJECT_ID")

    # Step 5: Wait for scan completion
    wait_for_scan_completion "$TASK_ID"

    # Step 6: Check inventory for HuggingFace Model Analyzer
    RESULT=$(check_inventory_for_huggingface "$PROJECT_ID")

    echo ""
    echo "============================================================================="
    echo "   Scan Automation Complete"
    echo "============================================================================="
    echo ""
    print_info "Project ID: $PROJECT_ID"
    print_info "Task ID: $TASK_ID"
    
    # Parse RESULT to extract JSON file path
    if [[ "$RESULT" =~ ^PASS: ]]; then
        JSON_FILE="${RESULT#PASS:}"
        
        # Step 7: Generate HTML Report
        print_info "Generating HTML report..."
        HTML_REPORT=$(generate_html_report "$JSON_FILE" "$PROJECT_ID" "$PROJECT_NAME")
        
        echo ""
        print_success "Result: PASS (No HuggingFace Model Analyzer found)"
        print_success "HTML Report: $HTML_REPORT"
        echo ""
        exit 0
        
    elif [[ "$RESULT" =~ ^FOUND: ]]; then
        # Extract both the names file and JSON file
        RESULT_DATA="${RESULT#FOUND:}"
        INVENTORY_FILE="${RESULT_DATA%%:*}"
        JSON_FILE="${RESULT_DATA#*:}"
        
        echo ""
        print_error "Result: FAIL (HuggingFace Model Analyzer detected)"
        echo ""
        print_info "HuggingFace Analyzer detected below inventories:"
        echo ""
        
        if [[ -f "$INVENTORY_FILE" ]]; then
            # Read and display inventory names
            while IFS= read -r inventory_name; do
                if [[ -n "$inventory_name" ]]; then
                    echo "  • $inventory_name"
                fi
            done < "$INVENTORY_FILE"
            
            # Cleanup temp file
            rm -f "$INVENTORY_FILE"
            
            # Remove the base temp file if it exists
            INVENTORY_BASE="${INVENTORY_FILE%.names}"
            rm -f "$INVENTORY_BASE"
        fi
        
        # Step 7: Generate HTML Report
        echo ""
        print_info "Generating HTML report..."
        HTML_REPORT=$(generate_html_report "$JSON_FILE" "$PROJECT_ID" "$PROJECT_NAME")
        print_success "HTML Report: $HTML_REPORT"
        
        echo ""
        exit 1
    else
        print_error "Result: FAIL (Unknown error occurred)"
        echo ""
        exit 1
    fi
}

# Execute main function
main
