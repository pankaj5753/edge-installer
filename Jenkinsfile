pipeline {
    agent any

    parameters {
        string(name: 'UI_TAG', defaultValue: 'v01.01.00', description: 'hub-ui image tag to bundle')
        string(name: 'API_TAG', defaultValue: 'v01.01.00', description: 'hub-api image tag to bundle')
        string(name: 'DB_TAG', defaultValue: 'v01.01.00', description: 'hub-db image tag to bundle')
        choice(name: 'ENV_TIER', choices: ['qa', 'dev', 'preprod', 'prod'], description: 'Which edge-api env tier to sync JWT/Okta/proxy values from into .env.prod.example - must match the ENV_TIER used on the edge-api ECR_PUSH build that produced API_TAG. QA is currently standing in for prod.')
    }

    environment {
        AWS_REGION          = "us-east-2"
        AWS_ACCOUNT_ID      = "427479402536"
        S3_BUCKET           = "bridge-dev1-bucket-edge-app"
        ENV_ARTIFACT_BUCKET = "bridge-dev1-bucket-edge-app"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                // Windows-authored checkouts sometimes lose the exec bit.
                sh 'chmod +x release/*.sh'
            }
        }

        stage('Prepare') {
            steps {
                script {
                    env.BUNDLE_VERSION = readFile('VERSION').trim()
                }
                sh '''
                    echo "Bundle Version : ${BUNDLE_VERSION}"
                    echo "UI Tag         : ${UI_TAG}"
                    echo "API Tag        : ${API_TAG}"
                    echo "DB Tag         : ${DB_TAG}"
                '''
            }
        }

        // Pulls all 3 images from ECR, saves the combined archive +
        // DIGESTS, syncs .env.example (release/download-images.sh).
        stage('Download Images') {
            steps {
                sh '''
                    set -e
                    ./release/download-images.sh ${BUNDLE_VERSION} ${UI_TAG} ${API_TAG} ${DB_TAG}
                '''
            }
        }

        // Syncs JWT/Okta/proxy values from edge-api's published env-tier snippet
        // into .env.prod.example (see release/sync-env-tier.sh).
        stage('Sync Env Config') {
            steps {
                sh '''
                    set -e
                    aws s3 cp "s3://${ENV_ARTIFACT_BUCKET}/hub-api-env/${API_TAG}.env" hub-api-env-tier.env
                    ./release/sync-env-tier.sh hub-api-env-tier.env
                    rm -f hub-api-env-tier.env
                '''
            }
        }

        // Builds dist/snn-hub-install-{version}-linux-x64.tar.gz + .sha256.
        stage('Package Bundle') {
            steps {
                sh './release/package-release.sh'
            }
        }

        // Uploads to S3 with --checksum-algorithm SHA256, prints the 7-day signed URL.
        stage('Publish to S3') {
            steps {
                sh './release/publish-bundle.sh'
            }
        }
    }

    post {
        success {
            echo "Bundle ${BUNDLE_VERSION} published to s3://${S3_BUCKET}/"
            archiveArtifacts artifacts: 'dist/*.tar.gz,dist/*.sha256', fingerprint: true, onlyIfSuccessful: true
        }

        failure {
            echo "Bundle publish pipeline failed. Check the build log for details."
        }

        cleanup {
            sh '''
                docker rmi snn-hub-ui:${UI_TAG} || true
                docker rmi snn-hub-api:${API_TAG} || true
                docker rmi snn-hub-db:${DB_TAG} || true
                docker rmi ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sandbox/bridge/snn-hub-ui:${UI_TAG} || true
                docker rmi ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sandbox/bridge/snn-hub-api:${API_TAG} || true
                docker rmi ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sandbox/bridge/snn-hub-db:${DB_TAG} || true
            '''
        }
    }
}
