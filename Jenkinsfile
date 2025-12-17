pipeline {
  agent any

  tools {
    jdk 'JAVA_HOME'
    maven 'M2_HOME'
  }

  environment {
    K8S_NAMESPACE = "devops"
    DOCKER_REPO   = "selimabll1/timesheet-app"   // change si ton repo dockerhub est différent
    IMAGE_TAG     = "${BUILD_NUMBER}"
  }

  stages {
    stage('Checkout') {
      steps {
        git branch: 'master', url: 'https://github.com/selimabll1/timesheetproject-ci.git'
      }
    }

    stage('Build Maven') {
      steps {
        sh 'mvn -Dmaven.test.skip=true clean package'
      }
    }

    stage('Docker Build & Push') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
            docker build -t ${DOCKER_REPO}:${IMAGE_TAG} .
            docker push ${DOCKER_REPO}:${IMAGE_TAG}
          '''
        }
      }
    }

    stage('Deploy Kubernetes') {
      steps {
        sh '''
          kubectl create namespace ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

          kubectl apply -n ${K8S_NAMESPACE} -f k8s/mysql-deployment.yaml
          kubectl apply -n ${K8S_NAMESPACE} -f k8s/spring-deployment.yaml

          kubectl set image -n ${K8S_NAMESPACE} deployment/spring-app spring-app=${DOCKER_REPO}:${IMAGE_TAG}
          kubectl rollout status -n ${K8S_NAMESPACE} deployment/spring-app

          kubectl get pods -n ${K8S_NAMESPACE}
          kubectl get svc  -n ${K8S_NAMESPACE}
        '''
      }
    }
  }
}
