pipeline {
    agent any

    environment {
        ORG = "Chase-UK-Org"
        MODULE_VERSION = "1.0.0"
        MODULE_NAME = "s3-simple"
        MODULE_PROVIDER = "aws"
        GITHUB_REPO = "https://github.com/swatibourai/terraform-aws-s3-simple.git"
        GITHUB_CREDENTIALS_ID = "github-personal" // ID of the credentials in Jenkins
    }

    stages {
        stage('Checkout') {
            steps {
                // Use Jenkins credentials for GitHub checkout
                git branch: 'main', 
                    url: env.GITHUB_REPO, 
                    credentialsId: env.GITHUB_CREDENTIALS_ID
            }
        }

        stage('Run Publish Module') {
            when {
                branch 'main'
            }
            steps {
                script {
                    // Load and run the publish function
                    def publishModule = load 'scripts/publishModule.groovy'
                    publishModule.publishModuleFunction(
                        env.ORG,
                        env.MODULE_VERSION,
                        env.MODULE_NAME,
                        env.MODULE_PROVIDER
                    )
                }
            }
        }
    }
}

