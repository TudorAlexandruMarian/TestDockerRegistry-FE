pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    IMAGE_NAME    = 'testdockerregistry-fe'
    K8S_NAMESPACE = 'testdockerregistry-fe'
  }

  stages {
    stage('CI') {
      steps {
        sh '''
          set -eu
          docker run --rm \
            -v "$PWD":/app \
            -w /app \
            node:22 \
            sh -c "npm ci && npm run lint && npm run build"
        '''
      }
    }

    stage('Build and push') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub',
          usernameVariable: 'DOCKERHUB_USER',
          passwordVariable: 'DOCKERHUB_PASS'
        )]) {
          sh '''
            set -eu
            echo "$DOCKERHUB_PASS" | docker login -u "$DOCKERHUB_USER" --password-stdin
            IMAGE="${DOCKERHUB_USER}/${IMAGE_NAME}"
            docker build -t "${IMAGE}:${GIT_COMMIT}" -t "${IMAGE}:latest" .
            docker push "${IMAGE}:${GIT_COMMIT}"
            docker push "${IMAGE}:latest"
            docker logout
          '''
        }
      }
    }

    stage('Deploy') {
      steps {
        withCredentials([
          file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG'),
          usernamePassword(
            credentialsId: 'dockerhub',
            usernameVariable: 'DOCKERHUB_USER',
            passwordVariable: 'DOCKERHUB_PASS'
          )
        ]) {
          sh '''
            set -eu
            IMAGE="${DOCKERHUB_USER}/${IMAGE_NAME}:${GIT_COMMIT}"
            kubectl apply -f k8s/namespace.yaml
            kubectl -n "${K8S_NAMESPACE}" create secret docker-registry dockerhub-pull \
              --docker-server=https://index.docker.io/v1/ \
              --docker-username="${DOCKERHUB_USER}" \
              --docker-password="${DOCKERHUB_PASS}" \
              --dry-run=client -o yaml | kubectl apply -f -
            sed "s|IMAGE_PLACEHOLDER|${IMAGE}|g" k8s/deployment.yaml | kubectl apply -f -
            kubectl apply -f k8s/service.yaml
            kubectl -n "${K8S_NAMESPACE}" rollout status deployment/testdockerregistry-fe --timeout=180s
            kubectl -n "${K8S_NAMESPACE}" get pods,svc
          '''
        }
      }
    }
  }
}
