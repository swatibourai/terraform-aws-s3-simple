pipeline {
    agent any

    parameters {
        string(name: 'ORG', defaultValue: 'Chase-UK-Org', description: 'Terraform organization name')
        string(name: 'MODULE_VERSION', defaultValue: '1.0.0', description: 'Module version')
        string(name: 'MODULE_NAME', defaultValue: 's3-simple', description: 'Terraform module name')
        string(name: 'MODULE_PROVIDER', defaultValue: 'aws', description: 'Module provider')
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
                    if (!params.MODULE_VERSION.matches(/^[0-9]+\.[0-9]+\.[0-9]+$/)) error("Invalid version format")
                }
            }
        }

        stage('Setup Tools') {
            steps {
                sh '''#!/bin/bash
                    mkdir -p /tmp/jenkins-tools
                    export PATH="/tmp/jenkins-tools:$PATH"

                    ARCH=$(uname -m)
                    TERRAFORM_ARCH="$( [ "$ARCH" = "x86_64" ] && echo amd64 || echo arm64 )"

                    if [ ! -f "/tmp/jenkins-tools/terraform" ]; then
                        curl -fsSL https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_$TERRAFORM_ARCH.zip -o terraform.zip
                        unzip -o -q terraform.zip -d /tmp/jenkins-tools
                        chmod +x /tmp/jenkins-tools/terraform
                        rm terraform.zip
                    fi

                    ln -sf $(which python3 || which python || echo "/bin/false") /tmp/jenkins-tools/python3 || true
                '''
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

        stage('Terraform Validate') {
            steps {
                sh '''#!/bin/bash
                    export PATH="/tmp/jenkins-tools:$PATH"
                    terraform init -backend=false
                    terraform validate
                '''
            }
        }

        stage('Check/Create Module') {
            steps {
                script {
                    echo "📦 Checking if module and version already exist in registry..."
                    sh '''#!/bin/bash
                        mkdir -p "${ARTIFACTS_DIR}"
                        curl -s -H "Authorization: Bearer ${TF_API_TOKEN}" \
                          https://app.terraform.io/api/v2/organizations/${ORG}/registry-modules/private/${ORG}/${MODULE_NAME}/${MODULE_PROVIDER} \
                          -o "${ARTIFACTS_DIR}/check_module_response.json"
                    '''

                    def moduleData = readJSON file: "${ARTIFACTS_DIR}/check_module_response.json"
                    def moduleExists = !(moduleData?.errors)

                    if (!moduleExists) {
                        echo "ℹ️ Module does not exist yet. Proceeding to create it."
                        env.CREATE_MODULE = 'true'
                        env.SKIP_VERSION_UPLOAD = 'false'
                    } else {
                        echo "✅ Module already exists. Checking versions..."

                        sh '''#!/bin/bash
                            curl -s -H "Authorization: Bearer ${TF_API_TOKEN}" \
                              https://app.terraform.io/api/v2/organizations/${ORG}/registry-modules/private/${ORG}/${MODULE_NAME}/${MODULE_PROVIDER}/versions \
                              -o "${ARTIFACTS_DIR}/check_versions_response.json"
                        '''

                        def versionData = readJSON file: "${ARTIFACTS_DIR}/check_versions_response.json"
                        def existingVersions = versionData?.data.collect { it.attributes.version }
                        echo "📃 Existing versions in registry: ${existingVersions.join(', ')}"

                        def versionCompare = { a, b ->
                            def va = a.tokenize('.')*.toInteger()
                            def vb = b.tokenize('.')*.toInteger()
                            for (int i = 0; i < Math.max(va.size(), vb.size()); i++) {
                                def ai = i < va.size() ? va[i] : 0
                                def bi = i < vb.size() ? vb[i] : 0
                                if (ai != bi) return ai <=> bi
                            }
                            return 0
                        }

                        if (existingVersions.contains(MODULE_VERSION)) {
                            echo "⛔ Module version ${MODULE_VERSION} already exists. Skipping upload."
                            env.SKIP_VERSION_UPLOAD = 'true'
                        } else if (existingVersions.any { versionCompare(it, MODULE_VERSION) > 0 }) {
                            echo "⚠️ A higher version than ${MODULE_VERSION} already exists in registry."
                            env.SKIP_VERSION_UPLOAD = 'true'
                        } else {
                            echo "✅ Target version ${MODULE_VERSION} is newer. Proceeding with upload."
                            env.SKIP_VERSION_UPLOAD = 'false'
                        }

                        env.CREATE_MODULE = 'false'
                    }
                }
            }
        }

        stage('Package Module') {
            steps {
                sh '''#!/bin/bash
                    mkdir -p "${ARTIFACTS_DIR}/module"
                    find . -name "*.tf" -exec cp --parents {} "${ARTIFACTS_DIR}/module/" \;
                    tar -czf "${ARTIFACTS_DIR}/module.tar.gz" -C "${ARTIFACTS_DIR}/module" .
                '''
            }
        }

        stage('Create Module in TFC') {
            when { environment name: 'CREATE_MODULE', value: 'true' }
            steps {
                echo "🚀 Creating module ${MODULE_NAME} in Terraform Cloud..."
                script {
                    writeFile file: "${ARTIFACTS_DIR}/create-module.json", text: """
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
                }
                sh '''#!/bin/bash
                    curl -s -f -H "Authorization: Bearer ${TF_API_TOKEN}" \
                         -H "Content-Type: application/vnd.api+json" \
                         -d @"${ARTIFACTS_DIR}/create-module.json" \
                         https://app.terraform.io/api/v2/organizations/${ORG}/registry-modules \
                         -o "${ARTIFACTS_DIR}/create_module_response.json"
                '''
            }
        }

        stage('Create & Upload Version') {
            when { environment name: 'SKIP_VERSION_UPLOAD', value: 'false' }
            steps {
                echo "🚀 Creating and uploading version ${MODULE_VERSION}..."
                script {
                    writeFile file: "${ARTIFACTS_DIR}/create-version.json", text: """
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
                }
                sh '''#!/bin/bash
                    curl -s -f -H "Authorization: Bearer ${TF_API_TOKEN}" \
                         -H "Content-Type: application/vnd.api+json" \
                         -d @"${ARTIFACTS_DIR}/create-version.json" \
                         https://app.terraform.io/api/v2/organizations/${ORG}/registry-modules/private/${ORG}/${MODULE_NAME}/${MODULE_PROVIDER}/versions \
                         -o "${ARTIFACTS_DIR}/version_response.json"

                    UPLOAD_URL=$(grep -o '"upload":"[^"]*"' "${ARTIFACTS_DIR}/version_response.json" | cut -d'"' -f4)

                    curl -s -f -H "Content-Type: application/octet-stream" \
                         --request PUT --data-binary @"${ARTIFACTS_DIR}/module.tar.gz" "$UPLOAD_URL"
                '''
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'artifacts/**/*', allowEmptyArchive: true
            cleanWs()
        }
        success {
            echo "✅ Module ${MODULE_NAME} version ${MODULE_VERSION} uploaded to Terraform Cloud"
        }
        failure {
            echo "❌ Failed to upload module ${MODULE_NAME}. Check artifacts and logs for details."
        }
    }
}
