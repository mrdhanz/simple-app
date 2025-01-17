pipeline {
    agent any
    parameters {
        booleanParam(defaultValue: false, description: 'Destroy the infrastructure', name: 'DESTROY')
    }

    environment {
        KUBE_CONFIG = credentials('kubeconfig')
        DOCKER_CREDENTIALS_ID = 'docker-credentials'
        DOCKER_IMAGE = 'mrdhanz/simple'
    }

    tools {
        nodejs 'nodejs-22'
        terraform 'terraform'
    }

    triggers {
        githubPush()  // Triggers the pipeline on GitHub push
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'master', url: 'https://github.com/mrdhanz/simple-app.git', credentialsId: 'Git'
            }
        }

        stage('Install Dependencies') {
            when { not { equals expected: true, actual: params.DESTROY } }
            steps {
                sh 'npm install'
            }
        }

        stage('Build and Push Docker Images') {
            when { not { equals expected: true, actual: params.DESTROY } }
            steps {
                script {
                    def envFiles = findFiles(glob: 'environment/.env.*')
                    def parallelSteps = [:]  // Create an empty map for parallel steps

                    envFiles.each { envFile ->
                        def envName = envFile.name.replace('.env.', '')

                        parallelSteps[envName] = {
                            stage("Building and pushing for ${envName}") {
                                echo "Building and pushing Docker image for environment: ${envName}"

                                // Load environment variables from the .env file using withEnv
                                def envVars = readFile(envFile.path)
                                        .replaceAll('(?m)^\\s*\\r?\\n', '')
                                        .replaceAll('(?m)^#[^\\n]*\\r?\\n', '')
                                        .split('\n').collect { line ->
                                                        return line.trim() && !line.startsWith('#') ? line : null
                                }.findAll { it != null }

                                withEnv(envVars) {
                                    sh "GENERATE_SOURCEMAP=false BUILD_PATH=./${envName}-build npm run build"

                                    // Docker build using the current directory context
                                    sh "docker build -t ${DOCKER_IMAGE}-${envName}:${env.BUILD_ID} -f Dockerfile ./${envName}-build"

                                    // Docker login and push the image
                                    withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS_ID}", usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                                        sh "echo ${DOCKER_PASSWORD} | docker login -u ${DOCKER_USERNAME} --password-stdin"
                                        sh "docker push ${DOCKER_IMAGE}-${envName}:${env.BUILD_ID}"
                                        // remove the image from the local machine after pushing it to the registry
                                        sh "docker rmi ${DOCKER_IMAGE}-${envName}:${env.BUILD_ID}"
                                    }
                                }
                            }
                        }
                    }

                    // Run all environment builds in parallel
                    parallel parallelSteps
                }
            }
        }

        stage('Deploy to Kubernetes') {
            when { not { equals expected: true, actual: params.DESTROY } }
            steps {
                script {
                    def envFiles = findFiles(glob: 'environment/.env.*')

                    sh 'terraform init'

                    envFiles.each { envFile ->
                        def envName = envFile.name.replace('.env.', '')
                        echo "Deploying to Kubernetes for environment: ${envName}"
                        loadVarsFromFile(envFile.path, envName)
                        def publicPort = env."${envName}_PUBLIC_PORT"
                        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                            sh """
                                terraform workspace select -or-create=true ${envName}
                                terraform apply -auto-approve \
                                -var 'app_name=${envName}' \
                                -var 'namespace_name=${envName}' \
                                -var 'public_port=${publicPort}' \
                                -var 'docker_image=${DOCKER_IMAGE}-${envName}:${env.BUILD_ID}' \
                                -var 'build_number=${env.BUILD_ID}'
                            """
                        }
                    }
                }
            }
        }

        stage('Destroy Infrastructure') {
            when { equals expected: true, actual: params.DESTROY }
            steps {
                script {
                    def envFiles = findFiles(glob: 'environment/.env.*')

                    envFiles.each { envFile ->
                        def envName = envFile.name.replace('.env.', '')

                        echo "Destroying infrastructure for environment: ${envName}"
                        loadVarsFromFile(envFile.path, envName)
                        def publicPort = env."${envName}_PUBLIC_PORT"
                        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                            sh """
                                terraform workspace select -or-create=true ${envName}
                                terraform destroy -auto-approve \
                                -var 'app_name=${envName}' \
                                -var 'namespace_name=${envName}' \
                                -var 'public_port=${publicPort}' \
                                -var 'docker_image=${DOCKER_IMAGE}-${envName}:latest' \
                                -var 'build_number=${env.BUILD_ID}'
                            """
                        }
                    }
                }
            }
        }
        }
    }

private void loadVarsFromFile(String path, String envName) {
    def file = readFile(path)
        .replaceAll('(?m)^\\s*\\r?\\n', '')  // skip empty line
        .replaceAll('(?m)^#[^\\n]*\\r?\\n', '')  // skip commented lines
    file.split('\n').each { envLine ->
        def (key, value) = envLine.tokenize('=')
        env."${envName}_${key}" = "${value.trim().replaceAll('^\"|\"$', '')}"
    }
}
