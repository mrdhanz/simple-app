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

    stages {
        stage('Checkout') {
            steps {
                git branch: 'master', url: 'https://github.com/mrdhanz/simple-app.git', credentialsId: 'Git'
            }
        }

        stage('Install Dependencies') {
            when {
                expression { return !params.DESTROY }
            }
            steps {
                sh 'npm install'
            }
        }

        stage('Building Apps for each environment') {
            when {
                expression { return !params.DESTROY }
            }
            steps {
                script {
                    def envDirectory = 'environment'
                    def envFiles = findFiles(glob: "${envDirectory}/.env.*")

                    if (envFiles.length == 0) {
                        error "No .env files found in ${envDirectory}"
                    }

                    envFiles.each { envFile ->
                        def envName = envFile.name.replace('.env.', '')
                        echo "Building for environment: ${envName}"
                        sh 'rm -rf .env'
                        sh "cp ${envFile.path} .env"
                        withEnv(["ENV_FILE=${envFile.path}"]) {
                            echo "Running build for ${envName} using ${envFile.path}"
                            sh 'npm run build'
                            sh "sudo docker build -t ${DOCKER_IMAGE}-${envName}:${env.BUILD_ID} -f Dockerfile ."
                            sh "sudo docker tag ${DOCKER_IMAGE}-${envName}:${env.BUILD_ID} ${DOCKER_IMAGE}-${envName}:latest"
                        }
                    }
                }
            }
        }

        stage('Pushing Docker Images to registry') {
            when {
                expression { return !params.DESTROY }
            }
            steps {
                script {
                    def envDirectory = 'environment'
                    def envFiles = findFiles(glob: "${envDirectory}/.env.*")

                    if (envFiles.length == 0) {
                        error "No .env files found in ${envDirectory}"
                    }

                    envFiles.each { envFile ->
                        def envName = envFile.name.replace('.env.', '')
                        echo "Building for environment: ${envName}"
                        sh 'rm -rf .env'
                        sh "cp ${envFile.path} .env"
                        withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS_ID}", usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                            sh """
                            echo ${DOCKER_PASSWORD} | sudo docker login -u ${DOCKER_USERNAME} --password-stdin
                            sudo docker push ${DOCKER_IMAGE}-${envName}:latest
                            """
                        }
                    }
                }
            }
        }

        stage('Deploying Apps to Kubernetes') {
            when {
                expression { return !params.DESTROY }
            }
            steps {
                script {
                    def envDirectory = 'environment'
                    def envFiles = findFiles(glob: "${envDirectory}/.env.*")

                    if (envFiles.length == 0) {
                        error "No .env files found in ${envDirectory}"
                    }

                    sh 'terraform init'

                    envFiles.each { envFile ->
                        def envName = envFile.name.replace('.env.', '')
                        loadVarsFromFile(envFile.path)
                        echo "Applying Terraform for environment: ${envName}"
                        withEnv(["ENV_FILE=${envFile.path}", ]) {
                            withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                sh """
                                terraform workspace select -or-create=true ${envName}
                                terraform apply -auto-approve \
                                -var 'app_name=${envName}' \
                                -var 'namespace_name=${envName}' \
                                -var 'docker_image=${DOCKER_IMAGE}-${envName}:latest' \
                                -var 'public_port=${env.PUBLIC_PORT}'
                                """
                            }
                        }
                    }
                }
            }
        }

        stage('Destroy Terraform') {
            when {
                expression { return params.DESTROY }
            }
            steps {
                script {
                    def envDirectory = 'environment'
                    def envFiles = findFiles(glob: "${envDirectory}/.env.*")

                    if (envFiles.length == 0) {
                        error "No .env files found in ${envDirectory}"
                    }

                    envFiles.each { envFile ->
                        def envName = envFile.name.replace('.env.', '')
                        echo "Destroying Terraform for environment: ${envName}"
                        def tfvarsFile = "${envDirectory}/${envName}.tfvars"

                        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                            sh """
                            terraform workspace select ${envName}
                            terraform destroy -auto-approve -var-file=${tfvarsFile}
                            terraform workspace select default
                            terraform workspace delete ${envName}
                            """
                        }
                    }
                }
            }
        }
    }
}

private void loadVarsFromFile(String path) {
    def file = readFile(path)
        .replaceAll('(?m)^\\s*\\r?\\n', '')  // skip empty line
        .replaceAll('(?m)^#[^\\n]*\\r?\\n', '')  // skip commented lines
    file.split('\n').each { envLine ->
        def (key, value) = envLine.tokenize('=')
        env."${key}" = "${value.trim().replaceAll('^\"|\"$', '')}"
    }
}