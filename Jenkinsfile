pipeline {
    agent any

    parameters {
        string(name: 'UI_TAG', defaultValue: 'v01.01.00', description: 'hub-ui image tag to bundle')
        string(name: 'API_TAG', defaultValue: 'v01.01.00', description: 'hub-api image tag to bundle')
        string(name: 'DB_TAG', defaultValue: 'v01.01.00', description: 'hub-db image tag to bundle')
    }

    environment {
        AWS_REGION     = "us-east-2"
        AWS_ACCOUNT_ID = "427479402536"
        S3_BUCKET      = "bridge-dev1-bucket-edge-app"
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
