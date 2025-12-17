pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(true)
  }

  tools {
    jdk 'JAVA_HOME'
    maven 'M2_HOME'
  }

  environment {
    SONAR_PROJECT_KEY = 'timesheet-devops'
    DOCKER_IMAGE      = 'salima20033/timesheet-devops'
    DOCKER_CREDS_ID   = 'dockerhub-creds'
    K8S_NAMESPACE     = 'devops'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build Maven') {
      steps {
        sh 'mvn -B clean package -Dmaven.test.skip=true'
      }
    }

    stage('MVN SONARQUBE') {
      steps {
        withSonarQubeEnv('sonar') {
          sh """
            set -euo pipefail
            echo "SONAR_HOST_URL=\$SONAR_HOST_URL"
            curl --retry 30 --retry-connrefused --retry-delay 5 --max-time 10 -fsS "\$SONAR_HOST_URL/api/system/status" | grep -q '"status":"UP"'
            mvn -B -Dmaven.test.skip=true sonar:sonar -Dsonar.projectKey=${SONAR_PROJECT_KEY}
          """
        }
      }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Docker Check') {
      steps {
        sh """
          set -euo pipefail
          echo "DOCKER_HOST=\${DOCKER_HOST:-unix:///var/run/docker.sock}"
          docker version
          docker info > /dev/null
        """
      }
    }

    stage('Docker Build & Push') {
      steps {
        script {
          def tagBuild  = "${DOCKER_IMAGE}:${env.BUILD_NUMBER}"
          def tagLatest = "${DOCKER_IMAGE}:latest"

          sh """
            set -euo pipefail
            test -f Dockerfile
            docker build -t ${tagBuild} -t ${tagLatest} .
          """

          withCredentials([usernamePassword(credentialsId: DOCKER_CREDS_ID, usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
            sh """
              set -euo pipefail
              echo "\$DH_PASS" | docker login -u "\$DH_USER" --password-stdin
            """

            // ✅ Retry robuste sur les pushes (502 / réseau)
            retry(3) {
              sh """
                set -euo pipefail

                push_with_retry () {
                  IMG="\$1"
                  n=0
                  until docker push "\$IMG"; do
                    n=\$((n+1))
                    if [ "\$n" -ge 4 ]; then
                      echo "❌ Push failed after \$n attempts: \$IMG"
                      return 1
                    fi
                    echo "⚠️ Push failed (attempt \$n) for \$IMG. Sleeping 20s then retry..."
                    sleep 20
                  done
                }

                push_with_retry "${tagBuild}"
                push_with_retry "${tagLatest}"
              """
            }

            sh 'docker logout || true'
          }
        }
      }
    }

    stage('Deploy Kubernetes') {
      steps {
        sh """
          set -euo pipefail
          minikube kubectl -- get ns ${K8S_NAMESPACE} >/dev/null 2>&1 || minikube kubectl -- create ns ${K8S_NAMESPACE}

          if [ -d k8s ]; then
            minikube kubectl -- apply -n ${K8S_NAMESPACE} -f k8s
          else
            YAMLS=\$(ls *.yaml 2>/dev/null || true)
            [ -n "\$YAMLS" ] || (echo "No k8s manifests found" && exit 1)
            minikube kubectl -- apply -n ${K8S_NAMESPACE} -f \$YAMLS
          fi

          minikube kubectl -- rollout status -n ${K8S_NAMESPACE} deploy/spring-app --timeout=180s
        """
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
    }
  }
}
