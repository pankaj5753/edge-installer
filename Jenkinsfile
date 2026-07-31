pipeline {
    agent any

    parameters {
        string(name: 'UI_TAG', defaultValue: '1.0.0', description: 'edge-ui image tag to bundle')
        string(name: 'API_TAG', defaultValue: '1.0.0', description: 'edge-api image tag to bundle')
        string(name: 'DB_TAG', defaultValue: '1.0.0', description: 'edge-db image tag to bundle')
    }

    environment {
        AWS_REGION     = "us-east-2"
        AWS_ACCOUNT_ID = "427479402536"
        S3_BUCKET      = "sportsmed-edge-installer-app-bucket"
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

        // Builds dist/edge-install-{version}-linux-x64.tar.gz + .sha256.
        stage('Package Bundle') {
            steps {
                sh './release/package-release.sh'
            }
        }

        // Uploads to S3 with --checksum-algorithm SHA256, prints the
        // 7-day signed URL (EDG-15 AC1/AC4).
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
                docker rmi snn-edge-ui:${UI_TAG} || true
                docker rmi snn-edge-api:${API_TAG} || true
                docker rmi snn-edge-db:${DB_TAG} || true
                docker rmi ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sandbox/bridge/snn-edge-ui:${UI_TAG} || true
                docker rmi ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sandbox/bridge/snn-edge-api:${API_TAG} || true
                docker rmi ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sandbox/bridge/snn-edge-db:${DB_TAG} || true
            '''
        }
    }
}
