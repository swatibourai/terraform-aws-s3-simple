pipeline {
    agent any
    
    parameters {
        string(
            name: 'MODULE_VERSION',
            defaultValue: '1.0.0',
            description: 'Module version in semver format (x.y.z)',
            trim: true
        )
        string(
            name: 'MODULE_NAME',
            defaultValue: 's3-simple',
            description: 'Name of the Terraform module',
            trim: true
        )
        string(
            name: 'MODULE_PROVIDER',
            defaultValue: 'aws',
            description: 'Provider for the Terraform module (e.g., aws, azure, gcp)',
            trim: true
        )
    }
    
    environment {
        // Terraform Cloud credentials - configure these in Jenkins credentials
        TF_API_TOKEN = credentials('terraform-cloud-api-token')
        ORG = 'Chase-UK-Org'
        
        // Module configuration - set from parameters
        MODULE_NAME = "${params.MODULE_NAME}"
        MODULE_PROVIDER = "${params.MODULE_PROVIDER}"
        REGISTRY_NAME = 'private'
        
        // Git configuration
        GIT_COMMIT_SHA = "${env.GIT_COMMIT}"
        
        // Workspace directories
        WORKSPACE_DIR = "${WORKSPACE}"
        ARTIFACTS_DIR = "${WORKSPACE}/artifacts"
    }
    
    triggers {
        // Trigger on push to main branch
        githubPush()
    }
    
    options {
        // Keep builds for 30 days
        buildDiscarder(logRotator(daysToKeepStr: '30', numToKeepStr: '10'))
        
        // Timeout after 30 minutes
        timeout(time: 30, unit: 'MINUTES')
        
        // Don't run concurrent builds
        disableConcurrentBuilds()
    }
    
    stages {
        stage('Validate Module Version') {
            steps {
                script {
                    echo "Validating parameters..."
                    echo "Module Name: ${params.MODULE_NAME}"
                    echo "Module Provider: ${params.MODULE_PROVIDER}"
                    echo "Module Version: ${params.MODULE_VERSION}"
                    
                    // Validate module name
                    if (!params.MODULE_NAME || params.MODULE_NAME.trim().isEmpty()) {
                        error("Module name cannot be empty")
                    }
                    
                    // Validate module provider
                    if (!params.MODULE_PROVIDER || params.MODULE_PROVIDER.trim().isEmpty()) {
                        error("Module provider cannot be empty")
                    }
                    
                    // Validate semver format
                    if (!params.MODULE_VERSION.matches(/^\d+\.\d+\.\d+$/)) {
                        error("Invalid module version format: ${params.MODULE_VERSION}. Expected format: x.y.z (e.g., 1.0.0)")
                    }
                    
                    // Set the validated version as environment variable
                    env.MODULE_VERSION = params.MODULE_VERSION
                    env.MODULE_NAME = params.MODULE_NAME
                    env.MODULE_PROVIDER = params.MODULE_PROVIDER
                    
                    echo "✅ All parameters validated successfully"
                    echo "  - Module: ${env.MODULE_NAME}"
                    echo "  - Provider: ${env.MODULE_PROVIDER}" 
                    echo "  - Version: ${env.MODULE_VERSION}"
                }
            }
        }
        
        stage('Setup Tools') {
            steps {
                script {
                    echo "Installing required tools..."
                    sh '''
                        # Create tools directory
                        mkdir -p /tmp/jenkins-tools
                        export PATH="/tmp/jenkins-tools:$PATH"
                        
                        # Detect architecture
                        ARCH=$(uname -m)
                        if [ "$ARCH" = "x86_64" ]; then
                            TERRAFORM_ARCH="amd64"
                        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
                            TERRAFORM_ARCH="arm64"
                        else
                            echo "Unsupported architecture: $ARCH"
                            exit 1
                        fi
                        
                        echo "Detected architecture: $ARCH, using $TERRAFORM_ARCH for Terraform"
                        
                        # Install Terraform
                        if [ ! -f "/tmp/jenkins-tools/terraform" ]; then
                            echo "Installing Terraform..."
                            cd /tmp/jenkins-tools
                            curl -fsSL https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_${TERRAFORM_ARCH}.zip -o terraform.zip
                            unzip -o -q terraform.zip  # -o flag to overwrite without prompt
                            chmod +x terraform
                            ./terraform version
                        else
                            echo "Terraform already installed in /tmp/jenkins-tools"
                            /tmp/jenkins-tools/terraform version
                        fi
                        
                        # Check Python3 availability for JSON parsing
                        if [ ! -f "/tmp/jenkins-tools/python3" ]; then
                            if command -v python3 &> /dev/null; then
                                echo "Python3 system installation found"
                                python3 --version
                                # Create symlink for consistency
                                ln -sf $(which python3) /tmp/jenkins-tools/python3
                            elif command -v python &> /dev/null; then
                                echo "Python (v2/3) available, creating python3 alias"
                                ln -sf $(which python) /tmp/jenkins-tools/python3
                                /tmp/jenkins-tools/python3 --version
                            else
                                echo "⚠️ Python not found, creating fallback script"
                                cat > /tmp/jenkins-tools/python3 << 'PYEOF'
#!/bin/sh
echo "Python not available - using fallback"
exit 0
PYEOF
                                chmod +x /tmp/jenkins-tools/python3
                            fi
                        else
                            echo "Python3 already set up in /tmp/jenkins-tools"
                            /tmp/jenkins-tools/python3 --version 2>/dev/null || echo "Python3 fallback script ready"
                        fi
                        
                        # Verify Terraform is working
                        echo "Verifying Terraform installation..."
                        export PATH="/tmp/jenkins-tools:$PATH"
                        
                        /tmp/jenkins-tools/terraform version
                        
                        # Test python3 availability
                        if command -v python3 &> /dev/null; then
                            python3 --version
                        else
                            echo "⚠️ Python3 not available, using fallback for JSON parsing"
                        fi
                        
                        # Cleanup temporary files to save space
                        cd /tmp/jenkins-tools
                        rm -f terraform.zip 2>/dev/null || true
                        
                        echo "✅ Tool setup completed successfully"
                        echo "Available tools:"
                        ls -la /tmp/jenkins-tools/
                    '''
                }
            }
        }
        
        stage('Checkout') {
            steps {
                script {
                    echo "Starting pipeline for commit: ${GIT_COMMIT_SHA}"
                    echo "Branch: ${env.GIT_BRANCH}"
                }
                
                // Clean workspace
                cleanWs()
                
                // Checkout the repository
                checkout scm
                
                // Verify we're on main branch (optional safety check)
                script {
                    if (env.GIT_BRANCH != 'origin/main' && env.GIT_BRANCH != 'main') {
                        error("Pipeline should only run on main branch. Current branch: ${env.GIT_BRANCH}")
                    }
                }
            }
        }
        
        stage('Code Quality Checks') {
            parallel {
                stage('Terraform Validate') {
                    steps {
                        script {
                            echo "Validating Terraform configuration..."
                            
                            sh '''
                                # Set up environment
                                export PATH="/tmp/jenkins-tools:$PATH"
                                
                                # Use the installed Terraform
                                /tmp/jenkins-tools/terraform init -backend=false
                                /tmp/jenkins-tools/terraform validate
                                
                                echo "✅ Terraform validation completed successfully"
                            '''
                        }
                    }
                }
                
                stage('Terraform Format Check') {
                    steps {
                        script {
                            echo "Checking Terraform formatting..."
                            sh '''
                                # Set up environment
                                export PATH="/tmp/jenkins-tools:$PATH"
                                
                                # Check formatting
                                /tmp/jenkins-tools/terraform fmt -check=true -diff=true || {
                                    echo "⚠️ Terraform formatting issues found"
                                    echo "Run 'terraform fmt' to fix formatting"
                                    exit 0  # Don't fail the build for formatting
                                }
                                
                                echo "✅ Terraform format check passed"
                            '''
                        }
                    }
                }
                
                stage('Documentation Check') {
                    steps {
                        script {
                            echo "Checking for required documentation..."
                            sh '''
                                # Check for README.md
                                if [ ! -f "README.md" ]; then
                                    echo "⚠️ WARNING: README.md not found"
                                else
                                    echo "✅ README.md found"
                                fi
                                
                                # Check for variables documentation
                                if [ ! -f "variables.tf" ]; then
                                    echo "⚠️ WARNING: variables.tf not found"
                                else
                                    echo "✅ variables.tf found"
                                fi
                                
                                # Check for outputs documentation
                                if [ ! -f "outputs.tf" ]; then
                                    echo "⚠️ WARNING: outputs.tf not found"
                                else
                                    echo "✅ outputs.tf found"
                                fi
                                
                                # Check for versions.tf
                                if [ ! -f "versions.tf" ]; then
                                    echo "⚠️ WARNING: versions.tf not found"
                                else
                                    echo "✅ versions.tf found"
                                fi
                                
                                echo "✅ Documentation check completed"
                            '''
                        }
                    }
                }
            }
        }
        
        stage('Check Version Compatibility') {
            steps {
                script {
                    echo "Checking version compatibility with existing module versions..."
                    
                    def moduleExists = sh(
                        script: '''
                            curl -s \
                              --header "Authorization: Bearer $TF_API_TOKEN" \
                              https://app.terraform.io/api/v2/organizations/$ORG/registry-modules/private/$ORG/$MODULE_NAME/$MODULE_PROVIDER \
                              | grep -q '"name"'
                        ''',
                        returnStatus: true
                    )
                    
                    if (moduleExists != 0) {
                        echo "✅ Module does not exist. This will be the first version."
                        env.CREATE_MODULE = 'true'
                        env.VERSION_CHECK_PASSED = 'true'
                    } else {
                        echo "Module exists. Checking version compatibility..."
                        env.CREATE_MODULE = 'false'
                        
                        // Check existing versions
                        def versionCheckResult = sh(
                            script: '''
                                export PATH="/tmp/jenkins-tools:$PATH"
                                
                                RESPONSE=$(curl -s \
                                  --header "Authorization: Bearer $TF_API_TOKEN" \
                                  https://app.terraform.io/api/v2/organizations/$ORG/registry-modules/private/$ORG/$MODULE_NAME/$MODULE_PROVIDER/versions)
                                
                                # Extract existing versions and check if our version is higher
                                if command -v python3 &> /dev/null && python3 -c "import json" 2>/dev/null; then
                                    echo "$RESPONSE" | python3 -c "
import sys, json
from packaging import version

try:
    data = json.load(sys.stdin)
    existing_versions = [v['attributes']['version'] for v in data['data']]
    new_version = '${MODULE_VERSION}'
    
    print('Existing versions:', existing_versions)
    print('New version:', new_version)
    
    # Check if version already exists
    if new_version in existing_versions:
        print('ERROR: Version ' + new_version + ' already exists!')
        sys.exit(1)
    
    # Check if new version is higher than all existing versions
    if existing_versions:
        highest_existing = max(existing_versions, key=version.parse)
        if version.parse(new_version) <= version.parse(highest_existing):
            print('ERROR: New version ' + new_version + ' must be higher than existing highest version ' + highest_existing)
            sys.exit(1)
        else:
            print('SUCCESS: Version ' + new_version + ' is higher than existing versions')
    else:
        print('SUCCESS: No existing versions found')
        
except ImportError:
    print('WARNING: packaging module not available, skipping version comparison')
except Exception as e:
    print('WARNING: Could not parse versions, continuing: ' + str(e))
"
                                else
                                    echo "⚠️ Python not available for version comparison, proceeding with upload"
                                fi
                            ''',
                            returnStatus: true
                        )
                        
                        if (versionCheckResult == 0) {
                            echo "✅ Version check passed"
                            env.VERSION_CHECK_PASSED = 'true'
                        } else {
                            error("Version check failed. Please use a higher version number.")
                        }
                    }
                }
            }
        }
        
        stage('Generate Module Version') {
            steps {
                script {
                    echo "Using module version: ${env.MODULE_VERSION}"
                    
                    // Create artifacts directory
                    sh "mkdir -p ${ARTIFACTS_DIR}"
                    
                    // Create version file for tracking
                    writeFile file: "${ARTIFACTS_DIR}/version.txt", text: "${env.MODULE_VERSION}"
                    
                    echo "✅ Module version set: ${env.MODULE_VERSION}"
                }
            }
        }
        
        stage('Create Module Package') {
            steps {
                script {
                    echo "Creating module package..."
                    
                    sh '''
                        # Create a clean directory for the module
                        mkdir -p ${ARTIFACTS_DIR}/module
                        
                        echo "📦 Creating module package with proper directory structure..."
                        
                        # Copy all relevant files while preserving directory structure
                        # This will include all .tf files in subdirectories and other important files
                        
                        # Use rsync for better directory structure preservation
                        echo "📁 Copying all Terraform and related files..."
                        
                        # Copy all .tf files recursively
                        find . -name "*.tf" -not -path "./.terraform/*" -not -path "./artifacts/*" -not -path "./.git/*" -print0 | \\
                            xargs -0 -I {} cp --parents {} ${ARTIFACTS_DIR}/module/
                        
                        # Copy documentation files  
                        find . -name "*.md" -not -path "./.terraform/*" -not -path "./artifacts/*" -not -path "./.git/*" -print0 | \\
                            xargs -0 -I {} cp --parents {} ${ARTIFACTS_DIR}/module/ 2>/dev/null || true
                        
                        # Copy license files
                        find . -name "LICENSE*" -not -path "./.terraform/*" -not -path "./artifacts/*" -not -path "./.git/*" -print0 | \\
                            xargs -0 -I {} cp --parents {} ${ARTIFACTS_DIR}/module/ 2>/dev/null || true
                        
                        # Copy .txt files
                        find . -name "*.txt" -not -path "./.terraform/*" -not -path "./artifacts/*" -not -path "./.git/*" -print0 | \\
                            xargs -0 -I {} cp --parents {} ${ARTIFACTS_DIR}/module/ 2>/dev/null || true
                        
                        # Copy examples directory if it exists (entire directory with structure)
                        if [ -d "examples" ]; then
                            echo "📁 Copying examples directory..."
                            cp -r examples ${ARTIFACTS_DIR}/module/
                        fi
                        
                        # Copy tests directory if it exists (entire directory with structure)
                        if [ -d "tests" ]; then
                            echo "🧪 Copying tests directory..."
                            cp -r tests ${ARTIFACTS_DIR}/module/
                        fi
                        
                        # Copy modules directory if it exists (for nested modules)
                        if [ -d "modules" ]; then
                            echo "📦 Copying modules directory..."
                            cp -r modules ${ARTIFACTS_DIR}/module/
                        fi
                        
                        # Copy any other common Terraform-related files
                        echo "📄 Copying additional Terraform files..."
                        for file in .terraform-version .terraformrc terraform.tfvars.example; do
                            if [ -f "$file" ]; then
                                echo "  - Copying $file..."
                                cp "$file" ${ARTIFACTS_DIR}/module/ 2>/dev/null || true
                            fi
                        done
                        
                        # Show what will be packaged
                        echo "📋 Files and directories to be packaged:"
                        find ${ARTIFACTS_DIR}/module -type f | sort
                        
                        echo ""
                        echo "📊 Directory structure:"
                        tree ${ARTIFACTS_DIR}/module 2>/dev/null || find ${ARTIFACTS_DIR}/module -type d | sort
                        
                        # Create the tar.gz package
                        echo ""
                        echo "📦 Creating tar.gz package..."
                        cd ${ARTIFACTS_DIR}/module
                        tar -czf ../module.tar.gz .
                        cd ${WORKSPACE_DIR}
                        
                        # Verify the package was created
                        if [ -f "${ARTIFACTS_DIR}/module.tar.gz" ]; then
                            echo "✅ Package created successfully:"
                            ls -lh ${ARTIFACTS_DIR}/module.tar.gz
                        else
                            echo "❌ Failed to create package"
                            exit 1
                        fi
                        
                        # Show package contents for verification
                        echo ""
                        echo "📋 Package contents (first 30 files):"
                        tar -tzf ${ARTIFACTS_DIR}/module.tar.gz | head -30
                        
                        TOTAL_FILES=$(tar -tzf ${ARTIFACTS_DIR}/module.tar.gz | wc -l)
                        echo ""
                        echo "📊 Package statistics:"
                        echo "  - Total files: $TOTAL_FILES"
                        echo "  - Package size: $(ls -lh ${ARTIFACTS_DIR}/module.tar.gz | awk '{print $5}')"
                        
                        # Show directory breakdown
                        echo "  - Terraform files: $(tar -tzf ${ARTIFACTS_DIR}/module.tar.gz | grep -c '\.tf$' || echo 0)"
                        echo "  - Documentation files: $(tar -tzf ${ARTIFACTS_DIR}/module.tar.gz | grep -c '\.md$' || echo 0)"
                        echo "  - Directories: $(tar -tzf ${ARTIFACTS_DIR}/module.tar.gz | grep '/$' | wc -l)"
                    '''
                }
            }
        }
        
        stage('Create Module (if needed)') {
            when {
                environment name: 'CREATE_MODULE', value: 'true'
            }
            steps {
                script {
                    echo "Creating new module in Terraform Cloud..."
                    
                    // Create payload for module creation
                    writeFile file: "${ARTIFACTS_DIR}/create-module-payload.json", text: """
{
  "data": {
    "type": "registry-modules",
    "attributes": {
      "name": "${MODULE_NAME}",
      "provider": "${MODULE_PROVIDER}",
      "registry-name": "${REGISTRY_NAME}",
      "no-code": true
    }
  }
}
"""
                    
                    sh '''
                        curl -f \
                          --header "Authorization: Bearer $TF_API_TOKEN" \
                          --header "Content-Type: application/vnd.api+json" \
                          --request POST \
                          --data @${ARTIFACTS_DIR}/create-module-payload.json \
                          https://app.terraform.io/api/v2/organizations/$ORG/registry-modules
                    '''
                    
                    echo "Module created successfully"
                }
            }
        }
        
        stage('Create Module Version') {
            steps {
                script {
                    echo "Creating module version ${MODULE_VERSION}..."
                    
                    // Create payload for module version creation
                    writeFile file: "${ARTIFACTS_DIR}/create-version-payload.json", text: """
{
  "data": {
    "type": "registry-module-versions",
    "attributes": {
      "version": "${MODULE_VERSION}",
      "commit-sha": "${GIT_COMMIT_SHA}"
    }
  }
}
"""
                    
                    sh '''
                        curl -f \
                          --header "Authorization: Bearer $TF_API_TOKEN" \
                          --header "Content-Type: application/vnd.api+json" \
                          --request POST \
                          --data @${ARTIFACTS_DIR}/create-version-payload.json \
                          https://app.terraform.io/api/v2/organizations/$ORG/registry-modules/private/$ORG/$MODULE_NAME/$MODULE_PROVIDER/versions \
                          > ${ARTIFACTS_DIR}/version_response.json
                    '''
                    
                    // Extract upload URL from response
                    sh '''
                        echo "Extracting upload URL from response..."
                        export PATH="/tmp/jenkins-tools:$PATH"
                        
                        # Try with installed python3 first, fallback to different methods
                        if command -v python3 &> /dev/null && python3 -c "import json" 2>/dev/null; then
                            echo "Using Python3 for JSON parsing..."
                            UPLOAD_URL=$(cat ${ARTIFACTS_DIR}/version_response.json | \
                              python3 -c "import sys, json; print(json.load(sys.stdin)['data']['links']['upload'])")
                        elif command -v python &> /dev/null; then
                            echo "Using Python for JSON parsing..."
                            UPLOAD_URL=$(cat ${ARTIFACTS_DIR}/version_response.json | \
                              python -c "import sys, json; print(json.load(sys.stdin)['data']['links']['upload'])")
                        elif command -v jq &> /dev/null; then
                            echo "Using jq for JSON parsing..."
                            UPLOAD_URL=$(cat ${ARTIFACTS_DIR}/version_response.json | jq -r '.data.links.upload')
                        else
                            echo "Using grep fallback for URL extraction..."
                            # Simple grep fallback (less reliable)
                            UPLOAD_URL=$(grep -o '"upload":"[^"]*"' ${ARTIFACTS_DIR}/version_response.json | cut -d'"' -f4)
                        fi
                        
                        echo "Upload URL extracted: $UPLOAD_URL"
                        echo "$UPLOAD_URL" > ${ARTIFACTS_DIR}/upload_url.txt
                        
                        # Validate URL
                        if [ -z "$UPLOAD_URL" ] || [ "$UPLOAD_URL" = "null" ]; then
                            echo "❌ Failed to extract upload URL"
                            echo "Response content:"
                            cat ${ARTIFACTS_DIR}/version_response.json
                            exit 1
                        fi
                        
                        echo "✅ Upload URL ready for module upload"
                    '''
                }
            }
        }
        
        stage('Upload Module') {
            steps {
                script {
                    echo "Uploading module package to Terraform Cloud..."
                    
                    sh '''
                        # Read the upload URL
                        UPLOAD_URL=$(cat ${ARTIFACTS_DIR}/upload_url.txt)
                        
                        echo "📤 Uploading to: $UPLOAD_URL"
                        echo "📦 Package size: $(ls -lh ${ARTIFACTS_DIR}/module.tar.gz | awk '{print $5}')"
                        
                        # Upload the module package with progress
                        if curl -f \
                          --header "Authorization: Bearer $TF_API_TOKEN" \
                          --header "Content-Type: application/octet-stream" \
                          --request PUT \
                          --data-binary @${ARTIFACTS_DIR}/module.tar.gz \
                          --progress-bar \
                          "$UPLOAD_URL"; then
                            echo "✅ Module uploaded successfully!"
                        else
                            echo "❌ Upload failed"
                            exit 1
                        fi
                    '''
                }
            }
        }
        
        stage('Verify Upload') {
            steps {
                script {
                    echo "Verifying module upload..."
                    
                    // Wait a bit for processing
                    sleep(time: 10, unit: 'SECONDS')
                    
                    sh '''
                        # Check if the module version is now available
                        export PATH="/tmp/jenkins-tools:$PATH"
                        
                        RESPONSE=$(curl -f \
                          --header "Authorization: Bearer $TF_API_TOKEN" \
                          https://app.terraform.io/api/v2/organizations/$ORG/registry-modules/private/$ORG/$MODULE_NAME/$MODULE_PROVIDER/versions)
                        
                        # Try different methods to parse JSON
                        if command -v python3 &> /dev/null && python3 -c "import json" 2>/dev/null; then
                            echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
versions = [v['attributes']['version'] for v in data['data']]
print('Available versions:', versions)
if '${MODULE_VERSION}' in versions:
    print('SUCCESS: Version ${MODULE_VERSION} is available')
else:
    print('ERROR: Version ${MODULE_VERSION} not found')
    sys.exit(1)
"
                        elif command -v jq &> /dev/null; then
                            echo "Using jq for JSON parsing..."
                            VERSIONS=$(echo "$RESPONSE" | jq -r '.data[].attributes.version')
                            echo "Available versions: $VERSIONS"
                            if echo "$VERSIONS" | grep -q "${MODULE_VERSION}"; then
                                echo "SUCCESS: Version ${MODULE_VERSION} is available"
                            else
                                echo "ERROR: Version ${MODULE_VERSION} not found"
                                exit 1
                            fi
                        else
                            echo "⚠️ Limited JSON parsing capability - checking response manually"
                            echo "Response: $RESPONSE"
                            if echo "$RESPONSE" | grep -q "\"version\":\"${MODULE_VERSION}\""; then
                                echo "SUCCESS: Version ${MODULE_VERSION} appears to be available"
                            else
                                echo "⚠️ Could not verify version ${MODULE_VERSION} - manual check recommended"
                                echo "Please check Terraform Cloud Registry manually"
                            fi
                        fi
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "Pipeline completed for commit: ${GIT_COMMIT_SHA}"
                def moduleVersion = env.MODULE_VERSION ?: "unknown"
                echo "Module: ${MODULE_NAME} version ${moduleVersion}"
            }
            
            // Archive artifacts
            archiveArtifacts artifacts: 'artifacts/**/*', allowEmptyArchive: true
            
            // Clean workspace
            cleanWs()
        }
        
        success {
            script {
                def moduleVersion = env.MODULE_VERSION ?: "unknown"
                echo "✅ Module ${MODULE_NAME} version ${moduleVersion} successfully uploaded to Terraform Cloud!"
                
                // Send success notification (customize as needed)
                // slackSend(
                //     color: 'good',
                //     message: "✅ Terraform module ${MODULE_NAME} v${moduleVersion} successfully deployed to TFC registry"
                // )
            }
        }
        
        failure {
            script {
                def moduleVersion = env.MODULE_VERSION ?: "unknown"
                echo "❌ Pipeline failed for module ${MODULE_NAME}"
                
                // Send failure notification (customize as needed)
                // slackSend(
                //     color: 'danger',
                //     message: "❌ Failed to deploy Terraform module ${MODULE_NAME} v${moduleVersion} to TFC registry"
                // )
            }
        }
    }
}
