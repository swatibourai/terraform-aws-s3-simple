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
            steps {
                script {
                    echo "Running basic Terraform checks..."
                    
                    sh '''
                        # Set up environment
                        export PATH="/tmp/jenkins-tools:$PATH"
                        
                        # Basic Terraform validation
                        /tmp/jenkins-tools/terraform init -backend=false
                        /tmp/jenkins-tools/terraform validate
                        
                        echo "✅ Basic checks completed"
                    '''
                }
            }
        }
        
        stage('Check Version Compatibility') {
            steps {
                script {
                    echo "Checking if module exists..."
                    
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
                    } else {
                        echo "✅ Module exists. Will create new version."
                        env.CREATE_MODULE = 'false'
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
                        
                        echo "📦 Creating module package..."
                        
                        # Copy all .tf files recursively with directory structure
                        find . -name "*.tf" -not -path "./.terraform/*" -not -path "./artifacts/*" -not -path "./.git/*" -exec cp --parents {} ${ARTIFACTS_DIR}/module/ \\;
                        
                        # Copy documentation files
                        find . -name "*.md" -not -path "./.terraform/*" -not -path "./artifacts/*" -not -path "./.git/*" -exec cp --parents {} ${ARTIFACTS_DIR}/module/ \\; 2>/dev/null || true
                        
                        # Copy entire directories if they exist
                        for dir in examples tests modules; do
                            if [ -d "$dir" ]; then
                                echo "� Copying $dir directory..."
                                cp -r "$dir" ${ARTIFACTS_DIR}/module/
                            fi
                        done
                        
                        # Show what will be packaged
                        echo "Files to be packaged:"
                        find ${ARTIFACTS_DIR}/module -type f | head -20
                        
                        # Create the tar.gz package
                        echo "📦 Creating tar.gz package..."
                        cd ${ARTIFACTS_DIR}/module
                        tar -czf ../module.tar.gz .
                        cd ${WORKSPACE_DIR}
                        
                        # Verify package
                        if [ -f "${ARTIFACTS_DIR}/module.tar.gz" ]; then
                            echo "✅ Package created successfully"
                            ls -lh ${ARTIFACTS_DIR}/module.tar.gz
                            echo "Package contents:"
                            tar -tzf ${ARTIFACTS_DIR}/module.tar.gz | head -20
                        else
                            echo "❌ Failed to create package"
                            exit 1
                        fi
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
                        # Simple verification
                        RESPONSE=$(curl -s \
                          --header "Authorization: Bearer $TF_API_TOKEN" \
                          https://app.terraform.io/api/v2/organizations/$ORG/registry-modules/private/$ORG/$MODULE_NAME/$MODULE_PROVIDER/versions)
                        
                        if echo "$RESPONSE" | grep -q "\"version\":\"${MODULE_VERSION}\""; then
                            echo "✅ SUCCESS: Version ${MODULE_VERSION} is available"
                        else
                            echo "⚠️ Could not verify version - check Terraform Cloud Registry manually"
                            echo "Response: $RESPONSE"
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
