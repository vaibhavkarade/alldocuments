pipeline {
    agent any
    stages {
        stage ('build') {
            steps {
                sh ''
            }
        }
        stage ('test') {
            steps{
             sh ''
            }
        }
    }
}




pipeline {
    agent {
        label ''
    }
    stages {
        stage ('build') {
            steps {
                sh ''
            }
        }
        stage ('test') {
            steps{
             sh ''
            }
        }
    }
}