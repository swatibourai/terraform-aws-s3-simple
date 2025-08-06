pipeline {
    agent any

    parameters {
        string(name: 'ORG', defaultValue: 'Chase-UK-Org', description: 'Terraform organization name')
        string(name: 'MODULE_NAME', defaultValue: 's3-simple', description: 'Terraform module name')
        string(name: 'MODULE_PROVIDER', defaultValue: 'aws', description: 'Module provider')
        choice(name: 'VERSION_TYPE', choices: ['patch', 'minor', 'major'], description: 'Semantic version increment type')
        booleanParam(name: 'FORCE_VERSION', defaultValue: false, description: 'Override semantic versioning')
        string(name: 'MANUAL_VERSION', defaultValue: '', description: 'Manual version (only if FORCE_VERSION is true)')
    }

    environment {
        TF_API_TOKEN = credentials('terraform-cloud-api-token')
        REGISTRY_NAME = 'private'
        GIT_COMMIT_SHA = "${env.GIT_COMMIT}"
        WORKSPACE_DIR = "${env.WORKSPACE}"
        ARTIFACTS_DIR = "${env.WORKSPACE}/artifacts"
    }

    options {
        buildDiscarder(logRotator(daysToKeepStr: '30', numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {
        stage('Validate Parameters') {
            steps {
                script {
                    echo "Validating parameters..."
                    if (!params.MODULE_NAME?.trim()) error("Module name cannot be empty")
                    if (!params.MODULE_PROVIDER?.trim()) error("Module provider cannot be empty")
                    
                    if (params.FORCE_VERSION && !params.MANUAL_VERSION?.trim()) {
                        error("Manual version required when FORCE_VERSION is enabled")
                    }
                    
                    if (params.FORCE_VERSION && !params.MANUAL_VERSION.matches(/^\d+\.\d+\.\d+$/)) {
                        error("Invalid manual version format. Expected: x.y.z")
                    }
                }
            }
        }

        stage('Setup Tools') {
            steps {
                sh """#!/bin/bash
                    mkdir -p /tmp/jenkins-tools
                    export PATH="/tmp/jenkins-tools:\$PATH"

                    ARCH=\$(uname -m)
                    TERRAFORM_ARCH="\$( [ "\$ARCH" = "x86_64" ] && echo amd64 || echo arm64 )"

                    # Install Terraform
                    if [ ! -f "/tmp/jenkins-tools/terraform" ]; then
                        curl -fsSL https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_\$TERRAFORM_ARCH.zip -o terraform.zip
                        unzip -o -q terraform.zip -d /tmp/jenkins-tools
                        chmod +x /tmp/jenkins-tools/terraform
                        rm terraform.zip
                    fi

                    # Install git-semver for semantic versioning
                    if [ ! -f "/tmp/jenkins-tools/git-semver" ]; then
                        curl -fsSL https://github.com/markchalloner/git-semver/raw/master/git-semver -o /tmp/jenkins-tools/git-semver
                        chmod +x /tmp/jenkins-tools/git-semver
                    fi

                    ln -sf \$(which python3 || which python || echo "/bin/false") /tmp/jenkins-tools/python3 || true
                """
            }
        }

        stage('Checkout Code') {
            steps {
                cleanWs()
                checkout scm
                script {
                    echo "GIT_BRANCH: ${env.GIT_BRANCH}"
                    if (!env.GIT_BRANCH?.contains('main')) error("This pipeline only runs on 'main' branch")
                }
            }
        }

        stage('Secret Scan') {
            steps {
                script {
                    echo "🔍 Running secret scan..."
                    sh """#!/bin/bash
                        # Basic secret scan - look for common patterns
                        echo "Scanning for potential secrets..."
                        
                        # Check for AWS keys (exclude Jenkinsfiles to avoid false positives)
                        if grep -r "AKIA[0-9A-Z]\\{16\\}" . --exclude-dir=.git --exclude-dir=artifacts --exclude="*Jenkinsfile*" 2>/dev/null; then
                            echo "❌ Found potential AWS Access Key"
                            exit 1
                        fi
                        
                        # Check for private keys (exclude Jenkinsfiles to avoid false positives)
                        if grep -r "BEGIN.*PRIVATE KEY" . --exclude-dir=.git --exclude-dir=artifacts --exclude="*Jenkinsfile*" 2>/dev/null; then
                            echo "❌ Found potential private key"
                            exit 1
                        fi
                        
                        # Check for passwords in plain text (only in Terraform files)
                        if grep -ri "password.*=" . --include="*.tf" --include="*.tfvars" --exclude-dir=.git --exclude-dir=artifacts 2>/dev/null | grep -v "variable"; then
                            echo "❌ Found potential hardcoded password"
                            exit 1
                        fi
                        
                        # Check for other sensitive patterns
                        if grep -ri "secret.*=" . --include="*.tf" --include="*.tfvars" --exclude-dir=.git --exclude-dir=artifacts 2>/dev/null | grep -v "variable" | grep -v "data"; then
                            echo "❌ Found potential hardcoded secret"
                            exit 1
                        fi
                        
                        echo "✅ Secret scan completed - no issues found"
                    """
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                sh """#!/bin/bash
                    export PATH="/tmp/jenkins-tools:\$PATH"
                    terraform init -backend=false
                    terraform validate
                    echo "✅ Terraform validation passed"
                """
            }
        }

        stage('Trigger Semantic Versioning') {
            steps {
                script {
                    echo "🏷️ Determining next version..."
                    
                    if (params.FORCE_VERSION) {
                        env.MODULE_VERSION = params.MANUAL_VERSION
                        echo "Using manual version: ${env.MODULE_VERSION}"
                    } else {
                        // Get current version from TFC or tags
                        def currentVersion = sh(script: """#!/bin/bash
                            mkdir -p "${ARTIFACTS_DIR}"
                            
                            # Try to get latest version from Terraform Cloud
                            LATEST_VERSION=\$(curl -s -H "Authorization: Bearer ${TF_API_TOKEN}" \\
                              https://app.terraform.io/api/v2/organizations/${params.ORG}/registry-modules/private/${params.ORG}/${params.MODULE_NAME}/${params.MODULE_PROVIDER}/versions \\
                              | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
                            
                            if [ -z "\$LATEST_VERSION" ] || [ "\$LATEST_VERSION" = "null" ]; then
                                # No existing version, check git tags
                                git fetch --tags 2>/dev/null || true
                                LATEST_VERSION=\$(git tag -l "v*" | sort -V | tail -1 | sed 's/^v//')
                                
                                if [ -z "\$LATEST_VERSION" ]; then
                                    echo "0.0.0"
                                else
                                    echo "\$LATEST_VERSION"
                                fi
                            else
                                echo "\$LATEST_VERSION"
                            fi
                        """, returnStdout: true).trim()
                        
                        echo "Current version: ${currentVersion}"
                        
                        // Calculate next version
                        def versionParts = currentVersion.split('\\.')
                        def major = versionParts[0] as Integer
                        def minor = versionParts[1] as Integer
                        def patch = versionParts[2] as Integer
                        
                        switch(params.VERSION_TYPE) {
                            case 'major':
                                major++
                                minor = 0
                                patch = 0
                                break
                            case 'minor':
                                minor++
                                patch = 0
                                break
                            case 'patch':
                            default:
                                patch++
                                break
                        }
                        
                        env.MODULE_VERSION = "${major}.${minor}.${patch}"
                        echo "Next version (${params.VERSION_TYPE}): ${env.MODULE_VERSION}"
                    }
                }
            }
        }

        stage('Check/Create Module') {
            steps {
                script {
                    echo "Checking if module already exists in registry..."
                    def check = sh(script: """#!/bin/bash
                        mkdir -p "${ARTIFACTS_DIR}"
                        curl -s -H "Authorization: Bearer ${TF_API_TOKEN}" \\
                          https://app.terraform.io/api/v2/organizations/${params.ORG}/registry-modules/private/${params.ORG}/${params.MODULE_NAME}/${params.MODULE_PROVIDER} \\
                          | tee "${ARTIFACTS_DIR}/check_module_response.json" | grep -q '"name"'
                    """, returnStatus: true)
                    env.CREATE_MODULE = (check != 0).toString()
                    echo "Module exists: ${check == 0 ? 'Yes' : 'No'}"
                }
            }
        }

        stage('Package Module') {
            steps {
                sh """#!/bin/bash
                    echo "📦 Creating module package..."
                    mkdir -p "${ARTIFACTS_DIR}/module"
                    
                    # Copy all .tf files with directory structure
                    find . -name "*.tf" -not -path "./.terraform/*" -not -path "./artifacts/*" -not -path "./.git/*" -exec cp --parents {} "${ARTIFACTS_DIR}/module/" \\;
                    
                    # Copy documentation and examples
                    find . -name "*.md" -not -path "./.terraform/*" -not -path "./artifacts/*" -not -path "./.git/*" -exec cp --parents {} "${ARTIFACTS_DIR}/module/" \\; 2>/dev/null || true
                    
                    # Copy directories if they exist
                    for dir in examples tests modules; do
                        if [ -d "\$dir" ]; then
                            cp -r "\$dir" "${ARTIFACTS_DIR}/module/"
                        fi
                    done
                    
                    # Create package
                    tar -czf "${ARTIFACTS_DIR}/module.tar.gz" -C "${ARTIFACTS_DIR}/module" .
                    
                    echo "Package contents:"
                    tar -tzf "${ARTIFACTS_DIR}/module.tar.gz" | head -10
                """
            }
        }

        stage('Create Module in TFC') {
            when { environment name: 'CREATE_MODULE', value: 'true' }
            steps {
                script {
                    echo "🆕 Creating new module in Terraform Cloud..."
                    writeFile file: "${ARTIFACTS_DIR}/create-module.json", text: """
{
  "data": {
    "type": "registry-modules",
    "attributes": {
      "name": "${params.MODULE_NAME}",
      "provider": "${params.MODULE_PROVIDER}",
      "registry-name": "${REGISTRY_NAME}",
      "no-code": true
    }
  }
}
"""
                }
                sh """#!/bin/bash
                    curl -s -f -H "Authorization: Bearer ${TF_API_TOKEN}" \\
                         -H "Content-Type: application/vnd.api+json" \\
                         -d @"${ARTIFACTS_DIR}/create-module.json" \\
                         https://app.terraform.io/api/v2/organizations/${params.ORG}/registry-modules \\
                         -o "${ARTIFACTS_DIR}/create_module_response.json"
                    echo "✅ Module created successfully"
                """
            }
        }

        stage('Publish to Registry') {
            steps {
                script {
                    echo "📤 Publishing version ${env.MODULE_VERSION} to registry..."
                    writeFile file: "${ARTIFACTS_DIR}/create-version.json", text: """
{
  "data": {
    "type": "registry-module-versions",
    "attributes": {
      "version": "${env.MODULE_VERSION}",
      "commit-sha": "${GIT_COMMIT_SHA}"
    }
  }
}
"""
                }
                sh """#!/bin/bash
                    # Create version
                    curl -s -f -H "Authorization: Bearer ${TF_API_TOKEN}" \\
                         -H "Content-Type: application/vnd.api+json" \\
                         -d @"${ARTIFACTS_DIR}/create-version.json" \\
                         https://app.terraform.io/api/v2/organizations/${params.ORG}/registry-modules/private/${params.ORG}/${params.MODULE_NAME}/${params.MODULE_PROVIDER}/versions \\
                         -o "${ARTIFACTS_DIR}/version_response.json"

                    # Extract upload URL
                    UPLOAD_URL=\$(grep -o '"upload":"[^"]*"' "${ARTIFACTS_DIR}/version_response.json" | cut -d'"' -f4)
                    
                    if [ -z "\$UPLOAD_URL" ]; then
                        echo "❌ Failed to get upload URL"
                        cat "${ARTIFACTS_DIR}/version_response.json"
                        exit 1
                    fi

                    echo "Uploading to: \$UPLOAD_URL"
                    
                    # Upload package
                    curl -s -f -H "Content-Type: application/octet-stream" \\
                         --request PUT --data-binary @"${ARTIFACTS_DIR}/module.tar.gz" "\$UPLOAD_URL"
                    
                    echo "✅ Module version ${env.MODULE_VERSION} published successfully"
                """
            }
        }

        stage('Update CHANGELOG') {
            steps {
                script {
                    echo "📝 Updating CHANGELOG..."
                    
                    // Create or update CHANGELOG.md
                    def changelogExists = fileExists('CHANGELOG.md')
                    def changelog = ""
                    
                    if (changelogExists) {
                        changelog = readFile('CHANGELOG.md')
                    } else {
                        changelog = "# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n"
                    }
                    
                    def today = new Date().format('yyyy-MM-dd')
                    def newEntry = """## [${env.MODULE_VERSION}] - ${today}

### Added
- Module version ${env.MODULE_VERSION} published to Terraform Cloud Registry
- Commit: ${GIT_COMMIT_SHA}

"""
                    
                    // Insert new entry after the header
                    def lines = changelog.split('\n')
                    def newChangelog = ""
                    def headerFound = false
                    
                    for (int i = 0; i < lines.length; i++) {
                        newChangelog += lines[i] + '\n'
                        if (!headerFound && lines[i].trim().isEmpty() && i > 0) {
                            newChangelog += newEntry
                            headerFound = true
                        }
                    }
                    
                    if (!headerFound) {
                        newChangelog += newEntry
                    }
                    
                    writeFile file: 'CHANGELOG.md', text: newChangelog
                    
                    echo "✅ CHANGELOG.md updated with version ${env.MODULE_VERSION}"
                }
                
                // Commit and tag the new version
                sh """#!/bin/bash
                    git config --global user.email "jenkins@company.com"
                    git config --global user.name "Jenkins CI"
                    
                    git add CHANGELOG.md
                    git commit -m "chore: update CHANGELOG for version ${env.MODULE_VERSION}" || true
                    git tag -a "v${env.MODULE_VERSION}" -m "Release version ${env.MODULE_VERSION}"
                    
                    echo "✅ Tagged version v${env.MODULE_VERSION}"
                """
            }
        }
    }

    post {
        always {
            script {
                echo "📊 Pipeline Summary:"
                echo "  - Module: ${params.MODULE_NAME}"
                echo "  - Provider: ${params.MODULE_PROVIDER}"
                echo "  - Version: ${env.MODULE_VERSION ?: 'N/A'}"
                echo "  - Commit: ${GIT_COMMIT_SHA}"
            }
            archiveArtifacts artifacts: 'artifacts/**/*', allowEmptyArchive: true
            cleanWs()
        }
        success {
            echo "✅ Module ${params.MODULE_NAME} version ${env.MODULE_VERSION} successfully published to Terraform Cloud Registry!"
        }
        failure {
            echo "❌ Failed to publish module ${params.MODULE_NAME}. Check artifacts and logs for details."
        }
    }
}
