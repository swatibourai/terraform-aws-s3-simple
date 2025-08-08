pipeline {
    agent any

    environment {
        ORG = "Chase-UK-Org"
        MODULE_VERSION = "1.0.0"
        MODULE_NAME = "s3-simple"
        MODULE_PROVIDER = "aws"
        GITHUB_REPO = "https://github.com/swatibourai/terraform-aws-s3-simple.git"
        GITHUB_CREDENTIALS_ID = "github-personal" // Jenkins credentials ID for GitHub
        TF_API_TOKEN = credentials('terraform-cloud-api-token') // picked from Jenkins credentials
        REGISTRY_NAME = 'private'
        WORKSPACE_DIR = "${env.WORKSPACE}"
        ARTIFACTS_DIR = "${env.WORKSPACE}/artifacts"
    }

    parameters {
        string(name: 'ORG', defaultValue: 'Chase-UK-Org', description: 'Terraform organization name')
        string(name: 'MODULE_VERSION', defaultValue: '1.0.0', description: 'Module version')
        string(name: 'MODULE_NAME', defaultValue: 's3-simple', description: 'Terraform module name')
        string(name: 'MODULE_PROVIDER', defaultValue: 'aws', description: 'Module provider')
        string(name: 'GIT_COMMIT', defaultValue: '', description: 'Git commit SHA (leave empty to use env.GIT_COMMIT)')
        string(name: 'GIT_BRANCH', defaultValue: 'main', description: 'Git branch name (leave empty to use env.GIT_BRANCH)')
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: params.GIT_BRANCH ?: 'main', 
                    url: env.GITHUB_REPO, 
                    credentialsId: env.GITHUB_CREDENTIALS_ID
            }
        }

        stage('Run Publish Module') {
               when { expression { true } } 

            
            steps {
                script {
                    def publishModule = load 'scripts/publishterraformmodule.groovy'
                    publishModule.publishModuleFunction(
                        env.ORG,
                        env.MODULE_VERSION,
                        env.MODULE_NAME,
                        env.MODULE_PROVIDER,
                        env.TF_API_TOKEN, // pass token from env
                        env.ARTIFACTS_DIR
                    )
                }
            }
        }
    }
}
