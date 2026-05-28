terraform {
  backend "gcs" {
    bucket = "spotify-pipeline-infra-260529-tfstate"
    prefix = "envs/dev"
  }
}
