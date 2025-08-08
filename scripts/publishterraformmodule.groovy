def publishModuleFunction(String org, String version, String name, String provider, String artifactsDir, String gitCommitSha, String tfApiToken) {

stage('Validate Parameters') {
    echo "Validating parameters..."
    echo "MODULE_VERSION from Jenkins: '${MODULE_VERSION}'"
    if (!MODULE_VERSION || !(MODULE_VERSION ==~ /^\d+\.\d+\.\d+$/)) {
        error "Invalid version format"
    }
}


    
    stage('Setup Tools') {
        sh """#!/bin/bash
            mkdir -p /tmp/jenkins-tools
            export PATH="/tmp/jenkins-tools:\$PATH"

            ARCH=\$(uname -m)
            TERRAFORM_ARCH="\$( [ "\$ARCH" = "x86_64" ] && echo amd64 || echo arm64 )"

            if [ ! -f "/tmp/jenkins-tools/terraform" ]; then
                curl -fsSL https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_\$TERRAFORM_ARCH.zip -o terraform.zip
                unzip -o -q terraform.zip -d /tmp/jenkins-tools
                chmod +x /tmp/jenkins-tools/terraform
                rm terraform.zip
            fi

            ln -sf \$(which python3 || which python || echo "/bin/false") /tmp/jenkins-tools/python3 || true
        """
    }

    stage('Terraform Validate') {
        sh """#!/bin/bash
            export PATH="/tmp/jenkins-tools:\$PATH"
            terraform init -backend=false
            terraform validate
        """
    }

    stage('Check/Create Module') {
        def check = sh(script: """#!/bin/bash
            mkdir -p "${artifactsDir}"
            curl -s -H "Authorization: Bearer ${tfApiToken}" \\
              https://app.terraform.io/api/v2/organizations/${org}/registry-modules/private/${org}/${name}/${provider} \\
              | tee "${artifactsDir}/check_module_response.json" | grep -q '"name"'
        """, returnStatus: true)
        env.CREATE_MODULE = (check != 0).toString()
    }

    if (env.CREATE_MODULE == 'true') {
        stage('Create Module in TFC') {
            writeFile file: "${artifactsDir}/create-module.json", text: """
{
  "data": {
    "type": "registry-modules",
    "attributes": {
      "name": "${name}",
      "provider": "${provider}",
      "registry-name": "private",
      "no-code": true
    }
  }
}
"""
            sh """#!/bin/bash
                curl -s -f -H "Authorization: Bearer ${tfApiToken}" \\
                     -H "Content-Type: application/vnd.api+json" \\
                     -d @"${artifactsDir}/create-module.json" \\
                     https://app.terraform.io/api/v2/organizations/${org}/registry-modules \\
                     -o "${artifactsDir}/create_module_response.json"
            """
        }
    }

    stage('Package Module') {
        sh """#!/bin/bash
            mkdir -p "${artifactsDir}/module"
            find . -name "*.tf" -exec cp --parents {} "${artifactsDir}/module/" \\;
            tar -czf "${artifactsDir}/module.tar.gz" -C "${artifactsDir}/module" .
        """
    }

    stage('Create & Upload Version') {
        writeFile file: "${artifactsDir}/create-version.json", text: """
{
  "data": {
    "type": "registry-module-versions",
    "attributes": {
      "version": "${version}",
      "commit-sha": "${gitCommitSha}"
    }
  }
}
"""
        sh """#!/bin/bash
            curl -s -f -H "Authorization: Bearer ${tfApiToken}" \\
                 -H "Content-Type: application/vnd.api+json" \\
                 -d @"${artifactsDir}/create-version.json" \\
                 https://app.terraform.io/api/v2/organizations/${org}/registry-modules/private/${org}/${name}/${provider}/versions \\
                 -o "${artifactsDir}/version_response.json"

            UPLOAD_URL=\$(grep -o '"upload":"[^"]*"' "${artifactsDir}/version_response.json" | cut -d'"' -f4)

            curl -s -f -H "Content-Type: application/octet-stream" \\
                 --request PUT --data-binary @"${artifactsDir}/module.tar.gz" "\$UPLOAD_URL"
        """
    }

    echo "✅ Module ${name} version ${version} uploaded to Terraform Cloud"
}

return this
