pipeline {
  agent any

  tools {
    jdk 'JAVA_HOME'
    maven 'M2_HOME'
  }

  options {
    timestamps()
    skipDefaultCheckout(true)
  }

  environment {
    DOCKER_REPO = "salima20033/timesheet-devops"

    IMAGE_TAG   = "${BUILD_NUMBER}"
    DOCKER_IMAGE = "${DOCKER_REPO}:${IMAGE_TAG}"
    DOCKER_LATEST = "${DOCKER_REPO}:latest"

    K8S_NAMESPACE = "devops"
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build Maven') {
      steps {
        sh 'mvn -B clean package -DskipTests'
      }
    }

    stage('Docker Build & Push') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            set -e
            docker version

            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin

            docker build -t "$DOCKER_IMAGE" -t "$DOCKER_LATEST" .
            docker push "$DOCKER_IMAGE"
            docker push "$DOCKER_LATEST"

            docker logout
          '''
        }
      }
    }

    stage('Deploy Kubernetes') {
      steps {
        sh '''
          set -e
          minikube status

          # namespace
          minikube kubectl -- get ns "$K8S_NAMESPACE" >/dev/null 2>&1 || minikube kubectl -- create ns "$K8S_NAMESPACE"

          # apply mysql + app manifests
          minikube kubectl -- apply -n "$K8S_NAMESPACE" -f k8s/mysql-deployment.yaml
          minikube kubectl -- apply -n "$K8S_NAMESPACE" -f k8s/spring-deployment.yaml

          # force deployment to use the newly built image tag
          minikube kubectl -- set image deployment/spring-app spring-app="$DOCKER_IMAGE" -n "$K8S_NAMESPACE"
          minikube kubectl -- rollout status deployment/spring-app -n "$K8S_NAMESPACE" --timeout=180s

          minikube kubectl -- get pods -n "$K8S_NAMESPACE"
          minikube kubectl -- get svc  -n "$K8S_NAMESPACE"
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
    }
  }
}
