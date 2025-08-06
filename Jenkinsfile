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
                            
                            // Initialize Terraform
                            sh '''
                                terraform init -backend=false
                                terraform validate
                            '''
                        }
                    }
                }
                
                stage('Terraform Format Check') {
                    steps {
                        script {
                            echo "Checking Terraform formatting..."
                            sh '''
                                terraform fmt -check=true -diff=true
                            '''
                        }
                    }
                }
                
                stage('Security Scan') {
                    steps {
                        script {
                            echo "Running security scan with tfsec..."
                            sh '''
                                # Install tfsec if not available
                                if ! command -v tfsec &> /dev/null; then
                                    echo "Installing tfsec..."
                                    curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
                                fi
                                
                                # Run security scan
                                tfsec . --format=json --out=tfsec-results.json || true
                                tfsec . || true
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
                                    echo "WARNING: README.md not found"
                                fi
                                
                                # Check for variables documentation
                                if [ ! -f "variables.tf" ]; then
                                    echo "WARNING: variables.tf not found"
                                fi
                                
                                # Check for outputs documentation
                                if [ ! -f "outputs.tf" ]; then
                                    echo "WARNING: outputs.tf not found"
                                fi
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
                        # Extract the upload URL from the response
                        UPLOAD_URL=$(cat ${ARTIFACTS_DIR}/version_response.json | \
                          python3 -c "import sys, json; print(json.load(sys.stdin)['data']['links']['upload'])")
                        
                        echo "Upload URL: $UPLOAD_URL"
                        echo "$UPLOAD_URL" > ${ARTIFACTS_DIR}/upload_url.txt
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
                echo "Module: ${MODULE_NAME} version ${MODULE_VERSION}"
            }
            
            // Archive artifacts
            archiveArtifacts artifacts: 'artifacts/**/*', allowEmptyArchive: true
            
            // Clean workspace
            cleanWs()
        }
        
        success {
            script {
                echo "✅ Module ${MODULE_NAME} version ${MODULE_VERSION} successfully uploaded to Terraform Cloud!"
                
                // Send success notification (customize as needed)
                // slackSend(
                //     color: 'good',
                //     message: "✅ Terraform module ${MODULE_NAME} v${MODULE_VERSION} successfully deployed to TFC registry"
                // )
            }
        }
        
        failure {
            script {
                echo "❌ Pipeline failed for module ${MODULE_NAME}"
                
                // Send failure notification (customize as needed)
                // slackSend(
                //     color: 'danger',
                //     message: "❌ Failed to deploy Terraform module ${MODULE_NAME} v${MODULE_VERSION} to TFC registry"
                // )
            }
        }
    }
}
