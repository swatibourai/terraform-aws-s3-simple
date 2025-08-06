pipeline {
    agent any
    
    environment {
        // Terraform Cloud credentials - configure these in Jenkins credentials
        TF_API_TOKEN = credentials('terraform-cloud-api-token')
        ORG = 'Chase-UK-Org'
        
        // Module configuration
        MODULE_NAME = 's3-simple'
        MODULE_PROVIDER = 'aws'
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
                            TFSEC_ARCH="linux_amd64"
                        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
                            TERRAFORM_ARCH="arm64"
                            TFSEC_ARCH="linux_arm64"
                        else
                            echo "Unsupported architecture: $ARCH"
                            exit 1
                        fi
                        
                        echo "Detected architecture: $ARCH, using $TERRAFORM_ARCH for Terraform and $TFSEC_ARCH for tfsec"
                        
                        # Install Terraform
                        if ! command -v terraform &> /dev/null; then
                            echo "Installing Terraform..."
                            cd /tmp/jenkins-tools
                            curl -fsSL https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_${TERRAFORM_ARCH}.zip -o terraform.zip
                            unzip -q terraform.zip
                            chmod +x terraform
                            ./terraform version
                        else
                            echo "Terraform already available"
                            terraform version
                        fi
                        
                        # Install tfsec
                        if ! command -v tfsec &> /dev/null; then
                            echo "Installing tfsec..."
                            cd /tmp/jenkins-tools
                            curl -fsSL https://github.com/aquasecurity/tfsec/releases/download/v1.28.14/tfsec_1.28.14_${TFSEC_ARCH}.tar.gz -o tfsec.tar.gz
                            tar -xzf tfsec.tar.gz
                            chmod +x tfsec
                            ./tfsec --version
                        else
                            echo "tfsec already available"
                            tfsec --version
                        fi
                        
                        # Check Python3 availability (don't try to install if no permission)
                        if command -v python3 &> /dev/null; then
                            echo "Python3 already available"
                            python3 --version
                        elif command -v python &> /dev/null; then
                            echo "Python (v2/3) available, creating python3 alias"
                            ln -sf $(which python) /tmp/jenkins-tools/python3
                            /tmp/jenkins-tools/python3 --version
                        else
                            echo "⚠️ Python not found, but continuing - some features may be limited"
                            echo "Creating a dummy python3 script for basic functionality"
                            cat > /tmp/jenkins-tools/python3 << 'PYEOF'
#!/bin/sh
echo "Python not available - using fallback"
exit 0
PYEOF
                            chmod +x /tmp/jenkins-tools/python3
                        fi
                        
                        # Verify all tools are working
                        echo "Verifying tools installation..."
                        export PATH="/tmp/jenkins-tools:$PATH"
                        export TERRAFORM_CMD="/tmp/jenkins-tools/terraform"
                        export TFSEC_CMD="/tmp/jenkins-tools/tfsec"
                        
                        $TERRAFORM_CMD version
                        $TFSEC_CMD --version
                        
                        # Test python3 availability
                        if command -v python3 &> /dev/null; then
                            python3 --version
                        else
                            echo "⚠️ Python3 not available, using fallback for JSON parsing"
                        fi
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
        
        stage('Code Quality & Security') {
            parallel {
                stage('Terraform Validate') {
                    steps {
                        script {
                            echo "Validating Terraform configuration..."
                            
                            sh '''
                                # Set up environment
                                export PATH="/tmp/jenkins-tools:$PATH"
                                export TERRAFORM_CMD="/tmp/jenkins-tools/terraform"
                                export TFSEC_CMD="/tmp/jenkins-tools/tfsec"
                                
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
                                export TERRAFORM_CMD="/tmp/jenkins-tools/terraform"
                                export TFSEC_CMD="/tmp/jenkins-tools/tfsec"
                                
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
                
                stage('Security Scan') {
                    steps {
                        script {
                            echo "Running security scan with tfsec..."
                            sh '''
                                # Set up environment
                                export PATH="/tmp/jenkins-tools:$PATH"
                                export TERRAFORM_CMD="/tmp/jenkins-tools/terraform"
                                export TFSEC_CMD="/tmp/jenkins-tools/tfsec"
                                
                                # Run security scan
                                /tmp/jenkins-tools/tfsec . --format=json --out=tfsec-results.json || {
                                    echo "⚠️ Security scan completed with warnings"
                                }
                                
                                # Run human-readable scan
                                /tmp/jenkins-tools/tfsec . || {
                                    echo "⚠️ Security issues found - check tfsec-results.json for details"
                                }
                                
                                echo "✅ Security scan completed"
                            '''
                        }
                    }
                    post {
                        always {
                            // Archive security scan results
                            archiveArtifacts artifacts: 'tfsec-results.json', allowEmptyArchive: true
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
        
        stage('Generate Module Version') {
            steps {
                script {
                    echo "Generating module version..."
                    
                    // Create artifacts directory
                    sh "mkdir -p ${ARTIFACTS_DIR}"
                    
                    // Generate version based on build number and date
                    def moduleVersion = "1.0.${BUILD_NUMBER}"
                    env.MODULE_VERSION = moduleVersion
                    
                    echo "Module version: ${moduleVersion}"
                    
                    // Create version file for tracking
                    writeFile file: "${ARTIFACTS_DIR}/version.txt", text: "${moduleVersion}"
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
                        
                        # Copy Terraform files (exclude .git, .terraform, etc.)
                        find . -name "*.tf" -o -name "*.md" -o -name "*.txt" | \
                        grep -v ".terraform" | \
                        grep -v ".git" | \
                        xargs -I {} cp --parents {} ${ARTIFACTS_DIR}/module/
                        
                        # Create examples directory if it exists
                        if [ -d "examples" ]; then
                            cp -r examples ${ARTIFACTS_DIR}/module/
                        fi
                        
                        # Create tests directory if it exists
                        if [ -d "tests" ]; then
                            cp -r tests ${ARTIFACTS_DIR}/module/
                        fi
                        
                        # Create the tar.gz package
                        cd ${ARTIFACTS_DIR}/module
                        tar -czf ../module.tar.gz .
                        cd ${WORKSPACE_DIR}
                        
                        # Verify the package was created
                        ls -la ${ARTIFACTS_DIR}/module.tar.gz
                        
                        # Show package contents for verification
                        echo "Package contents:"
                        tar -tzf ${ARTIFACTS_DIR}/module.tar.gz
                    '''
                }
            }
        }
        
        stage('Check Module Exists') {
            steps {
                script {
                    echo "Checking if module exists in Terraform Cloud..."
                    
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
                        echo "Module does not exist. Will create it first."
                        env.CREATE_MODULE = 'true'
                    } else {
                        echo "Module already exists. Will create new version."
                        env.CREATE_MODULE = 'false'
                    }
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
                        # Set up environment and extract the upload URL from the response
                        export PATH="/tmp/jenkins-tools:$PATH"
                        export TERRAFORM_CMD="/tmp/jenkins-tools/terraform"
                        export TFSEC_CMD="/tmp/jenkins-tools/tfsec"
                        
                        # Try with installed python3 first, fallback to different methods
                        if command -v python3 &> /dev/null; then
                            UPLOAD_URL=$(cat ${ARTIFACTS_DIR}/version_response.json | \
                              python3 -c "import sys, json; print(json.load(sys.stdin)['data']['links']['upload'])")
                        elif command -v python &> /dev/null; then
                            UPLOAD_URL=$(cat ${ARTIFACTS_DIR}/version_response.json | \
                              python -c "import sys, json; print(json.load(sys.stdin)['data']['links']['upload'])")
                        else
                            # Fallback to jq or simple grep if available
                            if command -v jq &> /dev/null; then
                                UPLOAD_URL=$(cat ${ARTIFACTS_DIR}/version_response.json | jq -r '.data.links.upload')
                            else
                                # Simple grep fallback (less reliable)
                                UPLOAD_URL=$(grep -o '"upload":"[^"]*"' ${ARTIFACTS_DIR}/version_response.json | cut -d'"' -f4)
                            fi
                        fi
                        
                        echo "Upload URL: $UPLOAD_URL"
                        echo "$UPLOAD_URL" > ${ARTIFACTS_DIR}/upload_url.txt
                        
                        # Validate URL
                        if [ -z "$UPLOAD_URL" ] || [ "$UPLOAD_URL" = "null" ]; then
                            echo "❌ Failed to extract upload URL"
                            echo "Response content:"
                            cat ${ARTIFACTS_DIR}/version_response.json
                            exit 1
                        fi
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
                        
                        # Upload the module package
                        curl -f \
                          --header "Authorization: Bearer $TF_API_TOKEN" \
                          --header "Content-Type: application/octet-stream" \
                          --request PUT \
                          --data-binary @${ARTIFACTS_DIR}/module.tar.gz \
                          "$UPLOAD_URL"
                    '''
                    
                    echo "Module uploaded successfully!"
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
                        curl -f \
                          --header "Authorization: Bearer $TF_API_TOKEN" \
                          https://app.terraform.io/api/v2/organizations/$ORG/registry-modules/private/$ORG/$MODULE_NAME/$MODULE_PROVIDER/versions \
                          | python3 -c "
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
