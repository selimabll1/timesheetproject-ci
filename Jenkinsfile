pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(true)
    disableConcurrentBuilds()
    timeout(time: 60, unit: 'MINUTES')
  }

  tools {
    // ⚠️ Mets ici les NOMS exacts configurés dans Jenkins > Global Tool Configuration
    jdk   'JAVA_HOME'
    maven 'M2_HOME'
  }

  environment {
    // Sonar
    SONAR_PROJECT_KEY = 'timesheet-devops'

    // Docker
    DOCKER_IMAGE    = 'salima20033/timesheet-devops'
    DOCKER_CREDS_ID = 'dockerhub-creds'

    // K8s
    K8S_NAMESPACE = 'devops'

    // Helps with slow networks
    DOCKER_CLIENT_TIMEOUT = '600'
    COMPOSE_HTTP_TIMEOUT  = '600'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'ls -la'
      }
    }

    stage('Build Maven') {
      steps {
        sh 'mvn -B clean package -Dmaven.test.skip=true'
        sh 'ls -la target || true'
      }
    }

    stage('Ensure Dockerfile exists') {
      steps {
        sh '''
          set -euo pipefail

          if [ ! -f Dockerfile ]; then
            echo "⚠️ Dockerfile not found in repo. Creating it in workspace..."
            cat > Dockerfile <<'EOF'
FROM eclipse-temurin:17-jre
WORKDIR /app
EXPOSE 8082
COPY target/timesheet-devops-1.0.jar app.jar
ENTRYPOINT ["java","-jar","app.jar"]
EOF
          fi

          echo "Dockerfile content:"
          sed -n '1,200p' Dockerfile

          test -f target/timesheet-devops-1.0.jar
        '''
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
        sh '''
          set -euo pipefail
          echo "DOCKER_HOST=${DOCKER_HOST:-unix:///var/run/docker.sock}"
          docker version
          docker info > /dev/null
          test -S /var/run/docker.sock
          # quick connectivity check to docker hub registry
          curl -fsS https://registry-1.docker.io/v2/ >/dev/null
        '''
      }
    }

    stage('Docker Build & Push') {
      steps {
        withCredentials([usernamePassword(credentialsId: "${env.DOCKER_CREDS_ID}", usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            set -euo pipefail

            TAG_BUILD="${DOCKER_IMAGE}:${BUILD_NUMBER}"
            TAG_LATEST="${DOCKER_IMAGE}:latest"

            echo "Building: $TAG_BUILD and $TAG_LATEST"
            docker build -t "$TAG_BUILD" -t "$TAG_LATEST" .

            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin

            push_with_backoff () {
              IMG="$1"
              MAX=8
              n=1
              delay=15

              while true; do
                echo "=== docker push attempt ${n}/${MAX}: ${IMG} ==="
                if docker push "$IMG"; then
                  echo "✅ Push OK: $IMG"
                  return 0
                fi

                if [ "$n" -ge "$MAX" ]; then
                  echo "❌ Push failed after ${MAX} attempts: $IMG"
                  return 1
                fi

                echo "⚠️ Push failed (Docker Hub can return 502). Sleeping ${delay}s then retry..."
                sleep "$delay"
                n=$((n+1))
                delay=$((delay*2))
                [ "$delay" -gt 180 ] && delay=180
              done
            }

            # push both tags (retries handle 502)
            push_with_backoff "$TAG_BUILD"
            push_with_backoff "$TAG_LATEST"

            docker logout || true
          '''
        }
      }
    }

    stage('Deploy Kubernetes') {
      steps {
        sh '''
          set -euo pipefail

          command -v minikube >/dev/null 2>&1 || { echo "minikube not found on agent"; exit 1; }

          minikube kubectl -- get ns "${K8S_NAMESPACE}" >/dev/null 2>&1 || \
            minikube kubectl -- create ns "${K8S_NAMESPACE}"

          if [ -d k8s ]; then
            minikube kubectl -- apply -n "${K8S_NAMESPACE}" -f k8s
          else
            YAMLS=$(ls *.yaml 2>/dev/null || true)
            [ -n "$YAMLS" ] || { echo "No k8s manifests found (k8s/ or *.yaml)"; exit 1; }
            minikube kubectl -- apply -n "${K8S_NAMESPACE}" -f $YAMLS
          fi

          minikube kubectl -- rollout status -n "${K8S_NAMESPACE}" deploy/spring-app --timeout=180s
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
